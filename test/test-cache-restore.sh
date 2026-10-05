#!/usr/bin/env bash
set -euo pipefail

action_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
build_script=${1:-"$action_dir/scripts/build_docs.sh"}
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

fail() {
    if [[ ${GITHUB_ACTIONS:-} == true ]]; then
        echo "::error::$*"
    else
        echo "FAIL: $*" >&2
    fi
    exit 1
}
expect_file() {
    test -f "$1" || fail "$1 is missing"
}
expect_absent() {
    test ! -e "$1" || fail "$1 exists"
}
expect_text() {
    grep -q "$2" "$1" || fail "$1 does not contain $2"
}

# This test covers #33: after a cache restore, the site has no pages of the
# project. The test uses the newest doc-gen4 tag of a stable Lean release, so
# that a change in a new doc-gen4 release shows up here. `LEAN_VERSION`
# overrides the release. The sources do not change between the builds, so the
# test covers doc-gen4 releases with and without leanprover/doc-gen4#418.
lean_version=${LEAN_VERSION:-$(git ls-remote --tags --refs https://github.com/leanprover/doc-gen4 'v4.*' |
    sed 's|.*refs/tags/||' | grep -E '^v4\.[0-9]+\.[0-9]+$' | sort -V | tail -1)}
if [[ -z $(git ls-remote --tags https://github.com/leanprover/doc-gen4 "refs/tags/$lean_version") ]]; then
    fail "doc-gen4 has no tag $lean_version"
fi
echo "Using Lean $lean_version"

cp -R "$action_dir/test/fixtures/cache-restore" "$test_dir/project"
cd "$test_dir/project"
printf 'leanprover/lean4:%s\n' "$lean_version" > lean-toolchain
# The fixture has no git remote, so doc-gen4 links to the source files instead.
export DOCGEN_SRC=file
export NAME=CacheRegression
export DOCS_FACETS=CacheRegression:docs
export HOMEPAGE=site
export REFERENCES=references.bib

lake update
lake build

check_project_pages() {
    if ! test -f site/docs/CacheRegression.html ||
       ! test -f site/docs/CacheRegression/Basic.html; then
        fail "the deployed project pages are missing"
    fi
    expect_text site/docs/CacheRegression.html rootGreeting
    expect_text site/docs/CacheRegression/Basic.html projectGreeting
    expect_text site/docs/CachedDependency/Basic.html dependencyGreeting
    expect_file site/docs/Init/Prelude.html
}

echo "Building documentation without a cache"
bash "$build_script"
check_project_pages

# Read the cache paths from the output of `dist/index.js`, so that the test
# uses the same paths as the action. Archive only the paths that exist, as
# `actions/cache` does, because the build does not write every static file.
touch "$test_dir/metadata"
GITHUB_OUTPUT="$test_dir/metadata" node "$action_dir/dist/index.js"
awk '/^cached_docbuild_dependencies<</ {
    delimiter = substr($0, index($0, "<<") + 2)
    while ((getline) > 0 && $0 != delimiter) print
    exit
}' "$test_dir/metadata" > "$test_dir/cache-paths"
test -s "$test_dir/cache-paths" || fail "dist/index.js reports no cache paths"
while IFS= read -r cache_path; do
    if test -e "$cache_path"; then
        printf '%s\n' "$cache_path"
    fi
done < "$test_dir/cache-paths" > "$test_dir/existing-paths"
tar -czf "$test_dir/docs-cache.tar.gz" -T "$test_dir/existing-paths"
cp docbuild/lakefile.toml "$test_dir/docbuild-lakefile.toml"

# Keep the Lean build of the project. Replace the docbuild workspace and the
# site with the cache contents, as a cache restore on a new runner does.
rm -rf docbuild site
tar -xzf "$test_dir/docs-cache.tar.gz"

# Check the restored state: the HTML of the dependency, the database, the
# analysis markers and the HTML marker exist, and the HTML of the project does
# not.
expect_file docbuild/.lake/build/doc/CachedDependency/Basic.html
expect_file docbuild/.lake/build/api-docs.db
expect_file docbuild/.lake/build/doc-data/CachedDependency.Basic.doc
expect_file docbuild/.lake/build/doc-data/CacheRegression.Basic.doc
expect_file docbuild/.lake/build/doc-data/CacheRegression--library.docs_built
expect_absent docbuild/.lake/build/doc/CacheRegression.html
expect_absent docbuild/.lake/build/doc/CacheRegression

# Check that a plain Lake build skips the HTML pass in this state. The build of
# the action below must then write the pages of the project.
(
    cd docbuild
    cp "$test_dir/docbuild-lakefile.toml" lakefile.toml
    MATHLIB_NO_CACHE_ON_UPDATE=1 lake update "$NAME"
    lake build "$DOCS_FACETS"
)
expect_absent docbuild/.lake/build/doc/CacheRegression.html
expect_absent docbuild/.lake/build/doc/CacheRegression

# Restore the cache again, so that the action does not see the configuration
# and the manifest of the plain Lake build above.
rm -rf docbuild
tar -xzf "$test_dir/docs-cache.tar.gz"
analysis_markers=(
    docbuild/.lake/build/doc-data/core-Init.doc
    docbuild/.lake/build/doc-data/CachedDependency.Basic.doc
    docbuild/.lake/build/doc-data/CacheRegression.Basic.doc
)
declare -A analysis_marker_times
for marker in "${analysis_markers[@]}"; do
    analysis_marker_times[$marker]=$(stat -c '%y' "$marker")
done

echo "Rebuilding unchanged sources after restoring the documentation cache"
bash "$build_script"
check_project_pages
for marker in "${analysis_markers[@]}"; do
    if [[ $(stat -c '%y' "$marker") != "${analysis_marker_times[$marker]}" ]]; then
        fail "the build analyzed $(basename "$marker" .doc) again"
    fi
done
echo "PASS: the restored cache produces complete project documentation"
