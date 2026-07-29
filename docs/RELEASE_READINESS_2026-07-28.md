# SlimLuma 0.2.0 发布成熟度

## 当前判断

代码、功能闭环、实机 UI、国际化、Universal 构建、Developer ID、app / CLI /
DMG 公证、staple、Gatekeeper 和最终 SHA-256 已达到正式发行标准。`v0.2.0`
现已在 Public 仓库公开发布；仓库、Release、四个附件、三项哈希和下载后 DMG 的
公证/Gatekeeper 均已按匿名访客路径复核。

## 门禁

| 层级 | 验证 |
| --- | --- |
| 源码 | SwiftPM 可解析；app 与 CLI 产品分离 |
| 自动测试 | 120 项，1 项无外部 fixture 时按设计跳过，0 失败 |
| 真实文件 | 图片、动画、视频、加密 PDF、带书签 PDF |
| 代表性私有 PDF 样本 | 输出小于原件；页数、书签和网页快速打开状态均通过完整性检查 |
| 国际化 | 20 locale × 903 key；9 个复数；21 项专项测试 |
| GitHub 国际化 | 英文默认入口、完整简中镜像、20 份生成 README、20 份版本说明、首屏 DMG 直链；CI 拒绝过期和断链 |
| 实机 UI | 中文、阿拉伯语 RTL、窗口缩放、侧栏隐藏 / 恢复 |
| 外观适配 | 使用 macOS 语义色与系统材质；简体中文主工作区已完成浅色与深色实机复验 |
| 交互闭环 | 比较关闭 / Escape、取消、清空、重新处理、引擎恢复 |
| 架构 | `arm64` + `x86_64` |
| 签名 | 长期发布主体的 Developer ID Application、Hardened Runtime、安全时间戳 |
| 公证 | app、CLI 与 DMG 分别获得 Apple `Accepted`；app / DMG 已 staple |
| Gatekeeper | app execute、DMG primary signature；CLI 使用公证 Accepted + 严格 codesign |
| 附件 | app ZIP、DMG、CLI tar.gz、`SHA256SUMS` |
| GitHub Actions | tag/version 门禁、单 tag 并发保护、产物上传前校验和、临时密钥清理 |

## 本轮公证与附件证据

App、CLI archive 与 DMG 均由 Apple 公证服务返回 `Accepted`。具体 submission ID
只用于当次故障恢复，属于不必要的运营元数据，不在公开仓库长期保存。

```text
4e4a221a47fb6f1019ffba9adbab840e8dcb18cc6ff160f63829e4e2602a30d9  SlimLuma-0.2.0-macOS-universal.zip
5b0648d656f7a67da361b5199ecc929ac56aa00c6d6969429c4de40edc499864  slimluma-0.2.0-macOS-universal.tar.gz
39c0ef0e2560001ba42ef8cf252ca04abe451e271752a0b6bd834ed4dd442f06  SlimLuma-0.2.0-macOS-universal.dmg
```

三项校验和已通过 `shasum -a 256 -c`。挂载 DMG 后确认其中为 0.2.0、
`arm64 + x86_64` 的已签名 `SlimLuma.app` 和 Applications 快捷方式，并已安全卸载。

2026-07-29 再次从公开 Release 下载并复验：三个发行物的 SHA-256 全部匹配；DMG 与
App 的 stapled ticket 有效；Gatekeeper 均返回 `accepted`、
`source=Notarized Developer ID`；App 签名主体与项目固定的长期发布身份一致，版本为
0.2.0，架构为 `x86_64 arm64`，且不包含
`com.apple.security.get-task-allow`。

## 不可混淆的状态

- `swift test` 通过不等于真实媒体输出正确；
- app 已签名不等于 Apple 已公证；
- app 已公证不等于 DMG 已公证；
- workflow 成功不等于公开下载附件已人工抽查；
- 20 locale 资源完整不等于 20 种语言都完成母语编辑；
- UI 截图正常不等于完成完整 VoiceOver 朗读会话；
- 一张深色主工作区截图不等于完成 20 locale × 全页面 × 全窗口尺寸的暗色矩阵。
- Developer ID 签名主体不自动证明源码版权归属；发布主体、版权声明与贡献协议仍需
  保持书面一致。

## 许可状态

`v0.2.0` 的 tag、源码归档与 CLI 包按当时的 MIT License 公开发行；已经授予的许可
不被后续调整撤销。当前开发版本自 2026-07-29 起改为源码公开可审阅、保留全部权利，
长期发布主体与项目的规范发布身份保持一致。后续版本的 App、ZIP、DMG 和 CLI 都
必须携带该版本适用的项目许可与第三方许可文本。

## 下一版本 GitHub 发布清单

1. 更新 `Support/Info.plist` 的 version 和 build；
2. 更新 `CHANGELOG.md`；
3. 确认 `main` CI 通过；
4. 配置 `docs/RELEASING.md` 列出的 secrets；
5. 创建与版本严格一致且从未发布过的 tag，例如 `v0.2.1`；
6. 等待 Release workflow 完成；
7. 在另一台或清理过隔离属性的 Mac 上下载 DMG；
8. 抽查 Gatekeeper、启动、引擎页、一个图片和一个 PDF；
9. 对照 `SHA256SUMS`；
10. 再宣布公开版本可用。
