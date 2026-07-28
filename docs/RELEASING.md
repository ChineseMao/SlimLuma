# SlimLuma 发布流程

正式发行物必须同时满足：Universal 架构、完整本地化、Developer ID、Hardened
Runtime、安全时间戳、Apple 公证、staple、Gatekeeper 验收和发布后 SHA-256。
本地测试通过或 ad-hoc 签名不等于可公开发行。

## GitHub Secrets

仓库的 `release.yml` 使用以下 Actions secrets：

- `DEVELOPER_ID_CERTIFICATE_P12_BASE64`
- `DEVELOPER_ID_CERTIFICATE_PASSWORD`
- `RELEASE_KEYCHAIN_PASSWORD`
- `APPLE_API_PRIVATE_KEY`
- `APPLE_API_KEY_ID`
- `APPLE_API_ISSUER_ID`

私钥、P12 密码和 API key 不进入源码、日志、预设或发布附件。

## 本地预检

```bash
swift test
node scripts/sync-system-localizations.mjs --check
node scripts/generate-github-readmes.mjs --check
SLIMLUMA_CODE_SIGN_IDENTITY="<Developer ID SHA-1>" scripts/package-app.sh
```

签名构建会启用 Hardened Runtime 和安全时间戳，并拒绝
`com.apple.security.get-task-allow`。若 Keychain 中已保存公证凭据：

```bash
export SLIMLUMA_NOTARY_KEYCHAIN_PROFILE="<profile>"
scripts/notarize-release.sh dist/SlimLuma.app
scripts/notarize-release.sh dist/slimluma
scripts/create-release-artifacts.sh
scripts/notarize-release.sh dist/SlimLuma-<version>-macOS-universal.dmg
scripts/create-release-artifacts.sh --checksums-only
```

独立 CLI 没有可 staple 的 app / pkg / dmg 容器，`spctl --type execute` 也可能把有效
签名的裸命令行工具报告为“does not seem to be an app”。CLI 的门禁是提交归档获得
Apple `Accepted`，再对原始二进制执行严格 `codesign` 验证；app 和 DMG 仍必须
staple、stapler validate 和 Gatekeeper 通过。

## 0.2.0 本地发行证据

2026-07-28 最终候选：

- app 公证：`[redacted-notary-submission-id]`
- CLI 公证：`[redacted-notary-submission-id]`
- DMG 公证：`[redacted-notary-submission-id]`
- app 与 DMG：stapler validate 和 Gatekeeper accepted
- CLI：Apple Accepted、严格 codesign 通过
- Universal：`x86_64 arm64`
- `SHA256SUMS`：三项均通过 `shasum -a 256 -c`

本地证据不等于 GitHub Release 已公开；只有明确创建 tag 并完成远端 workflow 与
下载抽查后才能更新为公开状态。

## 自动发行

1. 更新 `Support/Info.plist` 中版本和 build。
2. 更新 `CHANGELOG.md` 和 `docs/releases/v<version>.md`；当前 release notes
   提供 20 个 GitHub 语言入口。
3. 确认 `main` 的 CI 全绿。
4. 创建与版本完全一致的 tag，例如 `v0.2.0`。
5. Release workflow 导入临时 keychain，构建、签名、公证并发布 ZIP、DMG、CLI
   与 `SHA256SUMS`。
6. 同一 tag 的发行任务不会并发执行；上传前会再次校验 20 份 GitHub README、
   本地化资源、测试、脚本语法、Universal 架构和三项 SHA-256。
7. 工作流无论成功或失败都会删除临时 keychain、P12 副本和 API 私钥临时文件。

发布后的 GitHub Release 和可下载附件仍需人工抽查；workflow 成功不替代产品页、
许可证与升级说明的最终审核。
