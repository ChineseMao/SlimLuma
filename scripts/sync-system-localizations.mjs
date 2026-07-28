#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import {
  existsSync,
  lstatSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  realpathSync,
  renameSync,
  rmSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { join, resolve } from "node:path";

const projectRoot = resolve(import.meta.dirname, "..");
const resourcesRoot = join(projectRoot, "Sources", "SlimLuma", "Resources");
const checkOnly = process.argv.includes("--check");
const unsupportedArguments = process.argv
  .slice(2)
  .filter((argument) => argument !== "--check");
if (unsupportedArguments.length > 0) {
  throw new Error(
    `Unsupported arguments: ${unsupportedArguments.join(", ")}. Use --check or no arguments.`,
  );
}
const serviceMenuKey = "添加到 SlimLuma 压缩队列";
const serviceDescriptionKey =
  "将所选图片、视频或 PDF 添加到 SlimLuma 的媒体压缩队列。";
const documentTypeKey = "支持的媒体文件";
const shortcutPhraseKeys = [
  "用 ${applicationName} 压缩文件",
  "添加文件到 ${applicationName}",
];

function dictionary(path) {
  const output = execFileSync(
    "/usr/bin/plutil",
    ["-convert", "json", "-o", "-", path],
    { encoding: "utf8" },
  );
  return JSON.parse(output);
}

function escaped(text) {
  return text
    .replaceAll("\\", "\\\\")
    .replaceAll('"', '\\"')
    .replaceAll("\n", "\\n")
    .replaceAll("\r", "\\r");
}

const sourceDirectory = join(resourcesRoot, "zh-Hans.lproj");
const source = dictionary(join(sourceDirectory, "Localizable.strings"));
const frozenKeysPath = join(resourcesRoot, "LocalizationKeys.json");
const infoPlist = dictionary(join(projectRoot, "Support", "Info.plist"));
const expectedLocales = [...infoPlist.CFBundleLocalizations].sort();
const canonicalResourcesRoot = realpathSync(resourcesRoot);
for (const name of readdirSync(resourcesRoot).filter((item) =>
  item.startsWith(".system-l10n-stage-"),
)) {
  const path = join(resourcesRoot, name);
  const stats = lstatSync(path);
  if (stats.isSymbolicLink() || !stats.isDirectory()) {
    throw new Error(`Unsafe localization staging path: ${path}`);
  }
  const ownerPath = join(path, "owner-pid");
  const ownerPID = existsSync(ownerPath)
    ? Number(readFileSync(ownerPath, "utf8").trim())
    : Number.NaN;
  if (Number.isSafeInteger(ownerPID) && ownerPID > 0) {
    try {
      process.kill(ownerPID, 0);
      continue;
    } catch (error) {
      if (error?.code !== "ESRCH") {
        continue;
      }
    }
  } else if (Date.now() - stats.mtimeMs < 5 * 60 * 1_000) {
    continue;
  }
  rmSync(path, { recursive: true, force: true });
}
const localizationDirectoryNames = readdirSync(resourcesRoot).filter((item) =>
  item.endsWith(".lproj"),
);
for (const name of localizationDirectoryNames) {
  const path = join(resourcesRoot, name);
  const stats = lstatSync(path);
  if (stats.isSymbolicLink() || !stats.isDirectory()) {
    throw new Error(`Localization path must be a real directory: ${path}`);
  }
  const canonicalDirectory = realpathSync(path);
  if (resolve(canonicalDirectory, "..") !== canonicalResourcesRoot) {
    throw new Error(`Localization directory escapes Resources: ${path}`);
  }
}
const actualLocales = localizationDirectoryNames
  .map((item) => item.slice(0, -".lproj".length))
  .sort();
if (JSON.stringify(actualLocales) !== JSON.stringify(expectedLocales)) {
  throw new Error(
    "Localization directories do not match CFBundleLocalizations.\n" +
      `Expected: ${expectedLocales.join(", ")}\n` +
      `Actual: ${actualLocales.join(", ")}`,
  );
}

const sourceKeys = Object.keys(source).sort();
const frozenKeys = JSON.parse(readFileSync(frozenKeysPath, "utf8"));
if (!Array.isArray(frozenKeys) || frozenKeys.some((key) => typeof key !== "string")) {
  throw new Error("LocalizationKeys.json must contain only string keys.");
}
const expectedSourceKeys = [...frozenKeys].sort();
if (JSON.stringify(sourceKeys) !== JSON.stringify(expectedSourceKeys)) {
  throw new Error(
    "The zh-Hans localization table does not match LocalizationKeys.json.",
  );
}
const sourceKeyCount = sourceKeys.length;

const appShortcutLocalizations = new Map();
const outputs = new Map();
const forbiddenSourceShortcutPath = join(
  sourceDirectory,
  "AppShortcuts.strings",
);
outputs.set(forbiddenSourceShortcutPath, null);

for (const locale of expectedLocales) {
  const directory = join(resourcesRoot, `${locale}.lproj`);
  const translations = dictionary(join(directory, "Localizable.strings"));
  const translationKeys = Object.keys(translations).sort();
  if (JSON.stringify(translationKeys) !== JSON.stringify(sourceKeys)) {
    const sourceKeySet = new Set(sourceKeys);
    const translationKeySet = new Set(translationKeys);
    const missing = sourceKeys.filter((key) => !translationKeySet.has(key));
    const unexpected = translationKeys.filter((key) => !sourceKeySet.has(key));
    throw new Error(
      `${locale} does not match the ${sourceKeyCount}-key source table. ` +
        `Missing: ${missing.slice(0, 3).join(" | ") || "none"}. ` +
        `Unexpected: ${unexpected.slice(0, 3).join(" | ") || "none"}.`,
    );
  }
  const localized = (key) => {
    const value = translations[key];
    if (typeof value !== "string" || value.length === 0) {
      throw new Error(`${locale} is missing a translation for: ${key}`);
    }
    return value;
  };

  const localizedInfoPlist = [
    '/* Localized values used by Finder and Launch Services. */',
    '"CFBundleDisplayName" = "SlimLuma";',
    '"CFBundleName" = "SlimLuma";',
    `"CFBundleTypeName" = "${escaped(localized(documentTypeKey))}";`,
    "",
  ].join("\n");
  outputs.set(join(directory, "InfoPlist.strings"), localizedInfoPlist);

  const servicesMenu = [
    "/* Finder Services menu and description. */",
    `"${escaped(serviceMenuKey)}" = "${escaped(localized(serviceMenuKey))}";`,
    `"SLIMLUMA_SERVICE_DESCRIPTION" = "${escaped(localized(serviceDescriptionKey))}";`,
    "",
  ].join("\n");
  outputs.set(join(directory, "ServicesMenu.strings"), servicesMenu);

  appShortcutLocalizations.set(
    locale,
    Object.fromEntries(
      shortcutPhraseKeys.map((key) => [
        key,
        normalizeApplicationName(localized(key)),
      ]),
    ),
  );
}

const shortcutStrings = Object.fromEntries(
  shortcutPhraseKeys.map((key) => [
    key,
    {
      comment:
        "App Shortcut invocation phrase. Keep ${applicationName} unchanged.",
      localizations: Object.fromEntries(
        [...appShortcutLocalizations.entries()].map(
          ([locale, translations]) => [
            locale,
            {
              stringUnit: {
                state: locale === "zh-Hans" ? "new" : "translated",
                value: translations[key],
              },
            },
          ],
        ),
      ),
    },
  ]),
);

outputs.set(
  join(resourcesRoot, "AppShortcuts.xcstrings"),
  `${JSON.stringify(
    {
      sourceLanguage: "zh-Hans",
      strings: shortcutStrings,
      version: "1.0",
    },
    null,
    2,
  )}\n`,
);

if (checkOnly) {
  const stalePaths = [...outputs].flatMap(([path, expectedContents]) => {
    if (expectedContents === null) {
      return existsSync(path) ? [path] : [];
    }
    if (!existsSync(path)) {
      return [path];
    }
    return readFileSync(path, "utf8") === expectedContents ? [] : [path];
  });
  if (stalePaths.length > 0) {
    throw new Error(
      "System localization artifacts are missing or stale:\n" +
        stalePaths.map((path) => `- ${path}`).join("\n"),
    );
  }
  console.log(
    `Verified system localization artifacts for ${expectedLocales.length} locales.`,
  );
} else {
  const previousOutputs = new Map(
    [...outputs.keys()].map((path) => [
      path,
      existsSync(path)
        ? { existed: true, contents: readFileSync(path) }
        : { existed: false, contents: null },
    ]),
  );
  const stagingDirectory = mkdtempSync(
    join(resourcesRoot, ".system-l10n-stage-"),
  );
  writeFileSync(
    join(stagingDirectory, "owner-pid"),
    `${process.pid}\n`,
    { flag: "wx" },
  );
  const stagedOutputs = new Map();
  const cleanupStagedOutputs = () => {
    try {
      rmSync(stagingDirectory, { recursive: true, force: true });
    } catch (error) {
      console.error(
        `Unable to remove localization staging directory: ${stagingDirectory}`,
      );
      console.error(error);
    }
  };
  let committed = false;
  let commitStarted = false;
  const rollback = () => {
    if (committed || !commitStarted) return [];
    const errors = [];
    for (const [path, previous] of previousOutputs) {
      try {
        if (previous.existed) {
          atomicWrite(path, previous.contents);
        } else if (existsSync(path)) {
          unlinkSync(path);
        }
      } catch (error) {
        errors.push(
          new Error(`Unable to restore ${path}`, { cause: error }),
        );
      }
    }
    return errors;
  };
  const handleInterrupt = (signal) => {
    const rollbackErrors = rollback();
    cleanupStagedOutputs();
    if (rollbackErrors.length > 0) {
      console.error(
        new AggregateError(
          rollbackErrors,
          "System localization rollback was incomplete.",
        ),
      );
    }
    process.exit(signal === "SIGINT" ? 130 : 143);
  };

  process.once("SIGINT", handleInterrupt);
  process.once("SIGTERM", handleInterrupt);
  try {
    for (const [index, [path, contents]] of [...outputs].entries()) {
      if (contents === null) continue;
      const stagedPath = join(stagingDirectory, String(index));
      writeFileSync(stagedPath, contents, { flag: "wx" });
      stagedOutputs.set(path, stagedPath);
      await new Promise((resolvePromise) => {
        setImmediate(resolvePromise);
      });
    }

    commitStarted = true;
    for (const [path, contents] of outputs) {
      if (contents === null) {
        if (existsSync(path)) {
          unlinkSync(path);
        }
      } else {
        renameSync(stagedOutputs.get(path), path);
      }
      await new Promise((resolvePromise) => {
        setImmediate(resolvePromise);
      });
    }
    committed = true;
  } catch (error) {
    const rollbackErrors = rollback();
    if (rollbackErrors.length > 0) {
      throw new AggregateError(
        [error, ...rollbackErrors],
        "System localization sync failed and rollback was incomplete.",
      );
    }
    throw error;
  } finally {
    process.off("SIGINT", handleInterrupt);
    process.off("SIGTERM", handleInterrupt);
    cleanupStagedOutputs();
  }
  console.log(
    `Synchronized system localization artifacts for ${expectedLocales.length} locales.`,
  );
}

function normalizeApplicationName(value) {
  if (!value.includes("${applicationName}")) {
    throw new Error(
      `App Shortcut translation lost the applicationName token: ${value}`,
    );
  }
  return value;
}

function atomicWrite(path, contents) {
  const temporaryPath = `${path}.tmp-${process.pid}`;
  try {
    writeFileSync(temporaryPath, contents, { flag: "wx" });
    renameSync(temporaryPath, path);
  } finally {
    if (existsSync(temporaryPath)) {
      unlinkSync(temporaryPath);
    }
  }
}
