#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status,
# treat unset variables as an error, and ensure errors in pipelines are not masked.
set -euo pipefail

# Build the HTML documentation of the project and copy it to `$HOMEPAGE/docs`.

# Determine the `doc-gen4` revision to use as a dependency,
# based on the `lean-toolchain` of this project:
# either the `v4.X.Y` or `v4.X.Y-rcZ` tags, or the `main` or `nightly-testing` branches.
determine_doc_gen_rev() {
    local toolchain_content
    local toolchain_repository
    local toolchain_revision
    
    # We are going to use the toolchain file to determine the revision,
    # or fall back to the `main` branch.
    if [[ ! -f "lean-toolchain" ]]; then
        echo "Warning: lean-toolchain file not found, falling back to main branch" >&2
        echo "main"
        return 0
    fi
    
    toolchain_content=$(< lean-toolchain)
    
    # Split on repository name and revision.
    toolchain_repository=$(echo "$toolchain_content" | cut -f1 -d:)
    toolchain_revision=$(echo "$toolchain_content" | cut -f2 -d:)
    
    if [[ "$toolchain_repository" != "leanprover/lean4" ]]; then
        echo "Warning: Expected 'leanprover/lean4' as first field in lean-toolchain, got '$toolchain_repository'. Falling back to main branch" >&2
        echo "main"
        return 0
    fi
    
    if [[ "$toolchain_revision" =~ ^v4\.[0-9]+\.[0-9]+(-rc[0-9]+)?$ ]]; then
        echo "$toolchain_revision"
        return 0
    fi
    
    # We match nightly-testing branches by looking for a revision starting with `nightly`.
    if [[ "$toolchain_revision" == *"nightly"* ]]; then
        echo "Warning: Detected nightly build '$toolchain_revision', falling back to nightly-testing branch" >&2
        echo "nightly-testing"
        return 0
    fi
    
    # Default fallback
    echo "Warning: Unexpected toolchain format '$toolchain_revision', falling back to main branch" >&2
    echo "main"
    return 0
}

# Create a temporary docbuild folder
mkdir -p docbuild

# Determine the doc-gen4 revision
DOC_GEN_REV=$(determine_doc_gen_rev)

# Template lakefile.toml
cat << EOF > docbuild/lakefile.toml
name = "docbuild"
reservoir = false
version = "0.1.0"
packagesDir = "../.lake/packages"

[[require]]
scope = "leanprover"
name = "doc-gen4"
rev = "$DOC_GEN_REV"

[[require]]
name = "$NAME"
path = "../"
EOF

# Initialise docbuild as a Lean project
cd docbuild

# Place references.bib in the location expected by doc-gen4
if [ -f "../$REFERENCES" ]; then
  mkdir -p docs
  cp "../$REFERENCES" ./docs/references.bib
fi

# Disable an error message due to a non-blocking bug. See Zulip
MATHLIB_NO_CACHE_ON_UPDATE=1 ~/.elan/bin/lake update "$NAME"

# Empty the output directory, so that the site holds only the pages of this
# build. Keep references.bib: Lake skips the step that writes it when the
# references file is unchanged.
if [ -d .lake/build/doc ]; then
  find .lake/build/doc -mindepth 1 -maxdepth 1 ! -name references.bib -exec rm -rf {} +
fi
# The HTML step writes the per-module search data again.
rm -f .lake/build/doc-data/declaration-data-*.bmp .lake/build/doc-data/backrefs-*.json
# Delete the markers of the HTML step. Lake checks a marker, not the pages, so a
# marker from an earlier build would skip the step although the pages are gone.
rm -f .lake/build/doc-data/*.docs_built{,.trace,.hash}
rm -f .lake/build/doc-data/*.docsHeader_built{,.trace,.hash}

# DOCS_FACETS is supplied by action.yml.
# shellcheck disable=SC2153
read -r -a docs_facets <<< "$DOCS_FACETS"

# Build the docs. doc-gen4 refuses a database written by a version with a
# different schema. A restored database can hit this when the doc-gen4 revision
# changes under an unchanged toolchain. In that case, build once more from a
# clean build directory. Any other failure stops the script.
build_log=$(mktemp)
trap 'rm -f "$build_log"' EXIT
if ! ~/.elan/bin/lake build "${docs_facets[@]}" 2>&1 | tee "$build_log"; then
  if grep -q "Database schema is outdated" "$build_log"; then
    echo "::warning::The cached documentation database does not match this doc-gen4 version. Rebuilding the documentation from a clean state."
    rm -rf .lake/build
    ~/.elan/bin/lake build "${docs_facets[@]}"
  else
    exit 1
  fi
fi

# Copy documentation to `$HOMEPAGE/docs`
cd ../
mkdir -p "$HOMEPAGE"
sudo chown -R runner "$HOMEPAGE"
# Replace any earlier copy of the site.
rm -rf -- "$HOMEPAGE/docs"
cp -r docbuild/.lake/build/doc "$HOMEPAGE/docs"
