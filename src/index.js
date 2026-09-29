import core from "@actions/core";
import fs from "fs";
import TOML from "smol-toml";

/**
 * Parse the Lake package definitions and publish the values that the later
 * steps need: the package name and the `docs` facets of the default targets.
 */
try {
  var lakefileContents;
  try {
    lakefileContents = fs.readFileSync("lakefile.toml", "utf-8");
  } catch (error) {
    throw new Error(
      `Could not find \`lakefile.toml\`.\nNote: nested error: ${error}.\nHint: make sure the \`lake-package-directory\` input is set to a directory containing a lakefile.`,
    );
  }
  const lakefile = TOML.parse(lakefileContents);

  // The docs build resolves the dependencies of the project from the manifest,
  // and the cache key hashes it. Fail early with a clear hint when it is absent.
  if (!fs.existsSync("lake-manifest.json")) {
    throw new Error(
      "Could not find `lake-manifest.json`.\nHint: run `lake update` and commit the generated `lake-manifest.json` file.",
    );
  }

  core.setOutput("name", lakefile.name);
  core.setOutput("default_targets", JSON.stringify(lakefile.defaultTargets));
  core.setOutput(
    "docs_facets",
    lakefile.defaultTargets.map((target) => `${target}:docs`).join(" "),
  );
} catch (error) {
  console.error("Error parsing Lake package description:", error.message);
  process.exit(1);
}
