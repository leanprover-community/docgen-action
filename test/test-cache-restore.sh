#!/usr/bin/env bash
set -euo pipefail

action_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
build_script=${1:-"$action_dir/scripts/build_docs.sh"}
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

# The sources do not change between the builds, so the cache restore alone
# decides whether the HTML pass runs.
cp -R "$action_dir/test/fixtures/cache-restore" "$test_dir/project"
cd "$test_dir/project"
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
        echo "FAIL: the deployed project pages are missing" >&2
        return 1
    fi
    grep -q 'rootGreeting' site/docs/CacheRegression.html
    grep -q 'projectGreeting' site/docs/CacheRegression/Basic.html
    grep -q 'dependencyGreeting' site/docs/CachedDependency/Basic.html
    test -f site/docs/Init/Prelude.html
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
test -s "$test_dir/cache-paths"
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
test -f docbuild/.lake/build/doc/CachedDependency/Basic.html
test -f docbuild/.lake/build/api-docs.db
test -f docbuild/.lake/build/doc-data/CachedDependency.Basic.doc
test -f docbuild/.lake/build/doc-data/CacheRegression--library.docs_built
test ! -e docbuild/.lake/build/doc/CacheRegression.html
test ! -e docbuild/.lake/build/doc/CacheRegression

# Check that a plain Lake build skips the HTML pass in this state. The build of
# the action below must then write the pages of the project.
(
    cd docbuild
    cp "$test_dir/docbuild-lakefile.toml" lakefile.toml
    MATHLIB_NO_CACHE_ON_UPDATE=1 lake update "$NAME"
    lake build "$DOCS_FACETS"
)
test ! -e docbuild/.lake/build/doc/CacheRegression.html
test ! -e docbuild/.lake/build/doc/CacheRegression

# Restore the cache again, so that the action does not see the configuration
# and the manifest of the plain Lake build above.
rm -rf docbuild
tar -xzf "$test_dir/docs-cache.tar.gz"
core_marker=docbuild/.lake/build/doc-data/core-Init.doc
dependency_marker=docbuild/.lake/build/doc-data/CachedDependency.Basic.doc
core_marker_time=$(stat -c '%y' "$core_marker")
dependency_marker_time=$(stat -c '%y' "$dependency_marker")

echo "Rebuilding unchanged sources after restoring the documentation cache"
bash "$build_script"
check_project_pages
if [[ $(stat -c '%y' "$core_marker") != "$core_marker_time" ||
      $(stat -c '%y' "$dependency_marker") != "$dependency_marker_time" ]]; then
    echo "FAIL: cached core or dependency analysis was regenerated" >&2
    exit 1
fi
echo "PASS: the restored cache produces complete project documentation"
