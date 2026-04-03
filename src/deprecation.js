import core from "@actions/core";

/**
 * DEPRECATION HANDLER
 *
 * This file handles backward compatibility for parameter name changes.
 *
 * UPGRADE PATH FOR MAINTAINERS:
 * When removing deprecation support in a future version:
 * 1. Delete this entire file (src/deprecation.js)
 * 2. Remove the "Handle deprecation and set environment variables" step from action.yml
 * 3. Remove the old parameter definitions from action.yml inputs:
 *    - Remove 'api_docs' input
 *    - Remove 'build_args' input
 *    - Remove 'lake_package_directory' input
 * 4. Update action.yml to use direct input references instead of environment variables:
 *    - Change `${{ env.LAKE_PACKAGE_DIRECTORY }}` back to `${{ inputs.lake-package-directory }}`
 *    - Change `${{ env.API_DOCS }}` back to `${{ inputs.api-docs }}`
 *    - Change `${{ env.BUILD_ARGS }}` back to `${{ inputs.build-args }}`
 * 5. Update README.md to remove the "Deprecated Parameters" section
 * 6. Update rollup.config.js to remove the deprecation.js build target
 */

// Helper function to get input with deprecation support
function getInputWithDeprecation(newName, oldName, options = {}) {
  const newValue = core.getInput(newName, options);
  const oldValue = core.getInput(oldName, options);

  if (oldValue) {
    console.warn(
      `Warning: The input parameter '${oldName}' is deprecated and will be removed in a future version. Please use '${newName}' instead.`,
    );
    return oldValue;
  }

  return newValue;
}

// Handle deprecation and set environment variables
function handleDeprecation() {
  // Handle lake-package-directory deprecation
  const lakePackageDirectory =
    getInputWithDeprecation(
      "lake-package-directory",
      "lake_package_directory",
    ) || ".";
  core.exportVariable("LAKE_PACKAGE_DIRECTORY", lakePackageDirectory);

  // Handle api-docs deprecation
  const apiDocs = getInputWithDeprecation("api-docs", "api_docs") || "true";
  core.exportVariable("API_DOCS", apiDocs);

  // Handle build-args deprecation
  const buildArgs =
    getInputWithDeprecation("build-args", "build_args") ||
    "--log-level=warning";
  core.exportVariable("BUILD_ARGS", buildArgs);
}

// Run the deprecation handler
handleDeprecation();
