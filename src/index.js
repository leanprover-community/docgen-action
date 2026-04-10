import core from "@actions/core";
import { Buffer } from "buffer";
import { execSync } from "child_process";
import fs from "fs";
import path from "path";
import TOML from "smol-toml";

/// Map a package name into an array of modules available from that package.
/// For example, 'mathlib' maps to 'Mathlib'.
function pkgToModuleNames(pkgName) {
  // Known package->module mappings, copied from Mathlib.
  const knownMap = {
    Cli: ["Cli"],
    LeanSearchClient: ["LeanSearchClient"],
    Qq: ["Qq"],
    aesop: ["Aesop"],
    batteries: ["Batteries"],
    importGraph: ["ImportGraph"],
    mathlib: ["Mathlib", "Archive", "Counterexamples"],
    plausible: ["Plausible"],
    proofwidgets: ["ProofWidgets"],
  };
  if (pkgName in knownMap) {
    return knownMap[pkgName];
  }
  // Fallback heuristic: use the same string-to-UpperCamelCase algorithm that `lake new` uses.
  const upperCamelCased = pkgName
    .split(/[-_]/)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join("");
  console.log(
    `Warning: Unknown package ${pkgName}, predicted module name: ${upperCamelCased}. If this is the wrong module name and causes a cache miss, please open an issue on leanprover-community/docgen-action.`,
  );
  return [upperCamelCased];
}

/**
 * Parse the Lake package definitions.
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

  var lakeManifestContents;
  try {
    lakeManifestContents = fs.readFileSync("lake-manifest.json", "utf-8");
  } catch (error) {
    throw new Error(
      `Could not find \`lake-manifest.json\`.\nNote: nested error: ${error}.\nHint: run \`lake update\` and commit the generated \`lake-manifest.json\` file.`,
    );
  }

  // Determine which dependencies to cache.
  // Implicit dependencies are packages included with Lean itself,
  // explicit dependencies are those specified (transitively) as a dependency in lakefiles,
  // and the full list of those can be found in the manifest.
  const lakeManifest = JSON.parse(lakeManifestContents);
  const explicitDependencies = lakeManifest.packages.flatMap((pkg) =>
    pkgToModuleNames(pkg.name),
  );
  const implicitDependencies = ["Init", "Lake", "Lean", "Std"];
  const cacheablePaths = explicitDependencies
    .concat(implicitDependencies)
    .map((dep) => `docbuild/.lake/build/doc/${dep}`);
  // Also cache doc-data which contains per-module declaration-data-*.bmp files.
  // These are read by `doc-gen4 index` to produce the combined declaration-data.bmp.
  // Without caching these, search breaks when HTML is restored from cache but
  // the .bmp files are missing (causing the index to only contain project-specific
  // declarations, not dependencies like Mathlib).
  cacheablePaths.push("docbuild/.lake/build/doc-data");
  // Also cache static files needed for the build to succeed.
  // Compare doc-gen4 lakefile.
  cacheablePaths.push(
    "docbuild/.lake/build/doc/declarations/declaration-data.bmp",
  );
  cacheablePaths.push("docbuild/.lake/build/api-docs.db");
  cacheablePaths.push("docbuild/.lake/build/doc-manifest.json");
  cacheablePaths.push("docbuild/.lake/build/doc/style.css");
  cacheablePaths.push("docbuild/.lake/build/doc/favicon.svg");
  cacheablePaths.push("docbuild/.lake/build/doc/declaration-data.js");
  cacheablePaths.push("docbuild/.lake/build/doc/color-scheme.js");
  cacheablePaths.push("docbuild/.lake/build/doc/nav.js");
  cacheablePaths.push("docbuild/.lake/build/doc/jump-src.js");
  cacheablePaths.push("docbuild/.lake/build/doc/expand-nav.js");
  cacheablePaths.push("docbuild/.lake/build/doc/how-about.js");
  cacheablePaths.push("docbuild/.lake/build/doc/search.js");
  cacheablePaths.push("docbuild/.lake/build/doc/mathjax-config.js");
  cacheablePaths.push("docbuild/.lake/build/doc/instances.js");
  cacheablePaths.push("docbuild/.lake/build/doc/importedBy.js");
  cacheablePaths.push("docbuild/.lake/build/doc/index.html");
  cacheablePaths.push("docbuild/.lake/build/doc/404.html");
  cacheablePaths.push("docbuild/.lake/build/doc/navbar.html");
  cacheablePaths.push("docbuild/.lake/build/doc/search.html");
  cacheablePaths.push("docbuild/.lake/build/doc/foundational_types.html");
  cacheablePaths.push("docbuild/.lake/build/doc/references.html");
  cacheablePaths.push("docbuild/.lake/build/doc/references.bib");
  cacheablePaths.push("docbuild/.lake/build/doc/tactics.html");
  cacheablePaths.push("docbuild/.lake/build/doc/find/index.html");
  cacheablePaths.push("docbuild/.lake/build/doc/find/find.js");

  // Output status to GitHub Actions.
  core.setOutput("name", lakefile.name);
  core.setOutput("default_targets", JSON.stringify(lakefile.defaultTargets));
  core.setOutput(
    "docs_facets",
    lakefile.defaultTargets.map((target) => `${target}:docs`).join(" "),
  );
  core.setOutput("cached_docbuild_dependencies", cacheablePaths.join("\n"));
} catch (error) {
  console.error("Error parsing Lake package description:", error.message);
  process.exit(1);
}
