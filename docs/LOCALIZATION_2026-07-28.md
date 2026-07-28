# SlimLuma 国际化范围与验证（2026-07-28）

## 结论

SlimLuma 的功能性国际化已经完整接入产品与发布链路：

- 18 个语言层、20 个 locale；
- 每个 locale 903 个主文案 key；
- 9 个 CLDR 复数文案；
- Finder Services、Info.plist、App Shortcuts、辅助功能、引擎恢复、完整性错误和
  GitHub README 使用同一 locale 集；
- 阿拉伯语、乌尔都语和 Shahmukhi 西旁遮普语采用 RTL；
- 资源、运行时解析、占位符、复数、书写系统、系统入口和 GitHub 文档均有自动门禁；
- 阿拉伯语和简体中文已经在最终签名 app 上做实机窗口复验。

这里的“完整”指技术覆盖和产品链路完整，不代表 20 种 locale 都已经完成母语编辑、
营销语气校对和逐页面人工 GUI 验收。

## 覆盖口径

“人口超过一亿的语言人群”没有唯一统计口径。SlimLuma 使用以下规则：

1. 主要参考母语与第二语言使用者总量；
2. 将语言映射为 macOS 可稳定选择的产品 locale；
3. 中文、西班牙语和葡萄牙语按常用书写或地区变体拆分；
4. 对不同口径处于一亿边界附近的斯瓦希里语、西旁遮普语和泰卢固语采取包容策略；
5. 现代标准阿拉伯语同时服务标准书面阿拉伯语与主要阿拉伯语人群；
6. 西旁遮普语使用 Shahmukhi（`pa-Arab`），不错误替换为 Gurmukhi。

| 语言层 | locale |
| --- | --- |
| 英语 | `en` |
| 中文 | `zh-Hans`、`zh-Hant` |
| 印地语 | `hi` |
| 西班牙语 | `es-419`、`es-ES` |
| 阿拉伯语 | `ar` |
| 法语 | `fr` |
| 孟加拉语 | `bn` |
| 葡萄牙语 | `pt-BR`、`pt-PT` |
| 印度尼西亚语 | `id` |
| 乌尔都语 | `ur` |
| 俄语 | `ru` |
| 德语 | `de` |
| 日语 | `ja` |
| 斯瓦希里语 | `sw` |
| 西旁遮普语（Shahmukhi） | `pa-Arab` |
| 泰卢固语 | `te` |
| 尼日利亚皮钦语 | `pcm` |

参考：

- [Ethnologue 200（2026）](https://shop.ethnologue.com/products/2026-ethnologue-200)
- [Unicode CLDR 复数规则](https://www.unicode.org/cldr/charts/latest/supplemental/language_plural_rules.html)
- [Apple Services 本地化](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/SysServices/Articles/properties.html)

## 产品表面

| 表面 | 覆盖 |
| --- | --- |
| SwiftUI 界面与模型文案 | 20 locale |
| 图片 / 动画 / 视频 / PDF 完整性错误 | 20 locale |
| 引擎检测、安装、取消、失败和恢复 | 20 locale |
| 可访问性标签、值、提示和步骤说明 | 20 locale |
| Finder 文档类型和 Services 菜单 | 20 locale |
| App Shortcuts 标题、短语和参数 | 20 locale |
| Info.plist 显示文案 | 20 locale |
| GitHub 安装 / 功能 / CLI / 隐私 README | 20 locale |
| PR / Issue / 安全 / 贡献入口 | 中英双语 |

文件名、路径、用户自定义预设名、外部引擎原始日志和 CLI 机器 JSON 不翻译。这是
数据边界，不是漏翻：翻译它们会改变用户数据、破坏脚本或掩盖诊断证据。

## 运行时实现

- `zh-Hans` 是源语言；
- `LocalizationKeys.json` 冻结 903 个已纳入产品的主 key；
- 普通 SwiftUI 字面量走系统本地化；
- 模型、动态错误、原理说明和辅助功能通过统一 `L10n` 入口；
- 动态参数可重排，计数按 CLDR cardinal 类别进入 `.stringsdict`；
- 日期、字节、百分比和列表使用 Foundation 本地化格式器；
- 嵌套完整性错误先拆分稳定模板，再插回诊断数字与用户文件名；
- 业务逻辑使用枚举、稳定 ID 和 typed failure，不依赖中文显示文本；
- `Bundle.main.preferredLocalizations` 驱动 RTL，根 `NavigationSplitView` 保持原生
  AppKit 管理，RTL 环境只作用于侧栏和详情内容，避免分栏约束崩溃；
- `forward` 语义图标和原生 SwiftUI 布局随阅读方向自动镜像。

## 自动质量门禁

测试会拒绝：

- locale 缺少、多出或包含空 key；
- 残留中文或翻译生成器 token；
- 非英文 locale 只是英文占位副本；
- `printf`、动态模板或可重排参数丢失；
- 俄语、阿拉伯语等缺少所需 CLDR 复数类别；
- 阿拉伯、天城、孟加拉、西里尔、日文或泰卢固书写系统异常；
- `es-419` / `es-ES`、`pt-BR` / `pt-PT`、`zh-Hans` / `zh-Hant` 或
  `pa-Arab` 错误跨地区 / 书写系统回退；
- Finder、Info.plist 或 App Shortcuts 缺少任一 locale；
- App Shortcut 丢失 `${applicationName}`；
- 翻译后的取消、完整性失败或引擎恢复改变业务分支；
- 动态诊断丢失数字，或错误地翻译用户文件名；
- `ar`、`ur`、`pa-Arab` 没有进入 RTL，或 LTR locale 被误判为 RTL；
- GitHub 20 份语言 README 与生成器不一致。

本轮实际结果：

```text
LocalizationTests: 21 passed, 0 failed
Full suite:         104 tests, 1 expected skip, 0 failed
Packaged locales:   20
Source keys:        903 per locale
Plural keys:        9 per locale
GitHub READMEs:     20
```

唯一跳过项是需要显式传入本地大 PDF 的外部 fixture 测试；同一真实 PDF 已在独立
回归中运行并保留页数与书签。

## 实机 RTL 与 GUI 验证

最终签名 app 使用 `ar_SA` 启动后检查了：

1. 媒体类型从右侧“图片”开始；
2. 设置标签位于右侧，选择器、数值与菜单位于左侧；
3. 原理流程从右侧第 1 步走到左侧第 5 步；
4. 能力卡片从右向左保持图片、视频、PDF 的语义顺序；
5. 可访问性树仍按图片、视频、PDF 和步骤 1…5 的逻辑顺序提供；
6. 侧栏隐藏和恢复不会再次触发 AppKit 分栏约束崩溃；
7. 简体中文重新启动后，LTR 排列与可访问性树未回归。

简体中文主工作区还在真实系统暗色外观下复验了背景、系统材质、控件状态、分隔线、
说明文字和焦点层级；完成截图后已恢复用户原来的浅色系统外观。该检查不替代
20 locale × 全页面 × 全窗口尺寸的暗色矩阵。

截图：

- [阿拉伯语主界面](release-audit-2026-07-28/20-main-ar-rtl-final.png)
- [阿拉伯语原理流程](release-audit-2026-07-28/21-principles-ar-rtl-final.png)
- [简体中文主界面](release-audit-2026-07-28/22-main-zh-Hans-final.png)
- [简体中文暗色主界面](release-audit-2026-07-28/23-main-zh-Hans-dark-final.png)

## GitHub 国际化

`scripts/generate-github-readmes.mjs` 从产品资源生成 20 份 README，内容包括：

- 功能与实现原理；
- 图片 / 视频 / PDF、目标大小、队列和结果守门；
- 安装与一键补齐引擎；
- CLI 示例；
- 本地数据与隐私；
- 回到主仓库架构、许可证和发布文档的入口。

CI 会运行：

```bash
node scripts/sync-system-localizations.mjs --check
node scripts/generate-github-readmes.mjs --check
swift test --filter LocalizationTests
```

任何源语言变更如果没有同步系统资源或 GitHub README，提交都会失败。

## 尚需人工完成的语言质量

技术国际化已闭环，但正式向特定地区投放前仍建议：

1. 由当地母语编辑复核安全、许可、PDF 和视频术语；
2. 在系统真实“应用语言”设置下检查菜单栏、文件面板和系统弹窗；
3. 对德语、俄语、法语等长文本语言做最小窗口截断矩阵；
4. 用 VoiceOver 完整朗读一轮核心任务；
5. 对阿拉伯语、乌尔都语和 Shahmukhi 分别做母语阅读顺序审校；
6. 扩展真实暗色系统外观的全页面、长文本语言与小窗口检查矩阵；
7. 对发行页、截图、更新日志和支持文案做母语营销编辑。

这些属于语言编辑与市场 QA，不是资源缺失或业务逻辑未国际化。
