# Release verification and identity privacy

Official macOS builds are Developer ID Application signed, use Hardened
Runtime and a secure timestamp, and are released only after Apple notarization,
stapling, Gatekeeper, and checksum verification succeed.

The signing certificate embedded in a macOS release necessarily exposes its
legal signer and Apple team identifier to macOS. Those values are public trust
metadata, not credentials. To reduce unnecessary indexing and correlation, this
repository does not duplicate them in documentation, source constants, logs, or
release notes.

Release automation still pins the exact expected signing identity. The expected
certificate authority and team identifier are supplied through local
environment variables or protected GitHub Secrets:

- `SLIMLUMA_EXPECTED_DEVELOPER_ID_AUTHORITY`
- `SLIMLUMA_EXPECTED_TEAM_ID`

Their values must never be committed. A missing or mismatched private value
blocks release packaging.

## Release requirements

Every official macOS release must verify all of the following:

1. the app and CLI have Universal `arm64` and `x86_64` binaries;
2. the signing authority and team identifier match the private release policy;
3. Hardened Runtime and a secure timestamp are present;
4. `com.apple.security.get-task-allow` is absent;
5. Apple notarization is `Accepted`;
6. the app and DMG have valid stapled tickets;
7. Gatekeeper accepts the app and DMG as `Notarized Developer ID`;
8. published archives match `SHA256SUMS`;
9. the app, DMG, ZIP, and CLI package carry the applicable project and
   third-party notices.

Private keys, certificate files and passwords, Keychain passwords, App Store
Connect credentials, notarization submission identifiers, personal paths, and
GitHub tokens are never committed to this repository.

## License boundary

Current development is source-visible proprietary software under
[LICENSE](LICENSE). SlimLuma 0.2.0 was previously released under the MIT
License; that earlier grant remains in effect for copies received under it.
