#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status,
# treat unset variables as an error, and ensure errors in pipelines are not masked.
set -euo pipefail

# Build HTML documentation for the project
# The output will be located in docs/docs

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
name = "$NAME"
path = "../"

[[require]]
scope = "leanprover"
name = "doc-gen4"
rev = "$DOC_GEN_REV"
EOF

# Initialise docbuild as a Lean project
cd docbuild

# Place references.bib in the location expected by doc-gen4
if [ -f ../$REFERENCES ]; then
  mkdir -p docs
  cp ../$REFERENCES ./docs/references.bib
fi

# Disable an error message due to a non-blocking bug. See Zulip
MATHLIB_NO_CACHE_ON_UPDATE=1 ~/.elan/bin/lake update $NAME

# Build the docs
~/.elan/bin/lake build $DOCS_FACETS

# Copy documentation to `$HOMEPAGE/docs`
cd ../
mkdir -p $HOMEPAGE
sudo chown -R runner $HOMEPAGE
cp -r docbuild/.lake/build/doc $HOMEPAGE/docs
