# Feedback and authorized contributions / 反馈与授权贡献

SlimLuma is source-visible proprietary software. Issues, reproducible bug
reports, security reports, and translation feedback are welcome. Code pull
requests are accepted only after prior written authorization from
SlimLuma copyright holders and completion of any contributor
agreement requested by the publisher.

SlimLuma 是源码公开可审阅的专有软件。欢迎提交 Issue、可复现故障、安全报告和翻译
反馈。代码 Pull Request 仅在事先获得
`SlimLuma copyright holders` 书面授权并按要求完成贡献协议后接收。

Submitting an issue, suggestion, or code does not grant any license to use the
SlimLuma source code. Do not submit third-party code unless you are authorized
to do so and have disclosed its exact license and provenance.

提交 Issue、建议或代码不会授予他人使用 SlimLuma 源码的许可。请勿提交无权提供的
第三方代码；经授权提交时必须明确其来源和完整许可。

## Authorized code changes / 已授权代码变更

If the publisher has authorized a code contribution, preserve SlimLuma's
local-first, non-destructive compression model and run:

如发布主体已经书面授权代码贡献，应保持“本地优先、不覆盖原件、结果必须验证”原则，
并运行：

```bash
swift test
node scripts/sync-system-localizations.mjs --check
node scripts/generate-github-readmes.mjs --check
node scripts/validate-github-localizations.mjs
```

When changing compression behavior, add a synthetic or redistributable fixture
and verify the produced file, not only the command arguments. PDF changes should
check pages and relevant outlines, links, forms, signatures, encryption, text,
and linearization. Video changes should check duration and semantic tracks.

修改压缩行为时，请加入可再分发的合成样本并验证真实输出，而不只断言命令参数。PDF
应检查页数及相关书签、链接、表单、签名、加密、文本和线性化；视频应检查时长和语义
轨道。

When adding user-visible copy:

1. update the `zh-Hans` source table;
2. run `node scripts/generate-localizations.mjs`;
3. review protected technical terms and placeholders;
4. run the localization and GitHub README generators;
5. inspect RTL if layout or control order changed.

新增可见文案时，请同步源语言、20 个 locale、系统本地化和 GitHub README；布局变化
必须检查 RTL。

GitHub uses English `README.md` as the default international entry point,
`README.zh-CN.md` as the complete Simplified Chinese mirror, and 20 generated
visitor pages under `docs/readme/`. Release notes use the same locale manifest
and live under `docs/releases/v<version>/`. Do not hand-edit generated files;
update the source localization table, the version's `.i18n.json`, or the
generator instead.

GitHub 默认使用英文 `README.md`，完整简体中文镜像为 `README.zh-CN.md`，其余访客
入口位于 `docs/readme/`。版本说明与它们共用 locale 清单，并生成到
`docs/releases/v<version>/`。请勿直接修改生成文件；应更新源语言表、对应版本的
`.i18n.json` 或生成器。

## Authorized pull request / 已授权 Pull Request

Keep one user-visible objective per pull request. Describe the outcome, risk,
real-file verification, localization impact, and release impact. Do not commit
media containing private user data, Developer ID certificates, notarization
keys, passwords, or generated release artifacts.

每个 PR 聚焦一个用户可见目标，说明结果、风险、真实文件验证、国际化和发布影响。请勿
提交用户私密媒体、Developer ID 证书、公证密钥、密码或生成的发行物。

Code submissions without the required written contributor agreement will not
be reviewed or merged. The publisher will provide the applicable agreement as
part of the authorization process.

未完成所需书面贡献协议的代码不会进入评审或合并。发布主体会在授权流程中提供对应
协议。
