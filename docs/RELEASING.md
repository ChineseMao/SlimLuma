# SlimLuma 发布流程

正式发行物必须同时满足：Universal 架构、完整本地化、Developer ID、Hardened
Runtime、安全时间戳、Apple 公证、staple、Gatekeeper 验收和发布后 SHA-256。
本地测试通过或 ad-hoc 签名不等于可公开发行。

每一层权限、证书、签名、公证与验证分别解决什么问题，见
[发布信任链（中文）](RELEASE_TRUST_CHAIN.zh-Hans.md) /
[Release trust chain (English)](RELEASE_TRUST_CHAIN.md)。

长期发布主体固定为
`Developer ID Application: private release identity`，
Apple Developer Team ID 为 `PRIVATE_TEAM_ID`。发布门禁会精确核对这两个值；证书轮换
可以改变指纹与有效期，但不能静默改变法律主体或 Team ID。完整声明见
[PUBLISHER.md](../PUBLISHER.md)。

## GitHub Secrets

仓库的 `release.yml` 使用以下 Actions secrets：

- `DEVELOPER_ID_CERTIFICATE_P12_BASE64`
- `DEVELOPER_ID_CERTIFICATE_PASSWORD`
- `RELEASE_KEYCHAIN_PASSWORD`
- `APPLE_API_PRIVATE_KEY`
- `APPLE_API_KEY_ID`
- `APPLE_API_ISSUER_ID`

只有仓库变量 `SLIMLUMA_AUTOMATED_RELEASE` 明确设置为 `true`，并从受保护的
`main` 手工触发 Release workflow、输入已签名 tag 时，才会运行自动签名、公证和
发布 job。工作流先使用 `main` 中固定的公开签名人列表验证 tag，再确认 tag 提交
已经合并到触发工作流的固定 `main` 提交，并在构建和 publish 前确认远端 live
`main` 仍是同一提交，最后才会 checkout 和构建 tag。旧 workflow run 重跑或
`main` 已变化时会直接拒绝。未配置变量时 job 会安全跳过，供下面的本机手工发行
流程使用；这样不会在 secrets 缺失时产生一个必然失败、又可能与手工 Release 竞态
的工作流。

私钥、P12 密码和 API key 不进入源码、日志、预设或发布附件。

## 本地预检

```bash
swift test
node scripts/sync-system-localizations.mjs --check
node scripts/generate-github-readmes.mjs --check
node scripts/validate-github-localizations.mjs
SLIMLUMA_CODE_SIGN_IDENTITY="<Developer ID SHA-1>" scripts/package-app.sh
```

签名构建会启用 Hardened Runtime 和安全时间戳，精确核对公司 Developer ID 与
Team ID，并拒绝 `com.apple.security.get-task-allow`。若 Keychain 中已保存
公证凭据：

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

## 0.2.0 公开发行证据

2026-07-28 最终候选：

- app、CLI 与 DMG 均由 Apple 公证服务返回 `Accepted`；具体 submission ID
  属于不必要的运营元数据，不在公开仓库长期保存；
- app 与 DMG：stapler validate 和 Gatekeeper accepted
- CLI：Apple Accepted、严格 codesign 通过
- Universal：`x86_64 arm64`
- `SHA256SUMS`：三项均通过 `shasum -a 256 -c`
- GitHub 仓库：<https://github.com/ChineseMao/SlimLuma>，Public
- GitHub Release：<https://github.com/ChineseMao/SlimLuma/releases/tag/v0.2.0>
- 匿名访问：仓库和 Release 均返回 HTTP 200
- 附件抽查：四个附件均可匿名下载；三项发行物哈希一致
- 下载后 DMG：stapler validate 通过，Gatekeeper 为 `Notarized Developer ID`
- Developer ID：
  `SlimLuma copyright holders (PRIVATE_TEAM_ID)`

`v0.2.0` 已于 2026-07-28 完成公开发布与下载后抽查。本节同时保留本地签名、公证
证据，避免把源码测试、Apple 验收和 GitHub 公开发行混为同一个状态。

## 自动发行

1. 更新 `Support/Info.plist` 中版本和 build。
2. 更新 `CHANGELOG.md`、`docs/releases/release-state.json` 中的
   `generatedReleaseNotesVersion` 和 `docs/releases/v<version>.i18n.json`，
   运行生成器创建 `docs/releases/v<version>.md` 及 20 份版本说明。
3. 确认 `main` 的 CI 全绿。
4. 从已通过 CI 的 `main` 提交创建与版本完全一致、且从未发布过的 signed tag，
   例如 `v0.2.1`。
5. 从 `main` 手工触发 Release workflow 并输入该 tag。工作流以 `main` 的 signer
   列表验证签名、拒绝未合并到 `main` 的 tag，再导入临时 keychain，构建、签名、
   公证并发布 ZIP、DMG、CLI 与 `SHA256SUMS`：

   ```bash
   gh workflow run Release --ref main -f tag=v0.2.1
   ```
6. 同一 tag 的发行任务不会并发执行；上传前会再次校验英文默认 README、完整中文
   镜像、20 份 GitHub README、20 份版本说明、直接下载链接、本地化资源、相对链接、
   测试、脚本语法、Universal 架构和三项 SHA-256。
7. App Resources、ZIP、DMG 根目录和 CLI 包必须携带适用的项目许可、第三方声明
   与 Swift Argument Parser 完整许可证；当前开发版本不得回退为 MIT 或开源口径。
8. 工作流无论成功或失败都会删除临时 keychain、P12 副本和 API 私钥临时文件。
9. 工作流会在构建前查询 GitHub；同名 Release 已存在时立即失败，绝不使用
   `--clobber` 覆盖历史附件或版本说明。
10. 新版本公开并完成下载后抽查后，把 `latestPublishedVersion` 更新到新版本，同时
    把 `Support/Info.plist` 推进到下一开发版本，再重新生成产品页。产品页的下载
    版本因此只会指向已实际公开的安装包，不会提前产生 404。

发布后的 GitHub Release 和可下载附件仍需人工抽查；workflow 成功不替代产品页、
许可证与升级说明的最终审核。

## 本机手工发行

当仓库没有配置上述 Actions secrets 时，使用已授权的本机 Keychain 完成完整发行。
正式 tag 必须指向已经合并、CI 成功的 `main` 提交；不得从 dirty worktree 或未合并
分支打 tag。

```bash
version="0.2.1"
export SLIMLUMA_CODE_SIGN_IDENTITY="<Developer ID SHA-1>"
export SLIMLUMA_NOTARY_KEYCHAIN_PROFILE="<notarytool profile>"

scripts/package-app.sh
scripts/notarize-release.sh dist/SlimLuma.app
scripts/notarize-release.sh dist/slimluma
scripts/create-release-artifacts.sh
scripts/notarize-release.sh \
  "dist/SlimLuma-$version-macOS-universal.dmg"
scripts/create-release-artifacts.sh --checksums-only
(cd dist && shasum -a 256 -c SHA256SUMS)
```

确认 App、CLI、DMG、ZIP 内的项目许可和第三方声明通过脚本门禁后，创建 signed
tag，并在推送前执行 `git verify-tag "v$version"`。推送 tag 本身不会自动发布；
只有从受保护的 `main` 显式运行 Release workflow 才会进入自动发行链路。
手工创建 Release 时必须使用精确文件名，禁止使用可能匹配旧版本的通配符，也禁止
`--clobber`：

```bash
git tag -s "v$version" -m "SlimLuma $version"
git push origin "v$version"
gh release create "v$version" \
  "dist/SlimLuma-$version-macOS-universal.dmg" \
  "dist/SlimLuma-$version-macOS-universal.zip" \
  "dist/slimluma-$version-macOS-universal.tar.gz" \
  dist/SHA256SUMS \
  --verify-tag \
  --notes-file "docs/releases/v$version.md" \
  --title "SlimLuma $version"
```

最后从匿名下载 URL 重新下载全部附件，执行 SHA-256、DMG/App stapler、Gatekeeper、
版本、架构、签名主体和 Team ID 复验。只有全部通过后，才推进
`latestPublishedVersion` 并让产品页指向新版本。

## 许可版本边界

`v0.2.0` 的源码 tag 与 CLI 包已经按 MIT License 发行，既有授权不会被追溯撤销。
当前 `main` 和后续版本使用各自提交或 tag 中的 `LICENSE`；创建新 tag 前必须确认
版本说明、20 份本地化说明和所有发行包都指向同一个许可状态。不得覆盖 `v0.2.0`
tag 或重打同版本产物来制造追溯性许可变更。
