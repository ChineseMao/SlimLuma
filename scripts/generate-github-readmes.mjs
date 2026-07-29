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
  githubLicenseNotices,
  githubLocales,
  githubReleaseLicenseNotices,
} from "./github-locales.mjs";

const projectRoot = resolve(import.meta.dirname, "..");
const resourcesRoot = join(projectRoot, "Sources", "SlimLuma", "Resources");
const readmeOutputRoot = join(projectRoot, "docs", "readme");
const releasesRoot = join(projectRoot, "docs", "releases");
const checksOnly = process.argv.includes("--check");
const repositoryURL = "https://github.com/ChineseMao/SlimLuma";
const publisherName = "SlimLuma copyright holders";
const publisherTeamID = "PRIVATE_TEAM_ID";
const currentLicenseURL = `${repositoryURL}/blob/main/LICENSE`;
const historicalLicenseURL = `${repositoryURL}/blob/v0.2.0/LICENSE`;

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
const developmentVersion = info.CFBundleShortVersionString;
if (
  typeof developmentVersion !== "string"
  || !/^\d+\.\d+\.\d+$/.test(developmentVersion)
) {
  throw new Error("Support/Info.plist does not contain a semantic app version.");
}

const releaseStatePath = join(releasesRoot, "release-state.json");
const releaseState = JSON.parse(readFileSync(releaseStatePath, "utf8"));
const latestPublishedVersion = releaseState.latestPublishedVersion;
const releaseNotesVersion = releaseState.generatedReleaseNotesVersion;
for (const [name, value] of Object.entries({
  latestPublishedVersion,
  generatedReleaseNotesVersion: releaseNotesVersion,
})) {
  if (typeof value !== "string" || !/^\d+\.\d+\.\d+$/.test(value)) {
    throw new Error(`${releaseStatePath} has an invalid ${name}.`);
  }
}
if (developmentVersion === latestPublishedVersion) {
  throw new Error(
    "Development and latest published versions must differ after the license transition.",
  );
}

const tag = `v${releaseNotesVersion}`;
const pinnedReleaseLicenseURL = `${repositoryURL}/blob/${tag}/LICENSE`;
const releaseLicenseURL =
  releaseNotesVersion === "0.2.0"
    ? currentLicenseURL
    : pinnedReleaseLicenseURL;
const releaseLicenseLabel =
  releaseNotesVersion === "0.2.0"
    ? "main LICENSE"
    : `${tag} LICENSE`;
const pinnedThirdPartyNoticesURL =
  `${repositoryURL}/blob/${tag}/THIRD_PARTY_NOTICES.md`;
const releaseConfigPath = join(releasesRoot, `${tag}.i18n.json`);
if (!existsSync(releaseConfigPath)) {
  throw new Error(
    `Missing localized release configuration: ${releaseConfigPath}`,
  );
}
const releaseConfig = JSON.parse(readFileSync(releaseConfigPath, "utf8"));
const usesTranslationKeys =
  typeof releaseConfig.taglineKey === "string"
  && Array.isArray(releaseConfig.highlightKeys)
  && releaseConfig.highlightKeys.length > 0
  && releaseConfig.highlightKeys.every((key) => typeof key === "string");
const localizedReleaseCopy = releaseConfig.locales;
const usesLocalizedCopy =
  localizedReleaseCopy !== null
  && typeof localizedReleaseCopy === "object"
  && !Array.isArray(localizedReleaseCopy);
if (usesTranslationKeys === usesLocalizedCopy) {
  throw new Error(
    `${releaseConfigPath} must define either localization keys or localized copy.`,
  );
}
if (usesLocalizedCopy) {
  const expectedLocales = githubLocales.map(({ locale }) => locale).sort();
  const actualLocales = Object.keys(localizedReleaseCopy).sort();
  if (JSON.stringify(actualLocales) !== JSON.stringify(expectedLocales)) {
    throw new Error(
      `${releaseConfigPath} localized copy does not cover exactly the GitHub locales.`,
    );
  }
  for (const locale of expectedLocales) {
    const copy = localizedReleaseCopy[locale];
    if (
      copy === null
      || typeof copy !== "object"
      || typeof copy.tagline !== "string"
      || copy.tagline.length === 0
      || !Array.isArray(copy.highlights)
      || copy.highlights.length === 0
      || copy.highlights.some(
        (highlight) => typeof highlight !== "string" || highlight.length === 0,
      )
    ) {
      throw new Error(
        `${releaseConfigPath} has invalid localized copy for ${locale}.`,
      );
    }
  }
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

function releaseCopy(locale, table) {
  if (usesLocalizedCopy) {
    return localizedReleaseCopy[locale];
  }
  return {
    tagline: translated(table, locale, releaseConfig.taglineKey),
    highlights: releaseConfig.highlightKeys.map((key) =>
      translated(table, locale, key)
    ),
  };
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
[![License: All Rights Reserved](https://img.shields.io/badge/License-All%20Rights%20Reserved-5b55ea.svg)](${currentLicenseURL})`;
}

function releaseAssets(version) {
  const releaseAssetURL =
    `${repositoryURL}/releases/download/v${version}`;
  const assetNames = {
    dmg: `SlimLuma-${version}-macOS-universal.dmg`,
    zip: `SlimLuma-${version}-macOS-universal.zip`,
    cli: `slimluma-${version}-macOS-universal.tar.gz`,
    checksums: "SHA256SUMS",
  };
  return {
    dmg: `${releaseAssetURL}/${assetNames.dmg}`,
    zip: `${releaseAssetURL}/${assetNames.zip}`,
    cli: `${releaseAssetURL}/${assetNames.cli}`,
    checksums: `${releaseAssetURL}/${assetNames.checksums}`,
  };
}

function directDownloads(primaryLabel, version = latestPublishedVersion) {
  const assets = releaseAssets(version);
  return `> [!IMPORTANT]
> **[⬇ ${primaryLabel}](${assets.dmg})**
>
> Apple Silicon + Intel · [App ZIP](${assets.zip}) · [CLI](${assets.cli}) · [SHA-256](${assets.checksums})`;
}

function currentLicenseNotice(locale, direction) {
  const notice = githubLicenseNotices[locale];
  if (typeof notice !== "string" || notice.length === 0) {
    throw new Error(`Missing GitHub license notice for ${locale}`);
  }
  if (direction === "rtl") {
    return `<div dir="rtl" align="right">
<p><strong>${escapeHTML(publisherName)} (${publisherTeamID})</strong></p>
<p><a href="${currentLicenseURL}">${escapeHTML(notice)}</a></p>
</div>`;
  }
  return `> **${publisherName} (${publisherTeamID})**
>
> [${notice}](${currentLicenseURL})`;
}

function releaseLicenseNotice(locale, direction) {
  const notice = githubReleaseLicenseNotices[locale];
  if (typeof notice !== "string" || notice.length === 0) {
    throw new Error(`Missing GitHub release-license notice for ${locale}`);
  }
  const links = `<a href="${historicalLicenseURL}">v0.2.0 MIT LICENSE</a> · <a href="${releaseLicenseURL}">${releaseLicenseLabel}</a>`;
  if (direction === "rtl") {
    return `<div dir="rtl" align="right">
<p><strong>${escapeHTML(publisherName)} (${publisherTeamID})</strong></p>
<p>${escapeHTML(notice)}</p>
<p>${links}</p>
</div>`;
  }
  return `> **Publisher:** ${publisherName} (${publisherTeamID})
>
> ${notice}
>
> [v0.2.0 MIT LICENSE](${historicalLicenseURL}) · [${releaseLicenseLabel}](${releaseLicenseURL})`;
}

function rtlReadmeBody(t) {
  const assets = releaseAssets(latestPublishedVersion);
  const featureRows = [
    [t("图片"), t("先纠正方向，再按比例缩小、重编码和处理 profile；PNG、WebP 与 AVIF 的设置会映射为对应引擎参数。")],
    [t("视频"), t("画面缩放保持比例、不放大并对齐偶数尺寸；音频转 AAC，MP4 字幕转 mov_text，MKV 字幕尽量复制，MP4 开启 faststart。")],
    ["PDF", t("qpdf 会重组对象流并重新压缩可压缩数据；Ghostscript 还能降低内嵌图片的像素密度、质量或色彩复杂度。文字型 PDF 通常收益较小，扫描件通常更明显。")],
    [t("目标文件大小"), `${t("SlimLuma 会逐级调整质量；必要时缩小尺寸，以得到不超过目标的最清晰安全结果。目标大小需要 ImageMagick。")} ${t("H.264 与 HEVC 可按目标大小执行两遍软件编码，并为音频、字幕和容器预留空间；AV1 与单独音频压缩暂不支持目标体积。")}`],
    [t("文件队列"), t("图片、视频和 PDF 可以混合加入；队列允许 1–6 个并发任务，开始时冻结整批设置。")],
    [t("安全"), t("隐藏临时输出、类型完整性检查、体积策略和永不覆盖原件的安全落盘。")],
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
<li><a href="${assets.dmg}">${escapeHTML(t("从 GitHub Releases 下载适用于 macOS 的 Universal 版本。"))}</a></li>
<li>${escapeHTML(t("将 SlimLuma.app 移到“应用程序”文件夹。"))}</li>
<li>${escapeHTML(t("打开“引擎与设置”并选择“一键补齐推荐引擎”。"))}</li>
</ol>
<p>${escapeHTML(t("SlimLuma 使用 Homebrew 安装 ImageMagick、FFmpeg、qpdf 与 Ghostscript；媒体文件始终留在这台 Mac。"))}</p>
</div>`;
}

function ltrReadmeBody(t) {
  const assets = releaseAssets(latestPublishedVersion);
  return `> ${t("本地媒体瘦身工具")}

${t("支持常见图片、视频和 PDF，也可以拖入整个文件夹")}

## ${t("功能与原理")}

- **${t("图片")}** — ${t("先纠正方向，再按比例缩小、重编码和处理 profile；PNG、WebP 与 AVIF 的设置会映射为对应引擎参数。")}
- **${t("视频")}** — ${t("画面缩放保持比例、不放大并对齐偶数尺寸；音频转 AAC，MP4 字幕转 mov_text，MKV 字幕尽量复制，MP4 开启 faststart。")}
- **PDF** — ${t("qpdf 会重组对象流并重新压缩可压缩数据；Ghostscript 还能降低内嵌图片的像素密度、质量或色彩复杂度。文字型 PDF 通常收益较小，扫描件通常更明显。")}
- **${t("目标文件大小")}** — ${t("SlimLuma 会逐级调整质量；必要时缩小尺寸，以得到不超过目标的最清晰安全结果。目标大小需要 ImageMagick。")} ${t("H.264 与 HEVC 可按目标大小执行两遍软件编码，并为音频、字幕和容器预留空间；AV1 与单独音频压缩暂不支持目标体积。")}
- **${t("文件队列")}** — ${t("图片、视频和 PDF 可以混合加入；队列允许 1–6 个并发任务，开始时冻结整批设置。")}
- **${t("安全")}** — ${t("隐藏临时输出、类型完整性检查、体积策略和永不覆盖原件的安全落盘。")}
- **${t("结果守门")}** — ${t("按图片、视频或 PDF 的完整性规则重新读取，发现关键退化就拒绝输出。")}
- **${t("自动化")}** — ${t("从剪贴板、监控文件夹和 Finder 直接进入压缩队列")}

## ${t("安装")}

1. [${t("从 GitHub Releases 下载适用于 macOS 的 Universal 版本。")}](${assets.dmg})
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

${currentLicenseNotice(locale, direction)}

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
  return `${repositoryURL}/blob/${tagName}/docs/releases/${tagName}/README.${locale}.md`;
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
  const copy = releaseCopy(locale, table);
  const { tagline, highlights } = copy;
  const productReadme = githubLocales.find(
    (item) => item.locale === locale,
  ).canonicalReadme;
  const productReadmeURL = `${repositoryURL}/blob/${tag}/${productReadme}`;

  if (direction === "rtl") {
    return `<!-- Generated by scripts/generate-github-readmes.mjs. -->
<!-- locale:${locale} -->

# SlimLuma ${releaseNotesVersion} — ${name}

${releaseLanguageSelector(locale)}

${directDownloads(t("从 GitHub Releases 下载适用于 macOS 的 Universal 版本。"), releaseNotesVersion)}

${releaseLicenseNotice(locale, direction)}

<div dir="rtl" align="right">
<p>${escapeHTML(tagline)}</p>
<ul>
${highlights.map((item) => `<li>${escapeHTML(item)}</li>`).join("\n")}
</ul>
<p><a href="${productReadmeURL}">SlimLuma ${escapeHTML(name)}</a></p>
</div>
`;
  }

  return `<!-- Generated by scripts/generate-github-readmes.mjs. -->
<!-- locale:${locale} -->

# SlimLuma ${releaseNotesVersion} — ${name}

${releaseLanguageSelector(locale)}

${directDownloads(t("从 GitHub Releases 下载适用于 macOS 的 Universal 版本。"), releaseNotesVersion)}

${releaseLicenseNotice(locale, direction)}

${tagline}

${highlights.map((item) => `- ${item}`).join("\n")}

[SlimLuma ${name}](${productReadmeURL})
`;
}

function releaseIndexDocument() {
  const english = translations("en");
  const chinese = translations("zh-Hans");
  const englishCopy = releaseCopy("en", english);
  const chineseCopy = releaseCopy("zh-Hans", chinese);
  const englishHighlights = englishCopy.highlights
    .map((highlight) => `- ${highlight}`)
    .join("\n");
  const chineseHighlights = chineseCopy.highlights
    .map((highlight) => `- ${highlight}`)
    .join("\n");
  const englishCurrentTerms =
    releaseNotesVersion === "0.2.0"
      ? "Current development uses the terms in"
      : `SlimLuma ${releaseNotesVersion} uses the terms in`;
  const chineseCurrentTerms =
    releaseNotesVersion === "0.2.0"
      ? "当前开发版本采用"
      : `SlimLuma ${releaseNotesVersion} 采用`;

  return `<!-- Generated by scripts/generate-github-readmes.mjs. -->

# SlimLuma ${releaseNotesVersion}

${directDownloads(`Download SlimLuma ${releaseNotesVersion} for macOS — Universal DMG`, releaseNotesVersion)}

## Release notes in 20 languages

${releaseLanguageSelector()}

## English

${englishCopy.tagline}

${englishHighlights}

## 简体中文

${chineseCopy.tagline}

${chineseHighlights}

## Publisher and license / 发布主体与许可

Official publisher / 官方发布主体:
**${publisherName} (${publisherTeamID})**

SlimLuma 0.2.0 source was released under the
[MIT License](${historicalLicenseURL}); that historical grant is not revoked.
${englishCurrentTerms} [${releaseLicenseLabel}](${releaseLicenseURL}).

SlimLuma 0.2.0 源码按 [MIT License](${historicalLicenseURL}) 发布，已授予的历史
权利不被撤销。${chineseCurrentTerms} [${releaseLicenseLabel}](${releaseLicenseURL}) 中的条款。

## Verify / 验证

Download \`SHA256SUMS\` with the release files, then run:

\`\`\`bash
shasum -a 256 -c SHA256SUMS
\`\`\`

External engines remain separately licensed and are not bundled. See
[THIRD_PARTY_NOTICES.md](${pinnedThirdPartyNoticesURL}).
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
