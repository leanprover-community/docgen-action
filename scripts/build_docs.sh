#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status,
# treat unset variables as an error, and ensure errors in pipelines are not masked.
set -euo pipefail

# Build HTML documentation for the project
# The output will be located in docs/docs

# Function to validate and determine doc-gen4 revision
determine_doc_gen_rev() {
    local toolchain_content
    local first_field
    local second_field
    
    # Read the lean-toolchain file
    if [[ ! -f "lean-toolchain" ]]; then
        echo "Warning: lean-toolchain file not found, falling back to main branch" >&2
        echo "main"
        return 0
    fi
    
    toolchain_content=$(< lean-toolchain)
    
    # Extract first and second fields
    first_field=$(echo "$toolchain_content" | cut -f1 -d:)
    second_field=$(echo "$toolchain_content" | cut -f2 -d:)
    
    # Validate first field should be leanprover/lean4
    if [[ "$first_field" != "leanprover/lean4" ]]; then
        echo "Warning: Expected 'leanprover/lean4' as first field in lean-toolchain, got '$first_field'. Falling back to main branch" >&2
        echo "main"
        return 0
    fi
    
    # Check if second field matches v4.X.Y or v4.X.Y-rcZ pattern
    if [[ "$second_field" =~ ^v4\.[0-9]+\.[0-9]+(-rc[0-9]+)?$ ]]; then
        echo "$second_field"
        return 0
    fi
    
    # Check if it contains 'nightly'
    if [[ "$second_field" == *"nightly"* ]]; then
        echo "Warning: Detected nightly build '$second_field', falling back to nightly-testing branch" >&2
        echo "nightly-testing"
        return 0
    fi
    
    # Default fallback
    echo "Warning: Unexpected toolchain format '$second_field', falling back to main branch" >&2
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

# Disable an error message due to a non-blocking bug. See Zulip
MATHLIB_NO_CACHE_ON_UPDATE=1 ~/.elan/bin/lake update $NAME

# Build the docs
~/.elan/bin/lake build $DOCS_FACETS

# Copy documentation to `$HOMEPAGE/docs`
cd ../
mkdir -p $HOMEPAGE
sudo chown -R runner $HOMEPAGE
cp -r docbuild/.lake/build/doc $HOMEPAGE/docs
