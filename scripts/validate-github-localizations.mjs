#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import {
  existsSync,
  readFileSync,
  readdirSync,
  statSync,
} from "node:fs";
import { dirname, join, relative, resolve, sep } from "node:path";
import {
  generatedReadmePath,
  githubLocaleCodes,
  githubLocales,
} from "./github-locales.mjs";

const projectRoot = resolve(import.meta.dirname, "..");
const failures = [];

function fail(message) {
  failures.push(message);
}

function read(path) {
  if (!existsSync(path)) {
    fail(`Missing file: ${relative(projectRoot, path)}`);
    return "";
  }
  return readFileSync(path, "utf8");
}

const info = JSON.parse(
  execFileSync(
    "/usr/bin/plutil",
    [
      "-convert",
      "json",
      "-o",
      "-",
      join(projectRoot, "Support", "Info.plist"),
    ],
    { encoding: "utf8" },
  ),
);
const version = info.CFBundleShortVersionString;
const appLocales = [...info.CFBundleLocalizations].sort();
const documentedLocales = [...githubLocaleCodes].sort();
if (JSON.stringify(appLocales) !== JSON.stringify(documentedLocales)) {
  fail(
    `GitHub locales differ from CFBundleLocalizations: ${documentedLocales.join(", ")} vs ${appLocales.join(", ")}`,
  );
}

const rootReadmes = [
  join(projectRoot, "README.md"),
  join(projectRoot, "README.zh-CN.md"),
];
const expectedDMG =
  `https://github.com/ChineseMao/SlimLuma/releases/download/v${version}/` +
  `SlimLuma-${version}-macOS-universal.dmg`;
for (const rootReadme of rootReadmes) {
  const body = read(rootReadme);
  if (!body.includes(expectedDMG)) {
    fail(`${relative(projectRoot, rootReadme)} lacks the current direct DMG link`);
  }
  for (const { canonicalReadme } of githubLocales) {
    if (!body.includes(`](${canonicalReadme})`)) {
      fail(
        `${relative(projectRoot, rootReadme)} lacks language link ${canonicalReadme}`,
      );
    }
  }
}

const expectedGeneratedReadmes = new Set(
  githubLocales.map(({ locale }) => `README.${locale}.md`),
);
const actualGeneratedReadmes = new Set(
  readdirSync(join(projectRoot, "docs", "readme")).filter((name) =>
    /^README\..+\.md$/.test(name),
  ),
);
if (
  JSON.stringify([...actualGeneratedReadmes].sort()) !==
  JSON.stringify([...expectedGeneratedReadmes].sort())
) {
  fail("docs/readme does not contain exactly the configured GitHub locales");
}

const releaseDirectory = join(
  projectRoot,
  "docs",
  "releases",
  `v${version}`,
);
const expectedReleaseNotes = new Set(
  githubLocales.map(({ locale }) => `README.${locale}.md`),
);
const actualReleaseNotes = existsSync(releaseDirectory)
  ? new Set(
      readdirSync(releaseDirectory).filter((name) =>
        /^README\..+\.md$/.test(name),
      ),
    )
  : new Set();
if (
  JSON.stringify([...actualReleaseNotes].sort()) !==
  JSON.stringify([...expectedReleaseNotes].sort())
) {
  fail(
    `docs/releases/v${version} does not contain exactly the configured locales`,
  );
}

for (const { locale } of githubLocales) {
  const generatedReadme = read(
    join(projectRoot, generatedReadmePath(locale)),
  );
  if (!generatedReadme.includes(expectedDMG)) {
    fail(`Generated ${locale} README lacks the current direct DMG link`);
  }
  const localizedRelease = read(
    join(releaseDirectory, `README.${locale}.md`),
  );
  if (!localizedRelease.includes(`<!-- locale:${locale} -->`)) {
    fail(`Release note ${locale} lacks its locale marker`);
  }
  if (!localizedRelease.includes(expectedDMG)) {
    fail(`Release note ${locale} lacks the current direct DMG link`);
  }
}

const communityFiles = [
  "CONTRIBUTING.md",
  "SECURITY.md",
  "CODE_OF_CONDUCT.md",
  "SUPPORT.md",
  "LICENSE",
];
for (const file of communityFiles) {
  if (!existsSync(join(projectRoot, file))) {
    fail(`Missing community file: ${file}`);
  }
}

const markdownFiles = [
  ...rootReadmes,
  ...githubLocales.map(({ locale }) =>
    join(projectRoot, generatedReadmePath(locale)),
  ),
  join(projectRoot, "CONTRIBUTING.md"),
  join(projectRoot, "SECURITY.md"),
  join(projectRoot, "CODE_OF_CONDUCT.md"),
  join(projectRoot, "SUPPORT.md"),
  join(projectRoot, "CHANGELOG.md"),
  join(projectRoot, "docs", "releases", `v${version}.md`),
  ...githubLocales.map(({ locale }) =>
    join(releaseDirectory, `README.${locale}.md`),
  ),
];

function validateRelativeLink(source, rawHref) {
  const href = rawHref.trim().replace(/^<|>$/g, "");
  if (
    href.length === 0 ||
    href.startsWith("#") ||
    /^(?:https?:|mailto:)/i.test(href)
  ) {
    return;
  }
  const pathPart = decodeURIComponent(href.split(/[?#]/, 1)[0]);
  if (pathPart.length === 0) {
    return;
  }
  const target = resolve(dirname(source), pathPart);
  if (
    target !== projectRoot &&
    !target.startsWith(`${projectRoot}${sep}`)
  ) {
    fail(
      `${relative(projectRoot, source)} links outside the repository: ${href}`,
    );
    return;
  }
  if (!existsSync(target)) {
    fail(
      `${relative(projectRoot, source)} has a broken link: ${href}`,
    );
    return;
  }
  if (href.endsWith("/") && !statSync(target).isDirectory()) {
    fail(
      `${relative(projectRoot, source)} expects a directory: ${href}`,
    );
  }
}

for (const source of markdownFiles) {
  const body = read(source);
  const markdownLink = /!?\[[^\]]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g;
  const htmlLink = /\bhref="([^"]+)"/g;
  for (const match of body.matchAll(markdownLink)) {
    validateRelativeLink(source, match[1]);
  }
  for (const match of body.matchAll(htmlLink)) {
    validateRelativeLink(source, match[1]);
  }
}

const workflows = [
  join(projectRoot, ".github", "workflows", "ci.yml"),
  join(projectRoot, ".github", "workflows", "release.yml"),
];
for (const workflow of workflows) {
  const body = read(workflow);
  if (!body.includes("node scripts/validate-github-localizations.mjs")) {
    fail(
      `${relative(projectRoot, workflow)} does not enforce GitHub localization validation`,
    );
  }
}

if (failures.length > 0) {
  throw new Error(
    `GitHub localization validation failed:\n- ${failures.join("\n- ")}`,
  );
}

console.log(
  `Verified GitHub internationalization: ${githubLocales.length} product READMEs, ${githubLocales.length} localized v${version} release notes, direct downloads, community files, and local links.`,
);
