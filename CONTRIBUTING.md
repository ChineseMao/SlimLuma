# Contributing / 参与贡献

SlimLuma welcomes focused fixes and features that preserve its local-first,
non-destructive compression model.

SlimLuma 欢迎保持“本地优先、不覆盖原件、结果必须验证”原则的修复与功能。

## Before a pull request / 提交前

```bash
swift test
node scripts/sync-system-localizations.mjs --check
node scripts/generate-github-readmes.mjs --check
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

## Pull request / Pull Request

Keep one user-visible objective per pull request. Describe the outcome, risk,
real-file verification, localization impact, and release impact. Do not commit
media containing private user data, Developer ID certificates, notarization
keys, passwords, or generated release artifacts.

每个 PR 聚焦一个用户可见目标，说明结果、风险、真实文件验证、国际化和发布影响。请勿
提交用户私密媒体、Developer ID 证书、公证密钥、密码或生成的发行物。
