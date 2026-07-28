#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { writeFileSync } from "node:fs";
import { join, resolve } from "node:path";

const projectRoot = resolve(import.meta.dirname, "..");
const resourcesRoot = join(projectRoot, "Sources", "SlimLuma", "Resources");
const referenceLocale = process.argv[2] ?? "zh-Hans";
const referencePath = join(
  resourcesRoot,
  `${referenceLocale}.lproj`,
  "Localizable.strings",
);
const outputPath = join(resourcesRoot, "LocalizationKeys.json");

const output = execFileSync(
  "/usr/bin/plutil",
  ["-convert", "json", "-o", "-", referencePath],
  { encoding: "utf8" },
);
const dictionary = JSON.parse(output);
const keys = Object.keys(dictionary).sort((left, right) =>
  left.localeCompare(right, "zh-Hans"),
);

if (keys.length < 750) {
  throw new Error(
    `Refusing to freeze an incomplete localization table (${keys.length} keys)`,
  );
}
if (new Set(keys).size !== keys.length) {
  throw new Error("Reference localization contains duplicate keys");
}

writeFileSync(outputPath, `${JSON.stringify(keys, null, 2)}\n`);
console.log(`Frozen ${keys.length} localization keys from ${referenceLocale}.`);
