# Changelog / 更新日志

All notable changes are documented here. Dates use UTC.

## 0.2.0 — 2026-07-28

### Added / 新增

- Image target-size search and H.264 / HEVC two-pass target-size encoding. /
  图片目标体积搜索，以及 H.264 / HEVC 两遍目标体积编码。
- Per-file queue settings, preset JSON import/export, and a standalone
  `slimluma` CLI. / 逐文件队列设置、预设 JSON 导入导出和独立 `slimluma`
  命令行工具。
- Real progress, ETA, pause, resume, and managed-process cancellation. /
  真实进度、预计剩余时间、暂停、继续和受管进程取消。
- Encrypted PDF password flow with in-memory credentials and restored
  encryption. / 加密 PDF 密码流程，凭据只驻留内存并在输出中恢复加密策略。
- Video chapter, HDR, language, disposition, and subtitle-packet validation.
  / 视频章节、HDR、语言、轨道标记与字幕数据包验证。
- Homebrew detection, official-site handoff, automatic install continuation,
  and partial FFmpeg repair. / Homebrew 检测、官网引导、安装自动续接和不完整
  FFmpeg 修复。
- A detailed in-app feature and implementation-principles module. /
  应用内完整功能与实现原理模块。
- 20 product locales, RTL layout, and 20 generated GitHub README translations.
  / 20 个产品 locale、RTL 布局和 20 份自动生成的 GitHub README。

### Changed / 改进

- Compression actions now live inside the media workspace. /
  压缩操作集中放在媒体工作区内。
- Settings use bordered, visibly interactive controls and explain unavailable
  engine-specific options. / 设置使用有边界、可辨识的交互控件，并解释当前引擎
  无法执行的选项。
- PDF processing now uses qpdf repair, Ghostscript compression, optional qpdf
  linearization, and source-output integrity comparison. / PDF 链路采用 qpdf
  修复、Ghostscript 压缩、可选 qpdf 线性化和源文件/输出完整性对比。
- The app and CLI are separate Universal products with packaging collision
  gates. / App 与 CLI 是独立 Universal 产品，并由打包门禁防止产物混淆。

### Fixed / 修复

- PDF outlines lost by the previous Ghostscript-only path. /
  修复旧 Ghostscript 单链路丢失 PDF 书签的问题。
- Comparison windows that could not be closed. / 修复对比窗口无法关闭的问题。
- Queue reprocessing that required a second Start action. /
  修复重新处理仍需再次点击开始的问题。
- Busy automation requests that could lose their deferred start. /
  修复繁忙时自动化请求可能丢失延迟启动的问题。
- RTL sidebar constraint crashes and reversed control/process order. /
  修复 RTL 侧栏约束崩溃及控件、流程顺序颠倒的问题。

### Release / 发布

- Developer ID, Hardened Runtime, secure timestamps, notarization, stapling,
  Gatekeeper, DMG / ZIP / CLI archives, SHA-256, and tag-driven GitHub Release
  gates. / 完成 Developer ID、Hardened Runtime、安全时间戳、公证、staple、
  Gatekeeper、DMG / ZIP / CLI、SHA-256 和 tag 驱动的 GitHub Release 门禁。
- English-first GitHub landing page, complete Simplified Chinese mirror,
  direct DMG download, 20 localized README pages, and 20 localized release
  notes. / GitHub 使用英文默认入口、完整简体中文镜像、首屏 DMG 直链、
  20 份本地化 README 和 20 份本地化版本说明。
