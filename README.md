# Lean documentation generator action

This GitHub Action automatically builds and uploads documentation (including blueprints) for your project. It runs [`doc-gen4`](github.com/leanprover/doc-gen4) and hosts the result on GitHub Pages. It also supports building a website using Jekyll (see below).

## Installation

First, please ensure GitHub Pages is enabled for your project: go to Settings > Pages and under Build and deployment > Source select "GitHub Actions" from the dropdown menu.

Then, add this action to the end of the workflow that builds your project, and give the workflow write permissions to GitHub Pages. For blueprint support, add `blueprint: true` to the action inputs. Commit and push the changes.

When CI completes, the API documentation can be found at `https://YOUR_USERNAME.github.io/YOUR_PROJECT_NAME/docs`.

Example workflow for building the project and uploading documentation:

```yaml
name: Build project and documentation

on:
  push:
  pull_request:
  workflow_dispatch:

# Sets permissions of the GITHUB_TOKEN to allow deployment to GitHub Pages
permissions:
  contents: read # Read access to repository contents
  id-token: write # Required to upload the site to GitHub Pages
  pages: write # Write access to GitHub Pages

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout project
        uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
        with:
          fetch-depth: 0 # Fetch all history for all branches and tags

      - name: Build and lint the project.
        id: build-lean
        uses: leanprover/lean-action@f807b338d95de7813c5c50d018f1c23c9b93b4ec # v1.2.0

      - name: Build project documentation.
        id: build-docgen
        uses: leanprover-community/docgen-action@main
        with:
          # Uncomment the next line if you wish to build a blueprint alongside your repository.
          # blueprint: true
```

## Configuration options

### input: `blueprint`

Allowed values: `false`, `true`

Default value: `false`

This action can automatically build a [blueprint](https://github.com/PatrickMassot/leanblueprint/) for your project, by passing the input `blueprint: true` to the action. After CI is complete, the compiled blueprint will be available in `https://YOUR_USERNAME.github.io/YOUR_PROJECT_NAME/blueprint`.

### input: `homepage`

Default value: `home_page`

If you would like more than just a `docs` and a `blueprint` folder, this action automatically runs the [Jekyll](https://jekyllrb.com/) site generator for you. Run `jekyll new home_page` in your project folder and commit the resulting `home_page` folder. The action will automatically detect the `home_page` folder and build it for you alongside the API documentation and the blueprint. After CI is complete, the compiled site will be available in `https://YOUR_USERNAME.github.io/YOUR_PROJECT_NAME`.

### input: `build-args`

Default value: `--log-level=warning`

This GitHub Action uses https://github.com/leanprover/lean-action to build and test the repository.
This parameter determines what to pass to the `build-args` argument of https://github.com/leanprover/lean-action.

### input: `lake-package-directory`

Default value: `.`

The directory containing the Lake package to build.
This parameter is also passed as the `lake-package-directory` argument of https://github.com/leanprover/lean-action.

### input: `api-docs`

Allowed values: `false`, `true`

Default value: `true`

Set to true to build API docs alongside the rest of your documentation. (This is enabled by default but can be disabled if you are only interested in the blueprint.)

### input: `build-page`

Allowed values: `false`, `true`

Default value: `true`

Set to true to build the homepage using Jekyll alongside the rest of your documentation. (This is enabled by default but can be disabled if you are only interested in the API docs and/or blueprint.)

### input: `deploy`

Allowed values: `false`, `true`

Default value: `true`

Set to true to deploy the built documentation (API docs and/or blueprint and/or homepage) to GitHub Pages. (This is enabled by default but can be disabled for a dry run.)

## Deprecated Parameters

The following parameter names are deprecated and will be removed in a future version:

- `api_docs` → use `api-docs` instead
- `build_args` → use `build-args` instead
- `lake_package_directory` → use `lake-package-directory` instead

When using deprecated parameters, a warning message will be printed to the log, but the action will continue to work as expected. Please update your workflows to use the new parameter names to avoid future compatibility issues.

### For Maintainers: Removing Deprecation Support

When the deprecated parameters are ready to be removed, follow these steps:

1. Delete `src/deprecation.js`
2. Remove the "Handle deprecation and set environment variables" step from `action.yml`
3. Remove the old parameter definitions from `action.yml` inputs:
   - Remove `api_docs` input
   - Remove `build_args` input
   - Remove `lake_package_directory` input
4. Update `action.yml` to use direct input references instead of environment variables:
   - Change `${{ env.LAKE_PACKAGE_DIRECTORY }}` back to `${{ inputs.lake-package-directory }}`
   - Change `${{ env.API_DOCS }}` back to `${{ inputs.api-docs }}`
   - Change `${{ env.BUILD_ARGS }}` back to `${{ inputs.build-args }}`
5. Update `rollup.config.js` to remove the deprecation.js build target
6. Remove this "Deprecated Parameters" section from the README
