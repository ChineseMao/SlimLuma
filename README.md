# SlimLuma

[![CI](https://github.com/ChineseMao/SlimLuma/actions/workflows/ci.yml/badge.svg)](https://github.com/ChineseMao/SlimLuma/actions/workflows/ci.yml)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111111)](https://github.com/ChineseMao/SlimLuma/releases)
[![License: All Rights Reserved](https://img.shields.io/badge/License-All%20Rights%20Reserved-5b55ea.svg)](LICENSE)

[**English**](README.md) · [简体中文](README.zh-CN.md) ·
[繁體中文](docs/readme/README.zh-Hant.md) · [हिन्दी](docs/readme/README.hi.md) ·
[Español (Latinoamérica)](docs/readme/README.es-419.md) ·
[Español (España)](docs/readme/README.es-ES.md) ·
[العربية](docs/readme/README.ar.md) · [Français](docs/readme/README.fr.md) ·
[বাংলা](docs/readme/README.bn.md) · [Português (Brasil)](docs/readme/README.pt-BR.md) ·
[Português (Portugal)](docs/readme/README.pt-PT.md) ·
[Bahasa Indonesia](docs/readme/README.id.md) · [اردو](docs/readme/README.ur.md) ·
[Русский](docs/readme/README.ru.md) · [Deutsch](docs/readme/README.de.md) ·
[日本語](docs/readme/README.ja.md) · [Kiswahili](docs/readme/README.sw.md) ·
[پنجابی](docs/readme/README.pa-Arab.md) · [తెలుగు](docs/readme/README.te.md) ·
[Naijá](docs/readme/README.pcm.md)

> [!IMPORTANT]
> **[⬇ Download SlimLuma 0.2.0 for macOS — Universal DMG](https://github.com/ChineseMao/SlimLuma/releases/download/v0.2.0/SlimLuma-0.2.0-macOS-universal.dmg)**
>
> Apple Silicon + Intel · [App ZIP](https://github.com/ChineseMao/SlimLuma/releases/download/v0.2.0/SlimLuma-0.2.0-macOS-universal.zip) · [CLI](https://github.com/ChineseMao/SlimLuma/releases/download/v0.2.0/slimluma-0.2.0-macOS-universal.tar.gz) · [SHA-256](https://github.com/ChineseMao/SlimLuma/releases/download/v0.2.0/SHA256SUMS)

SlimLuma is a free-to-download, source-visible, local-first macOS app for
compressing images, animated images, videos, and PDF files. It provides a safe,
configurable workflow while delegating codec work to mature tools such as
ImageMagick, FFmpeg, qpdf, and optional Ghostscript.

Media stays on your Mac. Originals are not overwritten.

## Quick start

1. Open the downloaded DMG and move `SlimLuma.app` to Applications.
2. Launch SlimLuma.
3. Open **Engines & Settings** and choose **Install Recommended Engines**.

The Universal release supports both Apple Silicon and Intel Macs. Published
DMGs are Developer ID signed, Apple-notarized, stapled, Gatekeeper-checked, and
shipped with `SHA256SUMS`.

## What it compresses

- **Images** — JPEG, PNG, WebP, AVIF, HEIC, GIF, TIFF, BMP, JPEG 2000, and
  other formats supported by the active engine. Configure quality, dimensions,
  conversion, metadata, ICC handling, lossless modes, and target file size.
- **Animated images** — Preserve frame count, frame timing, and loop count when
  keeping the original format or converting safely to WebP.
- **Video** — H.264, HEVC, and capability-detected AV1 with resolution, frame
  rate, audio bitrate, metadata, hardware acceleration, and two-pass target
  size for H.264 and HEVC.
- **PDF** — Lossless structural optimization, image recompression, configurable
  DPI and color conversion, encrypted PDF workflows, linearization, and
  aggressive compression when Ghostscript is available.

## Product features

- Mix images, videos, and PDFs in one queue with 1–6 concurrent jobs.
- Freeze settings per file or use global and reusable custom presets.
- Show real progress, ETA, pause, resume, cancel, retry, and persistent history.
- Drag files or folders, recurse through directories, import from Clipboard,
  Finder, watched folders, Shortcuts, or the command line.
- Detect Homebrew, MacPorts, system paths, and paired tools such as
  `ffmpeg`/`ffprobe`.
- Install one engine or all recommended engines from the app, with automatic
  continuation after Homebrew becomes available.
- Keep unique outputs, preserve modification time when requested, avoid naming
  conflicts, and discard results that are not smaller by default.
- Compare source and output side by side with Quick Look.
- Export and import versioned presets with size, count, and range validation.
- Use a standalone `slimluma` CLI with presets, target size, password files,
  JSON output, dry-run, and engine diagnostics.

## Safety model

SlimLuma never sends media to a cloud service. Professional engines write only
inside a private app-owned temporary workspace. The app reopens the result and
applies format-specific integrity checks, then copies an accepted result to a
locked `0700` staging directory on the selected destination volume. After
syncing and inode checks, it exposes the final unique name with an exclusive
same-volume atomic rename.

- Image results are decoded again and animated output is checked for frames,
  timing, and loops.
- Video results are inspected with the paired `ffprobe` for duration, semantic
  tracks, chapters, language/default/forced flags, subtitle payloads, and HDR
  color metadata.
- PDF results are checked for page count and relevant outlines, links,
  annotations, forms, signatures, encryption, searchable text, and
  linearization signals.
- Passwords for encrypted PDFs are not persisted to history, presets, or
  application logs. While a job is running, qpdf receives the password through
  a permission-restricted temporary file that is removed after use.

These checks reduce known corruption risks but are not a semantic proof of
every page, link target, form behavior, frame, or pixel.

## Engines

Use **Engines & Settings** in the app, or install engines manually:

```bash
brew install imagemagick ffmpeg qpdf ghostscript
```

ImageMagick, FFmpeg, and qpdf are recommended. Ghostscript is optional and is
used for stronger PDF image downsampling. SlimLuma does not bundle these
executables. Ghostscript uses AGPL/commercial licensing, and FFmpeg licensing
depends on its build configuration. See
[Third-party notices](THIRD_PARTY_NOTICES.md) before redistribution.

When an engine is unavailable, SlimLuma only uses a system fallback when that
fallback can honor the selected settings. It reports unsupported combinations
instead of silently producing a different result.

## Internationalization

SlimLuma ships 20 locales across 18 language layers:

`en`, `zh-Hans`, `zh-Hant`, `hi`, `es-419`, `es-ES`, `ar`, `fr`, `bn`,
`pt-BR`, `pt-PT`, `id`, `ur`, `ru`, `de`, `ja`, `sw`, `pa-Arab`, `te`,
and `pcm`.

Arabic, Urdu, and Shahmukhi Punjabi use right-to-left layouts. GitHub visitor
pages use the same reviewed application translation tables, and CI rejects
missing, stale, or English-placeholder locale output. Scope, population
baseline, system integration, and review boundaries are documented in
[Localization](docs/LOCALIZATION_2026-07-28.md).

## CLI

```bash
slimluma compress photo.jpg movie.mov report.pdf
slimluma compress movie.mov --video-codec hevc --target-size-mb 25
slimluma engines
```

## Development

Requirements:

- macOS 14 or later
- Xcode 15.3 / Swift 5.10 or later

Open `Package.swift` in Xcode and run the `SlimLumaApp` scheme, or use:

```bash
swift run SlimLumaApp
swift test
```

Build and verify a double-clickable Universal app:

```bash
chmod +x scripts/package-app.sh
./scripts/package-app.sh
./scripts/verify-packaged-app.sh
open dist/SlimLuma.app
```

Without `SLIMLUMA_CODE_SIGN_IDENTITY`, packaging produces a local ad-hoc build.
Developer ID signing, hardened runtime, notarization, DMG/ZIP/CLI packaging,
Gatekeeper, and checksum requirements are covered in
[Releasing](docs/RELEASING.md). The reason for every certificate, permission,
signature, notarization, stapling, and verification step—and the failure mode
when one is missing—is documented in the
[release trust chain](docs/RELEASE_TRUST_CHAIN.md).

## Architecture and validation

```text
SwiftUI
  → typed CompressionSettings
  → bounded task scheduler
  → ImageMagick / FFmpeg / qpdf / Ghostscript adapter
  → hidden temporary output
  → ImageIO / ffprobe / PDFKit source-output validation
  → unique final file + local history
```

Process paths and arguments are passed separately rather than assembled into
shell commands. See [Architecture](docs/ARCHITECTURE.md) for the design and
security boundaries.

Additional project documents:

- [Comprehensive competitor comparison](docs/COMPETITOR_COMPARISON_2026-07-28.md)
- [Product audit](docs/PRODUCT_AUDIT_2026-07-26.md)
- [PDF validation](docs/PDF_VALIDATION_2026-07-26.md)
- [Release readiness](docs/RELEASE_READINESS_2026-07-28.md)
- [Release trust chain](docs/RELEASE_TRUST_CHAIN.md)
- [Changelog](CHANGELOG.md)
- [Publisher and release identity](PUBLISHER.md)
- [Contributing](CONTRIBUTING.md)
- [Security policy](SECURITY.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)
- [Support](SUPPORT.md)

## License

Current development is publicly visible for review but is proprietary:
[all rights are reserved](LICENSE). The official publisher is
SlimLuma copyright holders Public visibility does not grant
open-source rights beyond GitHub's platform terms. Official, unmodified binaries
may be used under the limited grant in `LICENSE`.

SlimLuma 0.2.0 was released under the MIT License. That historical grant is not
revoked; later project materials use the terms published with their revision
or release. External engines remain under their own licenses. See
[Publisher and release identity](PUBLISHER.md) and
[third-party notices](THIRD_PARTY_NOTICES.md).
