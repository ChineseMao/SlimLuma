# Publisher and release identity

SlimLuma's long-term official macOS publisher is:

> SlimLuma copyright holders

Apple release identity:

- Developer ID authority:
  `Developer ID Application: private release identity`
- Apple Developer Team ID: `PRIVATE_TEAM_ID`
- Distribution: Developer ID signed, Hardened Runtime enabled, Apple-notarized,
  stapled macOS releases distributed through GitHub Releases

The legal name above is intentionally preserved exactly, including
`TechnologyCo.`. Certificate fingerprints and expiration dates may change
during normal rotation; the legal entity and Team ID are the stable release
identity.

Developer ID identifies the entity that signs and publishes an official build;
it does not by itself transfer copyright from an author or contributor. Project
copyright ownership and any contributor assignments must remain supported by
the applicable written agreements.

## Release requirements

Every official macOS release must verify all of the following:

1. the app and CLI have Universal `arm64` and `x86_64` binaries;
2. the signing authority and Team ID exactly match the values above;
3. Hardened Runtime and a secure timestamp are present;
4. `com.apple.security.get-task-allow` is absent;
5. Apple notarization is `Accepted`;
6. the app and DMG have valid stapled tickets;
7. Gatekeeper accepts the app and DMG as `Notarized Developer ID`;
8. published archives match `SHA256SUMS`;
9. the app, DMG, ZIP, and CLI package carry the applicable project and
   third-party notices.

Private keys, certificate passwords, Keychain passwords, and App Store Connect
API keys are never committed to this repository.

## License boundary

Current development is source-visible proprietary software under
[LICENSE](LICENSE). SlimLuma 0.2.0 was previously released under the MIT
License; that earlier grant remains in effect for copies received under it.
