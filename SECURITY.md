# Security Policy / 安全策略

## Supported version / 支持版本

Security fixes are provided for the latest published SlimLuma version.
安全修复面向最新公开版本。

## Reporting / 报告漏洞

Please do not include passwords, private documents, signing credentials, API
keys, or unredacted personal paths in a public issue.

请勿在公开 Issue 中上传密码、私密文档、签名凭据、API Key 或未脱敏的个人路径。

Use GitHub private vulnerability reporting when it is enabled for this
repository. Otherwise, open a minimal public issue asking the maintainer for a
private contact channel without disclosing exploit details.

如果仓库启用了 GitHub Private Vulnerability Reporting，请优先使用；否则只创建一个
不包含利用细节的最小公开 Issue，请维护者提供私下联系方式。

Include:

- affected SlimLuma and macOS versions;
- input type and engine path;
- reproducible steps with a synthetic or redacted fixture;
- actual and expected behavior;
- whether the issue can overwrite, expose, or corrupt user data.

建议提供：

- SlimLuma 与 macOS 版本；
- 输入类型和实际引擎路径；
- 使用合成或脱敏样本的复现步骤；
- 实际与预期行为；
- 是否可能覆盖、泄露或损坏用户数据。

## Data boundary / 数据边界

SlimLuma processes media locally. Opening license or Homebrew websites and
running Homebrew are explicit network actions. PDF passwords stay in queue
memory and permission-restricted temporary files and are not persisted to
history, presets, or logs.

SlimLuma 在本机处理媒体。打开许可 / Homebrew 网站及运行 Homebrew 属于明确的网络
动作。PDF 密码只驻留队列内存与权限受限的临时文件，不写入历史、预设或日志。
