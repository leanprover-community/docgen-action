#!/usr/bin/env bash
set -euo pipefail

action_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
build_script=${1:-"$action_dir/scripts/build_docs.sh"}
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

# v4.34.0 predates doc-gen4#418, so this exercises a release where even changed
# analysis does not invalidate the cached HTML marker. The second build below
# deliberately keeps all sources unchanged, covering the remaining bug too.
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

# Get the cache paths from the action's metadata parser, rather than keeping
# another copy of the cache layout in the test. Mimic actions/cache by archiving
# only the paths that exist; optional static files need not all be generated.
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

# Retain the separate Lean build/package artifacts, but discard the entire
# docbuild workspace and published site to model a fresh docs cache restore.
rm -rf docbuild site
tar -xzf "$test_dir/docs-cache.tar.gz"

# Check that the restored state really has the partial-cache shape responsible
# for the 404: dependency HTML and analysis exist, project HTML does not, and
# Lake's HTML marker is present.
test -f docbuild/.lake/build/doc/CachedDependency/Basic.html
test -f docbuild/.lake/build/api-docs.db
test -f docbuild/.lake/build/doc-data/CachedDependency.Basic.doc
test -f docbuild/.lake/build/doc-data/CacheRegression--library.docs_built
test ! -e docbuild/.lake/build/doc/CacheRegression.html
test ! -e docbuild/.lake/build/doc/CacheRegression

# Establish that an ordinary Lake rebuild really skips the HTML pass in this
# restored state. This makes the test fail if it stops reproducing the bug.
(
    cd docbuild
    cp "$test_dir/docbuild-lakefile.toml" lakefile.toml
    MATHLIB_NO_CACHE_ON_UPDATE=1 lake update "$NAME"
    lake build "$DOCS_FACETS"
)
test ! -e docbuild/.lake/build/doc/CacheRegression.html
test ! -e docbuild/.lake/build/doc/CacheRegression

# Restore again so the action sees a pristine cache, without the configuration
# and manifest created by the plain Lake control build above.
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
