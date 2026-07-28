#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import {
  existsSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  statSync,
  writeFileSync,
  mkdirSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join, relative, resolve } from "node:path";

const projectRoot = resolve(import.meta.dirname, "..");
const resourcesRoot = join(projectRoot, "Sources", "SlimLuma", "Resources");
const frozenKeysPath = join(resourcesRoot, "LocalizationKeys.json");
const xcstringstool =
  "/Applications/Xcode.app/Contents/Developer/usr/bin/xcstringstool";

const localeTargets = {
  en: "en",
  "zh-Hant": "zh-Hant",
  hi: "hi",
  "es-419": "es",
  "es-ES": "es",
  ar: "ar",
  fr: "fr",
  bn: "bn",
  "pt-BR": "pt",
  "pt-PT": "pt-pt",
  id: "id",
  ur: "ur",
  ru: "ru",
  de: "de",
  ja: "ja",
  sw: "sw",
  "pa-Arab": "pnb",
  te: "te",
  pcm: "pcm",
};

// Keep the highest-visibility navigation terms intentionally reviewed. These
// overrides are applied after machine translation so a later key refresh
// cannot reintroduce literal but misleading UI labels.
const manualOverrides = {
  ar: new Map([
    ["了解", "تعرّف"],
    ["系统", "النظام"],
    ["自动化", "الأتمتة"],
    ["预设", "الإعدادات المسبقة"],
  ]),
};

const refreshExisting = process.argv.includes("--refresh");
const pruneFrozenKeys = process.argv.includes("--prune");
const requestedLocales = process.argv
  .slice(2)
  .filter(
    (argument) =>
      argument !== "--refresh"
      && argument !== "--prune",
  );
if (requestedLocales.length === 0) {
  console.error(
    `Usage: node ${relative(projectRoot, import.meta.filename)} <locale> ...`,
  );
  process.exit(2);
}

const manuallyManagedKeys = [
  "支持的媒体文件",
  "将所选图片、视频或 PDF 添加到 SlimLuma 的媒体压缩队列。",
  "用 ${applicationName} 压缩文件",
  "添加文件到 ${applicationName}",
  "从 GitHub Releases 下载适用于 macOS 的 Universal 版本。",
  "将 SlimLuma.app 移到“应用程序”文件夹。",
  "打开“引擎与设置”并选择“一键补齐推荐引擎”。",
  "SlimLuma 使用 Homebrew 安装 ImageMagick、FFmpeg、qpdf 与 Ghostscript；媒体文件始终留在这台 Mac。",
  "有关架构、验证边界、许可证和发布说明，请查看主仓库文档。",
];

for (const locale of requestedLocales) {
  if (locale !== "zh-Hans" && !localeTargets[locale]) {
    throw new Error(`Unsupported automatic locale ${locale}.`);
  }
}

function walk(directory, predicate) {
  const result = [];
  for (const name of readdirSync(directory)) {
    const path = join(directory, name);
    const stats = statSync(path);
    if (stats.isDirectory()) {
      result.push(...walk(path, predicate));
    } else if (predicate(path)) {
      result.push(path);
    }
  }
  return result;
}

function extractedKeys() {
  const temporaryDirectory = mkdtempSync(join(tmpdir(), "slimluma-l10n-"));
  try {
    const sources = walk(
      join(projectRoot, "Sources"),
      (path) => path.endsWith(".swift"),
    );
    execFileSync(
      xcstringstool,
      [
        "extract",
        "--all-potential-swift-keys",
        "--SwiftUI",
        "--modern-localizable-strings",
        "--legacy-localizable-strings",
        "--output-directory",
        temporaryDirectory,
        ...sources,
      ],
      { stdio: "inherit" },
    );

    const keys = new Set();
    const addFromStringsData = (path) => {
      let contents;
      try {
        contents = JSON.parse(readFileSync(path, "utf8"));
      } catch {
        return;
      }
      for (const table of ["Localizable", "__PotentialKeys"]) {
        for (const entry of contents.tables?.[table] ?? []) {
          if (typeof entry.key === "string" && /[\u3400-\u9fff]/u.test(entry.key)) {
            keys.add(entry.key);
          }
        }
      }
    };

    for (const path of walk(temporaryDirectory, (item) =>
      item.endsWith(".stringsdata"),
    )) {
      addFromStringsData(path);
    }

    // Compiler extraction knows the concrete printf types for SwiftUI
    // interpolations. Merge it when a build is available.
    const buildRoot = join(projectRoot, ".build");
    try {
      for (const path of walk(buildRoot, (item) =>
        item.endsWith(".stringsdata"),
      )) {
        if (path.includes("Objects-normal/arm64/")) {
          addFromStringsData(path);
        }
      }
    } catch {
      // A clean checkout may not have a build directory yet.
    }

    for (const key of manuallyManagedKeys) {
      keys.add(key);
    }
    if (!pruneFrozenKeys && existsSync(frozenKeysPath)) {
      const frozenKeys = JSON.parse(readFileSync(frozenKeysPath, "utf8"));
      if (!Array.isArray(frozenKeys)) {
        throw new Error("LocalizationKeys.json must contain a JSON array");
      }
      for (const key of frozenKeys) {
        if (typeof key !== "string") {
          throw new Error("LocalizationKeys.json contains a non-string key");
        }
        keys.add(key);
      }
    }
    return [...keys].sort((left, right) => left.localeCompare(right, "zh-Hans"));
  } finally {
    rmSync(temporaryDirectory, { recursive: true, force: true });
  }
}

const protectedTerms = [
  "${applicationName}",
  "SlimLuma",
  "ImageMagick",
  "Ghostscript",
  "Homebrew",
  "AVFoundation",
  "VideoToolbox",
  "ImageIO",
  "Quick Look",
  "PDFKit",
  "FFmpeg",
  "ffprobe",
  "qpdf",
  "sips",
  "macOS",
  "Finder",
  "WebP",
  "AVIF",
  "HEIC",
  "HEVC",
  "H.264",
  "H.265",
  "AV1",
  "JPEG 2000",
  "JPEG",
  "PNG",
  "TIFF",
  "BMP",
  "GIF",
  "MKV",
  "WebM",
  "EXIF",
  "XMP",
  "IPTC",
  "ICC",
  "PDF",
];

function protect(text) {
  const replacements = [];
  let dynamicArgumentIndex = 0;
  let protectedText = text.replace(
    /\{\{\d+\}\}/gu,
    (match) => {
      const token = `[[SLFMT_${replacements.length}]]`;
      replacements.push([token, match, match]);
      return token;
    },
  );
  protectedText = protectedText.replace(
    /%(?:\d+\$)?(?:arg|@|lld|ld|d|f|\.0f|\.1f|s)/gu,
    (match) => {
      const token = `[[SLFMT_${replacements.length}]]`;
      replacements.push([
        token,
        match,
        match === "%arg" ? `{{${dynamicArgumentIndex++}}}` : match,
      ]);
      return token;
    },
  );
  for (const term of protectedTerms) {
    protectedText = protectedText.replaceAll(term, () => {
      const token = `[[SLTERM_${replacements.length}]]`;
      replacements.push([token, term, term]);
      return token;
    });
  }
  return { protectedText, replacements };
}

function restore(text, replacements) {
  let restored = text;
  for (const [token, , translatedValue] of replacements) {
    restored = restored.replaceAll(token, translatedValue);
  }
  return restored;
}

function delay(milliseconds) {
  return new Promise((resolvePromise) => {
    setTimeout(resolvePromise, milliseconds);
  });
}

const browserUserAgent =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
  "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0 Safari/537.36";
let bingSession;

async function createBingSession() {
  const response = await fetch("https://www.bing.com/translator", {
    headers: { "user-agent": browserUserAgent },
    signal: AbortSignal.timeout(30_000),
  });
  if (!response.ok) {
    throw new Error(`Bing session request failed: HTTP ${response.status}`);
  }
  const html = await response.text();
  const ig = html.match(/IG:"([A-F0-9]+)"/u)?.[1];
  const abuse = html.match(
    /params_AbusePreventionHelper\s*=\s*\[(\d+),"([^"]+)",(\d+)\]/u,
  );
  const iid =
    html.match(/id="rich_tta"\s+data-iid="([^"]+)"/u)?.[1] ??
    html.match(/data-iid="(translator\.\d+)"/u)?.[1];
  const setCookies =
    typeof response.headers.getSetCookie === "function"
      ? response.headers.getSetCookie()
      : [response.headers.get("set-cookie")].filter(Boolean);
  const cookie = setCookies
    .map((value) => value.split(";", 1)[0])
    .join("; ");

  if (!ig || !abuse || !iid) {
    throw new Error("Bing translator session metadata was not found");
  }
  return {
    ig,
    iid,
    key: abuse[1],
    token: abuse[2],
    cookie,
    counter: 0,
  };
}

async function requestTranslation(text, target) {
  for (let attempt = 0; attempt < 6; attempt += 1) {
    let retryAfter = 0;
    try {
      bingSession ??= await createBingSession();
      const body = new URLSearchParams({
        fromLang: "zh-Hans",
        to: target,
        text,
        token: bingSession.token,
        key: bingSession.key,
      });
      const endpoint = new URL("https://www.bing.com/ttranslatev3");
      endpoint.searchParams.set("isVertical", "1");
      endpoint.searchParams.set("IG", bingSession.ig);
      endpoint.searchParams.set("IID", bingSession.iid);
      endpoint.searchParams.set("SFX", String(bingSession.counter++));
      const response = await fetch(
        endpoint,
        {
          method: "POST",
          headers: {
            "content-type": "application/x-www-form-urlencoded",
            "user-agent": browserUserAgent,
            referer: "https://www.bing.com/translator",
            origin: "https://www.bing.com",
            "x-requested-with": "XMLHttpRequest",
            cookie: bingSession.cookie,
          },
          body,
          signal: AbortSignal.timeout(30_000),
        },
      );
      if (response.ok) {
        const payload = await response.json();
        if (Array.isArray(payload)) {
          const translatedText = payload
            .map((item) => item.translations?.[0]?.text ?? "")
            .join("\n");
          if (translatedText.trim().length > 0) {
            return translatedText;
          }
        }
        // Bing occasionally returns an error object with HTTP 200 while a
        // translator session is being throttled. Treat that as a retryable
        // response instead of crashing with an unrelated TypeError.
        retryAfter =
          Number(response.headers.get("retry-after") ?? 0) * 1_000;
        throw new Error("Translation service returned no translations");
      }
      retryAfter =
        Number(response.headers.get("retry-after") ?? 0) * 1_000;
      if (
        ![401, 403, 408, 429, 500, 502, 503, 504].includes(response.status)
      ) {
        throw new Error(`Translation request failed: HTTP ${response.status}`);
      }
    } catch (error) {
      if (
        attempt === 5
        || (
          error instanceof Error
          && error.message.startsWith("Translation request failed: HTTP")
        )
      ) {
        throw error;
      }
    }

    const backoff = Math.min(45_000, 2_000 * 2 ** attempt);
    const jitter = Math.floor(Math.random() * 1_500);
    const wait = Math.max(retryAfter, backoff) + jitter;
    process.stdout.write(
      `\n${target}: request unavailable, retrying in ${Math.ceil(wait / 1_000)}s`,
    );
    bingSession = undefined;
    await delay(wait);
  }
  throw new Error("Translation request exhausted retries");
}

async function translateKeys(keys, target) {
  const translations = new Map();
  const batches = [];
  let current = [];
  let currentLength = 0;

  for (const [index, key] of keys.entries()) {
    const item = { index, key, ...protect(key) };
    const estimatedLength = item.protectedText.length + 40;
    if (current.length >= 8 || currentLength + estimatedLength > 850) {
      batches.push(current);
      current = [];
      currentLength = 0;
    }
    current.push(item);
    currentLength += estimatedLength;
  }
  if (current.length > 0) batches.push(current);

  for (const [batchIndex, batch] of batches.entries()) {
    const input = batch
      .map(
        (item) =>
          `[[SLKEY_${String(item.index).padStart(5, "0")}]]\n${item.protectedText}`,
      )
      .join("\n");
    const output = await requestTranslation(input, target);
    const markerPattern = /\[\[SLKEY_(\d{5})\]\]\s*/gu;
    const matches = [...output.matchAll(markerPattern)];

    for (const [matchIndex, match] of matches.entries()) {
      const start = match.index + match[0].length;
      const end =
        matchIndex + 1 < matches.length
          ? matches[matchIndex + 1].index
          : output.length;
      const item = batch.find(
        (candidate) => candidate.index === Number(match[1]),
      );
      if (!item) continue;
      translations.set(
        item.key,
        restore(output.slice(start, end).trim(), item.replacements),
      );
    }

    for (const item of batch) {
      if (!translations.has(item.key)) {
        const translated = await requestTranslation(item.protectedText, target);
        translations.set(
          item.key,
          restore(translated.trim(), item.replacements),
        );
      }
    }

    process.stdout.write(
      `\r${target}: ${batchIndex + 1}/${batches.length} batches`,
    );
    await delay(300 + Math.floor(Math.random() * 250));
  }
  process.stdout.write("\n");
  return translations;
}

async function requestPCMTranslation(text) {
  for (let attempt = 0; attempt < 2; attempt += 1) {
    try {
      const endpoint = new URL(
        "https://translate-api.naija.guru/translations/v1/search",
      );
      endpoint.searchParams.set("source_lang", "en");
      endpoint.searchParams.set("target_lang", "pcm");
      endpoint.searchParams.set("text", text);
      endpoint.searchParams.set("app_lang", "en");
      const response = await fetch(endpoint, {
        headers: { "user-agent": browserUserAgent },
        signal: AbortSignal.timeout(15_000),
      });
      if (!response.ok) {
        const error = new Error(
          `Naija translation failed: HTTP ${response.status}`,
        );
        if (
          response.status >= 400
          && response.status < 500
          && ![408, 429].includes(response.status)
        ) {
          error.nonRetryable = true;
        }
        throw error;
      }
      const payload = await response.json();
      const translated = payload?.data?.translations?.[0]?.text;
      if (typeof translated === "string" && translated.trim().length > 0) {
        return translated.trim();
      }
      throw new Error("Naija translation returned no translations");
    } catch (error) {
      if (error?.nonRetryable === true || attempt === 1) throw error;
      await delay(1_000 * 2 ** attempt);
    }
  }
  throw new Error("Naija translation exhausted retries");
}

async function translatePCMKeys(keys) {
  const english = existingTranslations("en");
  const translations = new Map();
  const items = keys.map((key) => {
    const englishText = english.get(key);
    if (typeof englishText !== "string" || englishText.length === 0) {
      throw new Error(`English localization is missing for PCM key: ${key}`);
    }
    return { key, englishText };
  });

  const concurrency = 3;
  let fallbackCount = 0;
  for (let offset = 0; offset < items.length; offset += concurrency) {
    const group = items.slice(offset, offset + concurrency);
    const values = await Promise.all(
      group.map(async (item) => {
        let candidate;
        try {
          candidate = await requestPCMTranslation(item.englishText);
        } catch {
          candidate = item.englishText;
          fallbackCount += 1;
        }
        const requiredFragments = [
          ...item.englishText.matchAll(
            /\{\{\d+\}\}|%(?:\d+\$)?(?:@|lld|ld|d|f|\.0f|\.1f|s)|\(\.\+\?\)/gu,
          ),
        ].map((match) => match[0]);
        for (const term of protectedTerms) {
          if (item.englishText.includes(term)) {
            requiredFragments.push(term);
          }
        }
        if (item.englishText.startsWith("^")) requiredFragments.push("^");
        if (item.englishText.endsWith("$")) requiredFragments.push("$");
        const preservesRequiredFragments = requiredFragments.every(
          (fragment) =>
            candidate.split(fragment).length
              >= item.englishText.split(fragment).length,
        );
        return {
          key: item.key,
          // A readable English fallback is safer than corrupting a runtime
          // placeholder, regular expression, or technical identifier.
          value: preservesRequiredFragments ? candidate : item.englishText,
        };
      }),
    );
    for (const { key, value } of values) {
      translations.set(key, value);
    }
    process.stdout.write(
      `\rpcm: ${Math.min(offset + group.length, items.length)}/${items.length} strings`
        + ` (${fallbackCount} English fallbacks)`,
    );
    await delay(250);
  }
  process.stdout.write("\n");
  return translations;
}

function escaped(text) {
  return text
    .replaceAll("\\", "\\\\")
    .replaceAll('"', '\\"')
    .replaceAll("\n", "\\n")
    .replaceAll("\r", "\\r");
}

function writeStrings(locale, keys, translations) {
  const directory = join(resourcesRoot, `${locale}.lproj`);
  mkdirSync(directory, { recursive: true });
  const header =
    "/* Generated localization. Technical names and printf placeholders are intentionally preserved. */\n\n";
  const body = keys
    .map((key) => `"${escaped(key)}" = "${escaped(translations.get(key) ?? key)}";`)
    .join("\n");
  writeFileSync(join(directory, "Localizable.strings"), `${header}${body}\n`);
}

function existingTranslations(locale) {
  const path = join(
    resourcesRoot,
    `${locale}.lproj`,
    "Localizable.strings",
  );
  if (!existsSync(path)) return new Map();
  try {
    const output = execFileSync(
      "/usr/bin/plutil",
      ["-convert", "json", "-o", "-", path],
      { encoding: "utf8" },
    );
    return new Map(Object.entries(JSON.parse(output)));
  } catch {
    throw new Error(`Unable to parse existing localization for ${locale}`);
  }
}

function validateTranslationStructure(key, value) {
  const issues = [];
  const dynamicCount = key.split("%arg").length - 1;
  for (let index = 0; index < dynamicCount; index += 1) {
    if (!value.includes(`{{${index}}}`)) {
      issues.push(`missing dynamic argument ${index}`);
    }
  }
  const typedPlaceholders = [
    ...key.matchAll(
      /%(?:\d+\$)?(?:@|lld|ld|d|f|\.0f|\.1f|s)/gu,
    ),
  ].map((match) => match[0]);
  for (const placeholder of typedPlaceholders) {
    if (
      value.split(placeholder).length
      < key.split(placeholder).length
    ) {
      issues.push(`missing ${placeholder}`);
    }
  }
  for (const term of protectedTerms) {
    if (key.includes(term) && !value.includes(term)) {
      issues.push(`missing ${term}`);
    }
  }
  if (/SL(?:FMT|TERM|KEY)_/u.test(value)) {
    issues.push("contains a generator token");
  }
  return issues;
}

const keys = extractedKeys();
console.log(`Extracted ${keys.length} Chinese localization keys.`);

for (const locale of requestedLocales) {
  if (locale === "zh-Hans") {
    writeStrings(locale, keys, new Map(keys.map((key) => [key, key])));
    continue;
  }
  const existing = refreshExisting
    ? new Map()
    : existingTranslations(locale);
  const missingKeys = keys.filter(
    (key) =>
      !existing.has(key)
      || typeof existing.get(key) !== "string"
      || existing.get(key).length === 0,
  );
  const translated = missingKeys.length === 0
    ? new Map()
    : locale === "pcm"
      ? await translatePCMKeys(missingKeys)
      : await translateKeys(missingKeys, localeTargets[locale]);
  const merged = new Map(
    keys.map((key) => [key, translated.get(key) ?? existing.get(key) ?? key]),
  );
  for (const [key, value] of manualOverrides[locale] ?? []) {
    if (merged.has(key)) {
      merged.set(key, value);
    }
  }
  for (const [key, value] of merged) {
    const issues = validateTranslationStructure(key, value);
    if (issues.length > 0) {
      throw new Error(
        `${locale} has an unsafe translation for ${key}: `
          + issues.join(", "),
      );
    }
  }
  console.log(
    `${locale}: preserved ${keys.length - missingKeys.length}, `
      + `translated ${missingKeys.length}.`,
  );
  writeStrings(locale, keys, merged);
}
