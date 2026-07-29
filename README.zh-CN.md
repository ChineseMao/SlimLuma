# SlimLuma

[![CI](https://github.com/ChineseMao/SlimLuma/actions/workflows/ci.yml/badge.svg)](https://github.com/ChineseMao/SlimLuma/actions/workflows/ci.yml)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111111)](https://github.com/ChineseMao/SlimLuma/releases)
[![许可：保留所有权利](https://img.shields.io/badge/%E8%AE%B8%E5%8F%AF-%E4%BF%9D%E7%95%99%E6%89%80%E6%9C%89%E6%9D%83%E5%88%A9-5b55ea.svg)](LICENSE)

[English](README.md) · [**简体中文**](README.zh-CN.md) ·
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
> **[⬇ 下载 SlimLuma 0.2.0 macOS 通用安装包（DMG）](https://github.com/ChineseMao/SlimLuma/releases/download/v0.2.0/SlimLuma-0.2.0-macOS-universal.dmg)**
>
> Apple Silicon + Intel · [App ZIP](https://github.com/ChineseMao/SlimLuma/releases/download/v0.2.0/SlimLuma-0.2.0-macOS-universal.zip) · [命令行工具](https://github.com/ChineseMao/SlimLuma/releases/download/v0.2.0/slimluma-0.2.0-macOS-universal.tar.gz) · [SHA-256 校验](https://github.com/ChineseMao/SlimLuma/releases/download/v0.2.0/SHA256SUMS)

SlimLuma 是一个免费下载、源码公开可审阅、本地运行的 macOS 图片、视频和 PDF
批量压缩工具。它负责安全可靠的工作流，把编解码交给 ImageMagick、FFmpeg、qpdf
等成熟引擎。

## 已实现

- 图片：JPEG、PNG、WebP、AVIF、HEIC 等常见格式，支持转换、质量、最大宽高、
  元数据和压缩强度。无损编码仅对 PNG、WebP，以及保持原格式时的 GIF、TIFF、
  BMP、JPEG 2000 等兼容格式开放；JPEG、HEIC、AVIF 会在任务开始前拦截。
- “全部移除元数据”与“保留 ICC”可以同时兑现：检测到嵌入 ICC 时先提取色彩
  配置，彻底清理其余元数据后再恢复 ICC，并由真实文件集成测试覆盖。
- 图片支持目标体积：ImageMagick 会从原件反复编码，逐级调整质量，并在必要时
  缩小尺寸，选择不超过目标的最清晰安全结果。
- 视频：H.264、HEVC、AV1，支持质量、速度、VideoToolbox 硬件加速、分辨率、
  帧率、音频码率和元数据清理。AV1 会读取当前 FFmpeg 的真实编码器能力，优先
  `libsvtav1`、后备 `libaom-av1`，两者都不存在时会给出可恢复的错误。
- 视频输入与输出由配套 `ffprobe` 检查时长、视频/音频/字幕轨道、章节、语言、
  默认/强制标记、字幕内容包和 HDR 色彩标记；AVFoundation 只作为 macOS 系统
  预览兼容性信号，不会误拒绝有效的 MKV / WebM。
- H.264 与 HEVC 支持目标体积两遍软件编码，自动为音频、字幕和容器预留空间；
  处理过程提供确定进度、预计剩余时间和真正的暂停/继续。
- FFmpeg 只有在主程序和同目录 `ffprobe` 同时存在时才标记“可用”；如果只检测到
  FFmpeg，工具页会显示“部分失效”，一键修复会执行 `brew reinstall ffmpeg`，
  而不是把缺少完整性检查组件的安装误报为就绪。
- PDF：无损模式优先 qpdf；均衡、自定义和极致模式优先 Ghostscript 深度降采样。
- 加密 PDF 可按单文件输入密码；密码不会持久化到历史、预设或应用日志。运行任务时
  通过 `0600` 临时文件交给 qpdf，压缩后复制原加密策略、重新解锁验收并删除临时
  凭据。
- 当 qpdf 与 Ghostscript 都可用时，PDF 强力压缩采用 qpdf 结构修复 →
  Ghostscript 压缩 → qpdf 网页线性化，并以页数、书签、链接/批注、表单、签名
  字段等数量及加密、可搜索文本和线性化信号作为结构守门后才保留输出。该检查不等于
  对链接目标、表单行为或每一页视觉内容做语义证明。
- qpdf 非无损模式可按“图片质量”重编码符合条件的内嵌图片；图片 DPI 与灰度转换
  只有 Ghostscript 路径会执行，界面会按实际引擎禁用无效设置。
- GIF / 动画图片逐帧解码，并比较帧数、每帧播放时长和循环次数；当前安全支持
  保持原格式或转换为 WebP。
- 拖放文件或目录、递归扫描、混合类型批处理和 1–6 个并行任务。
- 每个队列文件都可冻结独立参数，其余文件继续使用全局设置；批次开始后统一锁定，
  防止运行中参数漂移。
- 日常、网页、归档、极致瘦身、隐私分享五套内置预设，以及自定义预设。
- 预设可导入/导出带版本的 JSON；导入会限制文件大小、数量和参数范围。
- 指定输出目录、文件名后缀、冲突避让、修改时间保留。
- 输出后重新解码验证；默认不覆盖原件、不保留变大的结果。
- 本地历史记录、累计节省统计、Finder 定位和结果打开。
- 批次结束后的“重新处理”会同步重置结果并立即启动新批次，不需要再点一次
  “开始压缩”。
- Quick Look 并排对比压缩前后文件。
- 剪贴板文件/图片导入，可选择导入后自动开始。
- 多文件夹监控、稳定性等待、递归扫描、自动开始与输出防循环；处理过程中到达的
  自动任务会排队，并在当前批次结束后续跑，不会因“正在处理”而丢失启动请求。
- 输出目录或文件名后缀改变时，监控规则会动态刷新且不重复导入已有文件；监控会
  忽略当前输出目录、当前规范化后缀和旧版 `-slim` 后缀，避免反复压缩自身输出。
- Finder 服务与“打开方式”导入；macOS 15 及以上提供原生快捷指令动作。
- 主工作区按单窗口模型实现；Finder“打开方式”的代码路径会把文件追加到现有队列，
  并抑制同一打开事件的短时重复路由。
- 自动检测 Homebrew、MacPorts、系统路径和未来 app 内置引擎。
- “引擎与设置”支持通过 Homebrew 一键安装单个或全部推荐引擎；Homebrew 尚未
  安装时会打开官网并持续检测，就绪后自动续装已选择引擎，无需第二次点击。
- PDF 设置会在开始前说明当前实际能力；失败和“处理后没有变小”都会保留在
  队列与历史记录中，不再只显示一次性弹窗。
- “媒体压缩”内集中放置添加、剪贴板导入和清空队列；窗口全局工具栏不再承载
  容易误解的文件操作。
- 清空队列、清空历史和删除预设均有明确取消路径；任务菜单支持
  `Command-Return` 开始与 `Command-.` 取消，状态图标不会给 VoiceOver 制造重复朗读。
- 独立 `slimluma` CLI 使用 Apple Swift Argument Parser，支持目标体积、预设文件、
  PDF 密码文件、JSON 输出、dry-run 与引擎检查。
- GitHub Actions 提供 CI 与受保护的手工发行入口：从 `main` 的固定签名人列表验证
  signed tag，并拒绝未合并到 `main` 的提交；Universal 构建、Developer ID、
  Hardened Runtime、Apple 公证、staple、Gatekeeper、DMG/ZIP/CLI 与 SHA-256
  均有门禁。

## 环境

- macOS 14 或更新版本
- Xcode 15.3 / Swift 5.10 或更新版本

可以直接在 app 的“引擎与设置”点击“一键补齐推荐引擎”。也可以手动运行：

```bash
brew install imagemagick ffmpeg qpdf ghostscript
```

Ghostscript 使用 AGPL/商业双许可，SlimLuma 不会捆绑它；只有用户明确点击安装时，
才会由 Homebrew 作为独立程序安装。FFmpeg 的许可取决于具体构建参数；分发二进制前
请阅读 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

没有 ImageMagick 时，只有 `sips` 能准确兑现当前设置的任务才会使用系统后备。
当前后备要求“移除定位和拍摄信息”且关闭 ICC 保留；WebP、GIF、精确元数据策略、
ICC 保留或系统后备无法保证的无损输出会在写出前停止，并提示安装 ImageMagick。
视频需要同时提供 FFmpeg 与配套 `ffprobe`。

PDF 自动模式会根据策略和已安装引擎降级：非无损模式依次选择 Ghostscript、qpdf、
PDFKit；“无损整理”优先 qpdf，qpdf 缺失时即使用 PDFKit，而不会让 Ghostscript
冒充无损后备。PDFKit 不支持网页快速打开，系统会明确说明该选项本次未应用，也不会
把这项后备能力缺失误判为输出损坏。

## 语言

SlimLuma 跟随 macOS 的应用语言设置，提供 18 个语言层、20 个 locale：

`en`、`zh-Hans`、`zh-Hant`、`hi`、`es-419`、`es-ES`、`ar`、`fr`、`bn`、
`pt-BR`、`pt-PT`、`id`、`ur`、`ru`、`de`、`ja`、`sw`、`pa-Arab`、`te`、`pcm`。

覆盖范围以 Ethnologue 2026 的母语与第二语言使用者合计为主要基线，并额外纳入在
其他人口口径中可能越过一亿门槛的斯瓦希里语、西旁遮普语和泰卢固语。阿拉伯语界面
采用现代标准阿拉伯语，同时服务现代标准阿拉伯语与埃及阿拉伯语人群；西旁遮普语
使用 Shahmukhi（阿拉伯字母）而不是 Gurmukhi。完整口径、系统入口和测试方式见
[docs/LOCALIZATION_2026-07-28.md](docs/LOCALIZATION_2026-07-28.md)。

嵌套的图片、视频和 PDF 完整性错误也会按当前语言拆分并本地化，动态数量继续保留；
文件名等用户数据不翻译。非英文 locale 还必须通过“不能只是英文占位副本”的门禁，
其中包括尼日利亚皮钦语 `pcm`。

## 开发

直接用 Xcode 打开 `Package.swift`，选择 `SlimLumaApp` scheme 运行；或使用：

```bash
swift run SlimLumaApp
swift test
```

生成可双击的本地 `.app`：

```bash
chmod +x scripts/package-app.sh
./scripts/package-app.sh
./scripts/verify-packaged-app.sh
open dist/SlimLuma.app
```

脚本生成同时支持 Apple Silicon 与 Intel 的 Universal Release 二进制、AppIcon、
Finder Services / App Intents 元数据和 Info.plist。未传签名身份时只生成本地
ad-hoc 包；传入 `SLIMLUMA_CODE_SIGN_IDENTITY` 时会启用 Developer ID、
Hardened Runtime 与安全时间戳。Apple 公证、DMG / ZIP / CLI、Gatekeeper 和
SHA-256 的完整流程见 [docs/RELEASING.md](docs/RELEASING.md)。每一项权限、
证书、签名、公证与验证为什么需要、缺少时会怎样，见
[发布信任链](docs/RELEASE_TRUST_CHAIN.zh-Hans.md)。

打包不是“先删旧应用再碰运气”：脚本会先同步并复核 20 个系统语言表、运行测试，
在同一磁盘的暂存目录内完成 Universal 构建、元数据提取、签名和产物验证；只有全部
通过才替换 `dist/SlimLuma.app`。验证器同时检查冻结清单中的全部主文案、9 个复数文案、
Finder 服务、快捷指令译文和 App Intents 动作数据，失败时保留原来的可用应用。

## 架构与安全

核心是独立的 `SlimLumaKit`：

```text
SwiftUI
  → typed CompressionSettings
  → bounded task scheduler
  → ImageMagick / FFmpeg / qpdf / Ghostscript adapter
  → hidden temporary output
  → ImageIO / ffprobe / PDFKit source-output integrity validation
  → AVFoundation system-preview compatibility signal
  → unique final file + local history
```

文件路径作为独立参数传给 `Process`，不拼接 Shell 命令。引擎只写应用私有临时
工作区；验证成功后先复制到目标卷中的 `0700` 隐藏私有暂存目录，锁定归属标记、
同步并核对大小与 inode 后，再用排他原子重命名公开最终名称。输出目录处理期间被
用户改名时，会按目录文件描述符解析并返回实际新路径。外部进程即使在
`Process.run()` 启动阶段失败，也会从
受管进程表移除并解除管道回调，后续取消或重试不会命中残留任务。完整设计见
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

当前已分别完成自动测试、真实 PDF、Universal 打包、Developer ID、运行时 UI、
RTL、键盘关闭路径和可访问性树验证；这些仍是不同验证层级，任何一层通过都不能替代
其他层。完整证据与仍需母语 / VoiceOver 人工审校的边界见发布和国际化文档。

全面竞品定位、能力矩阵、内部闭环和路线优先级见
[docs/COMPETITOR_COMPARISON_2026-07-28.md](docs/COMPETITOR_COMPARISON_2026-07-28.md)。

国际化范围与验证见
[docs/LOCALIZATION_2026-07-28.md](docs/LOCALIZATION_2026-07-28.md)；版本变化、安全
披露与贡献流程分别见 [CHANGELOG.md](CHANGELOG.md)、[SECURITY.md](SECURITY.md)
和 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 许可

当前开发源码公开仅供审阅，属于[保留所有权利的专有软件](LICENSE)。官方发布主体为
`SlimLuma copyright holders`。公开可见不代表开源；除 GitHub
平台条款所需权利外，不额外授予复制、修改、分发、再许可或销售等权利。官方未修改的
二进制可按 `LICENSE` 中的有限授权使用。

SlimLuma 0.2.0 曾按 MIT License 发布，已经授予的历史权利不会被撤销；后续项目
材料以对应提交或版本附带的条款为准。外部引擎继续遵循各自许可。发布主体与发布门禁
见 [PUBLISHER.md](PUBLISHER.md)，第三方许可见
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
