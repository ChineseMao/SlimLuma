# SlimLuma release trust chain

A production release is a chain of independent checks. Each layer answers a
different question: who published it, whether the bytes changed, whether Apple
scanned those exact bytes, whether an offline Mac can verify them, and whether
the public GitHub download is the artifact that passed all gates.

| Layer | Why it is required | Without it | What it provides |
| --- | --- | --- | --- |
| Keychain private-key access | `codesign` needs the publisher's private key. Access is limited to signing tools; the key never belongs in source or logs. | A public certificate alone cannot sign, while exporting the key broadly increases impersonation risk. | Publisher proof while the key remains protected by macOS Keychain. |
| Developer ID Application certificate | Apple binds the public key to the legal signer and team identifier. SlimLuma checks both against a private release policy. | Ad-hoc or unsigned builds have no trusted publisher identity and Gatekeeper may block them. | A user-verifiable signer identity and an Apple-revocable certificate. |
| Hardened Runtime | Notarization expects runtime protections against common injection and debugging bypasses. | Notarization may reject the app and runtime protection is weaker. | Extends integrity controls into execution. |
| Secure timestamp | Apple's timestamp proves signing occurred while the certificate was valid. | Long-term validation can fail after certificate expiry. | Previously released builds remain verifiable after normal certificate expiry. |
| Strict signature and entitlement checks | Verifies nested code and rejects development-only entitlements such as `get-task-allow`. | A command may have signed an earlier state while later packaging broke it. | Detects tampering, missing nested signatures, and debug privileges before upload. |
| Universal architecture check | `lipo` proves both `arm64` and `x86_64` exist. | One class of Macs may fail to run the download. | One native artifact for Apple Silicon and Intel Macs. |
| Notary authentication | A Keychain profile or App Store Connect credential proves who may submit to Apple. | Submission and status lookup cannot run; exposing credentials creates account risk. | Authenticated upload without embedding a credential in the product. SlimLuma reuses a local Keychain profile and does not require a repository `.p8`. |
| Apple notarization | Apple scans the exact signed bytes and checks signing policy. | A Developer ID signature identifies a publisher but does not prove Apple scanned the build. | An `Accepted` record for each App, CLI archive, and DMG; one result does not cover the others. |
| Stapling | Attaches Apple's ticket to the App or DMG. | Online lookup may work, but offline or restricted Macs can fail verification. | Offline notarization verification. A bare CLI cannot carry a stapled ticket. |
| Gatekeeper assessment | `spctl` applies the policy a user's Mac will apply to the final container. | A notarized item can still be packaged incorrectly. | Evidence that the distributed App and DMG pass the real launch gate. |
| SHA-256 | Publishes a reproducible fingerprint of every download. | Corruption, stale caches, or replacement artifacts are harder to detect independently. | Download integrity; it complements rather than replaces code signing. |
| Anonymous re-download | Tests the public Release as an ordinary visitor. | A green build can still leave a private, missing, stale, or wrongly named asset. | Proof that public links, bytes, version, signature, notarization, and checksums agree. |
| SSH-signed Git commit and tag | The publisher signs commits and tags with a local SSH private key; the repository stores only the public signing key. | An unsigned or unknown-signer tag is rejected, while uploading the private key would permit impersonation. | Binds source, version tag, and authorized publisher without exposing the Developer ID key. |
| Least-privilege GitHub permissions | Build/sign/notary jobs use `contents: read`; only the publish job, which never receives Apple keys, gets temporary `contents: write`. | No write permission cannot create a Release, while broad write permission lets a compromised build step modify repository state or assets. | Separates Apple credentials from GitHub mutation and limits every job to its responsibility. |
| Protected release environment | Automated signing secrets are available only inside a protected release event and can require human approval. | Missing credentials cannot sign or notarize; ordinary source, PR jobs, or logs must never receive them. | Scopes P12, passwords, and Apple API credentials. Local releases instead reuse the Keychain profile. |
| Protected main and release tags | Reviewed main cannot be force-pushed and release tags cannot be updated or deleted. | Validated source or tags can otherwise change between verification and upload. | Keeps CI, signature, notarization, and the public Release bound to the same commit and bytes. |
| Signed-tag verification from protected main | The workflow loads its fixed signer list from protected `main` and requires the tagged commit to be merged into `main`. | A tag-controlled signer list can replace both code and trust root, while a signed side-branch can bypass review and CI. | Binds signer identity, reviewed source, and the exact released tag into one auditable chain. |

The final signature necessarily lets macOS display the legal signer, team
identifier, certificate chain, bundle ID, and version. Checksums, licenses, and
the release-signing public key also remain user-verifiable. To reduce
unnecessary indexing, repository text does not duplicate the legal signer or
team identifier; exact matching values live only in private release
configuration.

Private keys, P12 files and passwords, App Store Connect P8 keys, Apple
app-specific passwords, Keychain passwords, GitHub tokens, submission
identifiers, and personal paths must never enter Git, logs, or release
attachments.
