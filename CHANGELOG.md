# Changelog / 更新日志

All notable changes are documented here. Dates use UTC.

## 0.2.0 — 2026-07-28

### Added / 新增

- Image target-size search and H.264 / HEVC two-pass target-size encoding.
- Per-file queue settings, preset JSON import/export, and a standalone
  `slimluma` CLI.
- Real progress, ETA, pause, resume, and managed-process cancellation.
- Encrypted PDF password flow with in-memory credentials and restored
  encryption.
- Video chapter, HDR, language, disposition, and subtitle-packet validation.
- Homebrew detection, official-site handoff, automatic install continuation,
  and partial FFmpeg repair.
- A detailed in-app feature and implementation-principles module.
- 20 product locales, RTL layout, and 20 generated GitHub README translations.

### Changed / 改进

- Compression actions now live inside the media workspace.
- Settings use bordered, visibly interactive controls and explain unavailable
  engine-specific options.
- PDF processing now uses qpdf repair, Ghostscript compression, optional qpdf
  linearization, and source-output integrity comparison.
- The app and CLI are separate Universal products with packaging collision
  gates.

### Fixed / 修复

- PDF outlines lost by the previous Ghostscript-only path.
- Comparison windows that could not be closed.
- Queue reprocessing that required a second Start action.
- Busy automation requests that could lose their deferred start.
- RTL sidebar constraint crashes and reversed control/process order.

### Release / 发布

- Developer ID, Hardened Runtime, secure timestamps, notarization, stapling,
  Gatekeeper, DMG / ZIP / CLI archives, SHA-256, and tag-driven GitHub Release
  gates.
