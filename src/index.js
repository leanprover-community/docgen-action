import core from "@actions/core";
import { Buffer } from "buffer";
import { execSync } from "child_process";
import fs from "fs";
import path from "path";
import TOML from "smol-toml";

/**
 * Parse the Lake package definitions.
 */
try {
  var lakefileContents;
  try {
    lakefileContents = fs.readFileSync("lakefile.toml", "utf-8");
  } catch (error) {
    throw new Error(
      `Could not find \`lakefile.toml\`.\nNote: nested error: ${error}.\nHint: make sure the \`lake_package_directory\` input is set to a directory containing a lakefile.`,
    );
  }
  const lakefile = TOML.parse(lakefileContents);

  var lakeManifestContents;
  try {
    lakeManifestContents = fs.readFileSync("lake-manifest.json", "utf-8");
  } catch (error) {
    throw new Error(
      `Could not find \`lake-manifest.json\`.\nNote: nested error: ${error}.\nHint: run \`lake update\` and commit the generated \`lake-manifest.json\` file.`,
    );
  }
  const lakeManifest = JSON.parse(lakeManifestContents);
  const dependencyNames = lakeManifest.packages.map((pkg) => pkg.name);

  // Output status to GitHub Actions.
  core.setOutput("name", lakefile.name);
  core.setOutput("default_targets", JSON.stringify(lakefile.defaultTargets));
  core.setOutput(
    "docs_facets",
    lakefile.defaultTargets.map((target) => `${target}:docs`).join(" "),
  );
  core.setOutput(
    "cached_docbuild_dependencies",
    dependencyNames.map((dep) => `docbuild/.lake/build/doc/${dep}`).join("\n"),
  );
} catch (error) {
  console.error("Error parsing Lake package description:", error.message);
  process.exit(1);
}
