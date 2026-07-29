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
  githubDownloadNotices,
  githubLicenseNotices,
  githubLocaleCodes,
  githubLocales,
  githubReleaseLicenseNotices,
} from "./github-locales.mjs";

const projectRoot = resolve(import.meta.dirname, "..");
const failures = [];
const repositoryURL = "https://github.com/ChineseMao/SlimLuma";
const expectedCopyright =
  "Copyright © 2026 SlimLuma copyright holders. All rights reserved.";

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
const releaseState = JSON.parse(
  read(
    join(projectRoot, "docs", "releases", "release-state.json"),
  ),
);
const latestPublishedVersion = releaseState.latestPublishedVersion;
const releaseNotesVersion = releaseState.generatedReleaseNotesVersion;
const latestPublishedDownloadsAvailable =
  releaseState.latestPublishedDownloadsAvailable;
for (const [name, value] of Object.entries({
  latestPublishedVersion,
  generatedReleaseNotesVersion: releaseNotesVersion,
})) {
  if (typeof value !== "string" || !/^\d+\.\d+\.\d+$/.test(value)) {
    fail(`release-state.json has an invalid ${name}`);
  }
}
if (version === latestPublishedVersion) {
  fail("Development version must not reuse the latest published version");
}
if (typeof latestPublishedDownloadsAvailable !== "boolean") {
  fail("release-state.json has an invalid latestPublishedDownloadsAvailable");
}
if (info.NSHumanReadableCopyright !== expectedCopyright) {
  fail("Info.plist does not contain the expected copyright notice");
}
const appLocales = [...info.CFBundleLocalizations].sort();
const documentedLocales = [...githubLocaleCodes].sort();
if (JSON.stringify(appLocales) !== JSON.stringify(documentedLocales)) {
  fail(
    `GitHub locales differ from CFBundleLocalizations: ${documentedLocales.join(", ")} vs ${appLocales.join(", ")}`,
  );
}

for (const [name, notices] of [
  ["product", githubLicenseNotices],
  ["release", githubReleaseLicenseNotices],
  ["download", githubDownloadNotices],
]) {
  const noticeLocales = Object.keys(notices).sort();
  if (JSON.stringify(noticeLocales) !== JSON.stringify(documentedLocales)) {
    fail(`${name} license notices do not cover exactly the GitHub locales`);
  }
}

const rootReadmes = [
  join(projectRoot, "README.md"),
  join(projectRoot, "README.zh-CN.md"),
];
const expectedDMG =
  `https://github.com/ChineseMao/SlimLuma/releases/download/v${latestPublishedVersion}/` +
  `SlimLuma-${latestPublishedVersion}-macOS-universal.dmg`;
const expectedReleaseDMG =
  `https://github.com/ChineseMao/SlimLuma/releases/download/v${releaseNotesVersion}/` +
  `SlimLuma-${releaseNotesVersion}-macOS-universal.dmg`;
for (const rootReadme of rootReadmes) {
  const body = read(rootReadme);
  if (
    latestPublishedDownloadsAvailable
      ? !body.includes(expectedDMG)
      : body.includes(expectedDMG)
  ) {
    fail(
      `${relative(projectRoot, rootReadme)} has the wrong public-download state`,
    );
  }
  if (!body.includes("](LICENSE)")) {
    fail(`${relative(projectRoot, rootReadme)} lacks the current license notice`);
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
  `v${releaseNotesVersion}`,
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
    `docs/releases/v${releaseNotesVersion} does not contain exactly the configured locales`,
  );
}

for (const { locale } of githubLocales) {
  const generatedReadme = read(
    join(projectRoot, generatedReadmePath(locale)),
  );
  if (
    latestPublishedDownloadsAvailable
      ? !generatedReadme.includes(expectedDMG)
      : (
        generatedReadme.includes(expectedDMG)
        || !generatedReadme.includes(githubDownloadNotices[locale])
      )
  ) {
    fail(`Generated ${locale} README has the wrong public-download state`);
  }
  if (
    !generatedReadme.includes(githubLicenseNotices[locale])
  ) {
    fail(`Generated ${locale} README lacks its localized rights notice`);
  }
  if (generatedReadme.includes("License: MIT")) {
    fail(`Generated ${locale} README still presents the current project as MIT`);
  }
  const localizedRelease = read(
    join(releaseDirectory, `README.${locale}.md`),
  );
  if (!localizedRelease.includes(`<!-- locale:${locale} -->`)) {
    fail(`Release note ${locale} lacks its locale marker`);
  }
  if (!localizedRelease.includes(expectedReleaseDMG)) {
    fail(`Release note ${locale} lacks the current direct DMG link`);
  }
  if (
    !localizedRelease.includes(githubReleaseLicenseNotices[locale])
  ) {
    fail(`Release note ${locale} lacks its localized license-history notice`);
  }
  if (releaseNotesVersion !== "0.2.0") {
    if (localizedRelease.includes(`${repositoryURL}/blob/main/`)) {
      fail(`Release note ${locale} contains a mutable main-branch link`);
    }
    for (const pinnedPath of [
      `${repositoryURL}/blob/v${releaseNotesVersion}/LICENSE`,
      `${repositoryURL}/blob/v${releaseNotesVersion}/docs/releases/v${releaseNotesVersion}/README.${locale}.md`,
    ]) {
      if (!localizedRelease.includes(pinnedPath)) {
        fail(`Release note ${locale} lacks pinned link: ${pinnedPath}`);
      }
    }
  }
}

const communityFiles = [
  "CONTRIBUTING.md",
  "SECURITY.md",
  "CODE_OF_CONDUCT.md",
  "SUPPORT.md",
  "LICENSE",
  "PUBLISHER.md",
  "THIRD_PARTY_NOTICES.md",
];
for (const file of communityFiles) {
  if (!existsSync(join(projectRoot, file))) {
    fail(`Missing community file: ${file}`);
  }
}

const releaseIndex = read(
  join(projectRoot, "docs", "releases", `v${releaseNotesVersion}.md`),
);
const expectedReleaseLicenseRef =
  releaseNotesVersion === "0.2.0"
    ? "blob/main/LICENSE"
    : `blob/v${releaseNotesVersion}/LICENSE`;
for (const required of [
  "blob/v0.2.0/LICENSE",
  expectedReleaseLicenseRef,
  "historical grant is not revoked",
]) {
  if (!releaseIndex.includes(required)) {
    fail(`Release index lacks required publisher/license boundary: ${required}`);
  }
}
if (
  releaseNotesVersion !== "0.2.0"
  && releaseIndex.includes(`${repositoryURL}/blob/main/`)
) {
  fail("Release index contains a mutable main-branch link");
}

const license = read(join(projectRoot, "LICENSE"));
for (const required of [
  "SlimLuma Proprietary Source and Binary License",
  "Copyright © 2026 SlimLuma copyright holders.",
  "All rights reserved.",
  "SlimLuma 0.2.0",
  "released under the MIT License",
  "GitHub's terms",
  "Third-party materials",
]) {
  if (!license.includes(required)) {
    fail(`LICENSE lacks required boundary: ${required}`);
  }
}

const currentProjectSurfaces = [
  ...rootReadmes,
  join(projectRoot, "SUPPORT.md"),
  join(projectRoot, "docs", "COMPETITOR_COMPARISON_2026-07-28.md"),
  ...githubLocales.map(({ locale }) =>
    join(projectRoot, generatedReadmePath(locale)),
  ),
];
const retiredClaims = [
  "License: MIT",
  "free, open-source",
  "community-maintained open-source",
  "免费、开源",
  "社区维护的开源项目",
  "| 开源 | MIT |",
];
for (const source of currentProjectSurfaces) {
  const body = read(source);
  for (const claim of retiredClaims) {
    if (body.includes(claim)) {
      fail(`${relative(projectRoot, source)} contains retired project claim: ${claim}`);
    }
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
  join(projectRoot, "PUBLISHER.md"),
  join(projectRoot, "THIRD_PARTY_NOTICES.md"),
  join(projectRoot, "CHANGELOG.md"),
  join(projectRoot, "docs", "releases", `v${releaseNotesVersion}.md`),
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
const releaseWorkflow = read(
  join(projectRoot, ".github", "workflows", "release.yml"),
);
if (
  !releaseWorkflow.includes(
    "vars.SLIMLUMA_AUTOMATED_RELEASE == 'true'",
  )
) {
  fail("Release workflow lacks the explicit automated-release variable gate");
}

if (failures.length > 0) {
  throw new Error(
    `GitHub localization validation failed:\n- ${failures.join("\n- ")}`,
  );
}

console.log(
  `Verified GitHub internationalization: ${githubLocales.length} product READMEs for public v${latestPublishedVersion}, ${githubLocales.length} localized v${releaseNotesVersion} release notes, development v${version}, download-state gates, community files, and local links.`,
);
