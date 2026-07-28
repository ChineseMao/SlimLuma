#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import {
  existsSync,
  mkdirSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import { join, resolve } from "node:path";
import {
  generatedReadmePath,
  githubLocales,
} from "./github-locales.mjs";

const projectRoot = resolve(import.meta.dirname, "..");
const resourcesRoot = join(projectRoot, "Sources", "SlimLuma", "Resources");
const readmeOutputRoot = join(projectRoot, "docs", "readme");
const releasesRoot = join(projectRoot, "docs", "releases");
const checksOnly = process.argv.includes("--check");
const repositoryURL = "https://github.com/ChineseMao/SlimLuma";

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
if (typeof version !== "string" || !/^\d+\.\d+\.\d+$/.test(version)) {
  throw new Error("Support/Info.plist does not contain a semantic app version.");
}

const tag = `v${version}`;
const releaseURL = `${repositoryURL}/releases/tag/${tag}`;
const releaseAssetURL = `${repositoryURL}/releases/download/${tag}`;
const assetNames = {
  dmg: `SlimLuma-${version}-macOS-universal.dmg`,
  zip: `SlimLuma-${version}-macOS-universal.zip`,
  cli: `slimluma-${version}-macOS-universal.tar.gz`,
  checksums: "SHA256SUMS",
};
const releaseConfigPath = join(releasesRoot, `${tag}.i18n.json`);
if (!existsSync(releaseConfigPath)) {
  throw new Error(
    `Missing localized release configuration: ${releaseConfigPath}`,
  );
}
const releaseConfig = JSON.parse(readFileSync(releaseConfigPath, "utf8"));
if (
  typeof releaseConfig.taglineKey !== "string" ||
  !Array.isArray(releaseConfig.highlightKeys) ||
  releaseConfig.highlightKeys.length === 0 ||
  releaseConfig.highlightKeys.some((key) => typeof key !== "string")
) {
  throw new Error(`${releaseConfigPath} has an invalid localization schema.`);
}

const englishOverrides = {
  "本地媒体瘦身工具": "Local-first media compressor",
  "支持常见图片、视频和 PDF，也可以拖入整个文件夹":
    "Compress common image, video, and PDF formats, or drop in entire folders.",
  "先纠正方向，再按比例缩小、重编码和处理 profile；PNG、WebP 与 AVIF 的设置会映射为对应引擎参数。":
    "Correct orientation first, then resize, re-encode, and handle color profiles. PNG, WebP, and AVIF settings map to their engine-specific controls.",
  "画面缩放保持比例、不放大并对齐偶数尺寸；音频转 AAC，MP4 字幕转 mov_text，MKV 字幕尽量复制，MP4 开启 faststart。":
    "Preserve aspect ratio, avoid upscaling, and use codec-safe dimensions. Convert audio to AAC, map MP4 subtitles to mov_text, preserve compatible MKV subtitles, and enable MP4 fast start.",
  "qpdf 会重组对象流并重新压缩可压缩数据；Ghostscript 还能降低内嵌图片的像素密度、质量或色彩复杂度。文字型 PDF 通常收益较小，扫描件通常更明显。":
    "qpdf reorganizes object streams and recompresses eligible data. Optional Ghostscript processing can reduce embedded-image resolution, quality, or color complexity. Scanned documents usually shrink more than text-first PDFs.",
  "SlimLuma 会逐级调整质量；必要时缩小尺寸，以得到不超过目标的最清晰安全结果。目标大小需要 ImageMagick。":
    "SlimLuma searches quality levels and, when necessary, dimensions to find the clearest safe image that stays within the target size. Image target size requires ImageMagick.",
  "H.264 与 HEVC 可按目标大小执行两遍软件编码，并为音频、字幕和容器预留空间；AV1 与单独音频压缩暂不支持目标体积。":
    "H.264 and HEVC support two-pass target-size encoding with space reserved for audio, subtitles, and the container. AV1 and audio-only target sizing are not currently supported.",
  "图片、视频和 PDF 可以混合加入；队列允许 1–6 个并发任务，开始时冻结整批设置。":
    "Mix images, videos, and PDFs in one queue, run 1–6 jobs concurrently, and freeze the batch settings when processing starts.",
  "专业引擎只写入目标目录中的 .slimluma 隐藏临时文件，不直接碰原件。":
    "External engines write to a hidden .slimluma temporary file on the destination volume and never modify the original directly.",
  "按图片、视频或 PDF 的完整性规则重新读取，发现关键退化就拒绝输出。":
    "SlimLuma reopens every result with image-, video-, or PDF-specific integrity checks and rejects output when a critical regression is detected.",
  "从剪贴板、监控文件夹和 Finder 直接进入压缩队列":
    "Add work directly from the Clipboard, watched folders, Finder, and Shortcuts.",
  "从 GitHub Releases 下载适用于 macOS 的 Universal 版本。":
    "Download SlimLuma for macOS — Universal DMG",
  "将 SlimLuma.app 移到“应用程序”文件夹。":
    "Move SlimLuma.app to the Applications folder.",
  "打开“引擎与设置”并选择“一键补齐推荐引擎”。":
    "Open Engines & Settings and choose Install Recommended Engines.",
  "SlimLuma 使用 Homebrew 安装 ImageMagick、FFmpeg、qpdf 与 Ghostscript；媒体文件始终留在这台 Mac。":
    "SlimLuma can install ImageMagick, FFmpeg, qpdf, and Ghostscript through Homebrew. Your media stays on this Mac.",
  "压缩过程不上传媒体文件。只有用户主动打开许可网站、brew.sh 或执行 Homebrew 安装时，浏览器或 Homebrew 才会访问网络。":
    "Compression never uploads media. Network access occurs only when you explicitly open a licensing or Homebrew website or ask Homebrew to install an engine.",
  "有关架构、验证边界、许可证和发布说明，请查看主仓库文档。":
    "Read the canonical English documentation for architecture, validation boundaries, licensing, and release details.",
  "加密 PDF 需要 qpdf 才能安全解锁并在输出中恢复原加密策略。":
    "Encrypted PDFs use qpdf to unlock the input safely and restore its encryption policy on the accepted output.",
};

function escapeHTML(value) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function translations(locale) {
  const path = join(
    resourcesRoot,
    `${locale}.lproj`,
    "Localizable.strings",
  );
  const output = execFileSync(
    "/usr/bin/plutil",
    ["-convert", "json", "-o", "-", path],
    { encoding: "utf8" },
  );
  const table = JSON.parse(output);
  if (locale === "en") {
    Object.assign(table, englishOverrides);
  }
  return table;
}

function translated(table, locale, key) {
  const value = table[key];
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`${locale} is missing GitHub localization key: ${key}`);
  }
  return value;
}

function generatedReadmeHref(locale) {
  if (locale === "en") {
    return "../../README.md";
  }
  if (locale === "zh-Hans") {
    return "../../README.zh-CN.md";
  }
  return `README.${locale}.md`;
}

function languageSelector(currentLocale, hrefForLocale) {
  const links = githubLocales.map(({ locale, name }) => {
    const link = `<a href="${escapeHTML(hrefForLocale(locale))}">${escapeHTML(name)}</a>`;
    return locale === currentLocale ? `<strong>${link}</strong>` : link;
  });
  return `<p dir="auto">${links.join(" · ")}</p>`;
}

function badges() {
  return `[![CI](${repositoryURL}/actions/workflows/ci.yml/badge.svg)](${repositoryURL}/actions/workflows/ci.yml)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111111)](${repositoryURL}/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-5b55ea.svg)](${repositoryURL}/blob/main/LICENSE)`;
}

function directDownloads(primaryLabel) {
  return `> [!IMPORTANT]
> **[⬇ ${primaryLabel}](${releaseAssetURL}/${assetNames.dmg})**
>
> Apple Silicon + Intel · [App ZIP](${releaseAssetURL}/${assetNames.zip}) · [CLI](${releaseAssetURL}/${assetNames.cli}) · [SHA-256](${releaseAssetURL}/${assetNames.checksums})`;
}

function rtlReadmeBody(t) {
  const featureRows = [
    [t("图片"), t("先纠正方向，再按比例缩小、重编码和处理 profile；PNG、WebP 与 AVIF 的设置会映射为对应引擎参数。")],
    [t("视频"), t("画面缩放保持比例、不放大并对齐偶数尺寸；音频转 AAC，MP4 字幕转 mov_text，MKV 字幕尽量复制，MP4 开启 faststart。")],
    ["PDF", t("qpdf 会重组对象流并重新压缩可压缩数据；Ghostscript 还能降低内嵌图片的像素密度、质量或色彩复杂度。文字型 PDF 通常收益较小，扫描件通常更明显。")],
    [t("目标文件大小"), `${t("SlimLuma 会逐级调整质量；必要时缩小尺寸，以得到不超过目标的最清晰安全结果。目标大小需要 ImageMagick。")} ${t("H.264 与 HEVC 可按目标大小执行两遍软件编码，并为音频、字幕和容器预留空间；AV1 与单独音频压缩暂不支持目标体积。")}`],
    [t("文件队列"), t("图片、视频和 PDF 可以混合加入；队列允许 1–6 个并发任务，开始时冻结整批设置。")],
    [t("安全"), t("专业引擎只写入目标目录中的 .slimluma 隐藏临时文件，不直接碰原件。")],
    [t("结果守门"), t("按图片、视频或 PDF 的完整性规则重新读取，发现关键退化就拒绝输出。")],
    [t("自动化"), t("从剪贴板、监控文件夹和 Finder 直接进入压缩队列")],
  ];
  const features = featureRows
    .map(
      ([label, body]) =>
        `<li><strong>${escapeHTML(label)}</strong> — ${escapeHTML(body)}</li>`,
    )
    .join("\n");
  return `<div dir="rtl" align="right">
<p><strong>${escapeHTML(t("本地媒体瘦身工具"))}</strong></p>
<p>${escapeHTML(t("支持常见图片、视频和 PDF，也可以拖入整个文件夹"))}</p>
<h2>${escapeHTML(t("功能与原理"))}</h2>
<ul>
${features}
</ul>
<h2>${escapeHTML(t("安装"))}</h2>
<ol>
<li><a href="${releaseAssetURL}/${assetNames.dmg}">${escapeHTML(t("从 GitHub Releases 下载适用于 macOS 的 Universal 版本。"))}</a></li>
<li>${escapeHTML(t("将 SlimLuma.app 移到“应用程序”文件夹。"))}</li>
<li>${escapeHTML(t("打开“引擎与设置”并选择“一键补齐推荐引擎”。"))}</li>
</ol>
<p>${escapeHTML(t("SlimLuma 使用 Homebrew 安装 ImageMagick、FFmpeg、qpdf 与 Ghostscript；媒体文件始终留在这台 Mac。"))}</p>
</div>`;
}

function ltrReadmeBody(t) {
  return `> ${t("本地媒体瘦身工具")}

${t("支持常见图片、视频和 PDF，也可以拖入整个文件夹")}

## ${t("功能与原理")}

- **${t("图片")}** — ${t("先纠正方向，再按比例缩小、重编码和处理 profile；PNG、WebP 与 AVIF 的设置会映射为对应引擎参数。")}
- **${t("视频")}** — ${t("画面缩放保持比例、不放大并对齐偶数尺寸；音频转 AAC，MP4 字幕转 mov_text，MKV 字幕尽量复制，MP4 开启 faststart。")}
- **PDF** — ${t("qpdf 会重组对象流并重新压缩可压缩数据；Ghostscript 还能降低内嵌图片的像素密度、质量或色彩复杂度。文字型 PDF 通常收益较小，扫描件通常更明显。")}
- **${t("目标文件大小")}** — ${t("SlimLuma 会逐级调整质量；必要时缩小尺寸，以得到不超过目标的最清晰安全结果。目标大小需要 ImageMagick。")} ${t("H.264 与 HEVC 可按目标大小执行两遍软件编码，并为音频、字幕和容器预留空间；AV1 与单独音频压缩暂不支持目标体积。")}
- **${t("文件队列")}** — ${t("图片、视频和 PDF 可以混合加入；队列允许 1–6 个并发任务，开始时冻结整批设置。")}
- **${t("安全")}** — ${t("专业引擎只写入目标目录中的 .slimluma 隐藏临时文件，不直接碰原件。")}
- **${t("结果守门")}** — ${t("按图片、视频或 PDF 的完整性规则重新读取，发现关键退化就拒绝输出。")}
- **${t("自动化")}** — ${t("从剪贴板、监控文件夹和 Finder 直接进入压缩队列")}

## ${t("安装")}

1. [${t("从 GitHub Releases 下载适用于 macOS 的 Universal 版本。")}](${releaseAssetURL}/${assetNames.dmg})
2. ${t("将 SlimLuma.app 移到“应用程序”文件夹。")}
3. ${t("打开“引擎与设置”并选择“一键补齐推荐引擎”。")}

${t("SlimLuma 使用 Homebrew 安装 ImageMagick、FFmpeg、qpdf 与 Ghostscript；媒体文件始终留在这台 Mac。")}`;
}

function readmeDocument(locale, direction) {
  const table = translations(locale);
  const t = (key) => translated(table, locale, key);
  const localizedBody =
    direction === "rtl" ? rtlReadmeBody(t) : ltrReadmeBody(t);
  const privacy =
    direction === "rtl"
      ? `<div dir="rtl" align="right"><h2>${escapeHTML(t("本地数据与隐私"))}</h2><p>${escapeHTML(t("压缩过程不上传媒体文件。只有用户主动打开许可网站、brew.sh 或执行 Homebrew 安装时，浏览器或 Homebrew 才会访问网络。"))}</p></div>`
      : `## ${t("本地数据与隐私")}

${t("压缩过程不上传媒体文件。只有用户主动打开许可网站、brew.sh 或执行 Homebrew 安装时，浏览器或 Homebrew 才会访问网络。")}`;

  return `<!-- Generated by scripts/generate-github-readmes.mjs. -->

# SlimLuma

${badges()}

${languageSelector(locale, generatedReadmeHref)}

${directDownloads(t("从 GitHub Releases 下载适用于 macOS 的 Universal 版本。"))}

${localizedBody}

## CLI

\`\`\`bash
slimluma compress photo.jpg movie.mov report.pdf
slimluma compress movie.mov --video-codec hevc --target-size-mb 25
slimluma engines
\`\`\`

${privacy}

[${t("有关架构、验证边界、许可证和发布说明，请查看主仓库文档。")}](../../README.md)

[Contributing](../../CONTRIBUTING.md) · [Security](../../SECURITY.md) · [Code of Conduct](../../CODE_OF_CONDUCT.md) · [Support](../../SUPPORT.md)
`;
}

function releaseNotesHref(tagName, locale) {
  return `${repositoryURL}/blob/main/docs/releases/${tagName}/README.${locale}.md`;
}

function releaseLanguageSelector(currentLocale = null) {
  return languageSelector(
    currentLocale,
    (locale) => releaseNotesHref(tag, locale),
  );
}

function localizedReleaseDocument(locale, name, direction) {
  const table = translations(locale);
  const t = (key) => translated(table, locale, key);
  const highlights = releaseConfig.highlightKeys.map((key) => t(key));
  const productReadme = githubLocales.find(
    (item) => item.locale === locale,
  ).canonicalReadme;
  const productReadmeURL = `${repositoryURL}/blob/main/${productReadme}`;

  if (direction === "rtl") {
    return `<!-- Generated by scripts/generate-github-readmes.mjs. -->
<!-- locale:${locale} -->

# SlimLuma ${version} — ${name}

${releaseLanguageSelector(locale)}

${directDownloads(t("从 GitHub Releases 下载适用于 macOS 的 Universal 版本。"))}

<div dir="rtl" align="right">
<p>${escapeHTML(t(releaseConfig.taglineKey))}</p>
<ul>
${highlights.map((item) => `<li>${escapeHTML(item)}</li>`).join("\n")}
</ul>
<p><a href="${productReadmeURL}">SlimLuma ${escapeHTML(name)}</a></p>
</div>
`;
  }

  return `<!-- Generated by scripts/generate-github-readmes.mjs. -->
<!-- locale:${locale} -->

# SlimLuma ${version} — ${name}

${releaseLanguageSelector(locale)}

${directDownloads(t("从 GitHub Releases 下载适用于 macOS 的 Universal 版本。"))}

${t(releaseConfig.taglineKey)}

${highlights.map((item) => `- ${item}`).join("\n")}

[SlimLuma ${name}](${productReadmeURL})
`;
}

function releaseIndexDocument() {
  const english = translations("en");
  const chinese = translations("zh-Hans");
  const tEnglish = (key) => translated(english, "en", key);
  const tChinese = (key) => translated(chinese, "zh-Hans", key);
  const englishHighlights = releaseConfig.highlightKeys
    .map((key) => `- ${tEnglish(key)}`)
    .join("\n");
  const chineseHighlights = releaseConfig.highlightKeys
    .map((key) => `- ${tChinese(key)}`)
    .join("\n");

  return `<!-- Generated by scripts/generate-github-readmes.mjs. -->

# SlimLuma ${version}

${directDownloads(`Download SlimLuma ${version} for macOS — Universal DMG`)}

## Release notes in 20 languages

${releaseLanguageSelector()}

## English

${tEnglish(releaseConfig.taglineKey)}

${englishHighlights}

## 简体中文

${tChinese(releaseConfig.taglineKey)}

${chineseHighlights}

## Verify / 验证

Download \`SHA256SUMS\` with the release files, then run:

\`\`\`bash
shasum -a 256 -c SHA256SUMS
\`\`\`

External engines remain separately licensed and are not bundled. See
[THIRD_PARTY_NOTICES.md](${repositoryURL}/blob/main/THIRD_PARTY_NOTICES.md).
`;
}

function writeOrCheck(path, expected, mismatches) {
  if (checksOnly) {
    if (!existsSync(path) || readFileSync(path, "utf8") !== expected) {
      mismatches.push(path);
    }
  } else {
    mkdirSync(resolve(path, ".."), { recursive: true });
    writeFileSync(path, expected);
  }
}

mkdirSync(readmeOutputRoot, { recursive: true });
const mismatches = [];
for (const { locale, name, direction = "ltr" } of githubLocales) {
  writeOrCheck(
    join(projectRoot, generatedReadmePath(locale)),
    readmeDocument(locale, direction),
    mismatches,
  );
  writeOrCheck(
    join(releasesRoot, tag, `README.${locale}.md`),
    localizedReleaseDocument(locale, name, direction),
    mismatches,
  );
}
writeOrCheck(
  join(releasesRoot, `${tag}.md`),
  releaseIndexDocument(),
  mismatches,
);

if (mismatches.length > 0) {
  throw new Error(
    `GitHub localization assets are stale:\n${mismatches.join("\n")}`,
  );
}

console.log(
  `${checksOnly ? "Verified" : "Generated"} ${githubLocales.length} GitHub README translations and ${githubLocales.length} localized ${tag} release notes.`,
);
