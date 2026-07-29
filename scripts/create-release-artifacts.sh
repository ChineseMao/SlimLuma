#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$PROJECT_DIR/dist"
APP_DIR="$DIST_DIR/SlimLuma.app"
CLI_PATH="$DIST_DIR/slimluma"
CHECKSUMS_ONLY=false
source "$PROJECT_DIR/scripts/release-identity.sh"

if [[ "${1:-}" == "--checksums-only" ]]; then
    CHECKSUMS_ONLY=true
fi

VERSION="$(
    /usr/libexec/PlistBuddy \
        -c 'Print :CFBundleShortVersionString' \
        "$APP_DIR/Contents/Info.plist"
)"
if [[ ! "$VERSION" =~ '^[0-9]+([.][0-9]+){1,3}([+-][A-Za-z0-9.-]+)?$' ]]; then
    echo "Invalid release version: $VERSION" >&2
    exit 2
fi
if [[ "$VERSION" == "0.2.0" ]] \
    && [[ "$(sed -n '1p' "$PROJECT_DIR/LICENSE")" != "MIT License" ]]; then
    echo "Refusing to rebuild historical MIT release 0.2.0 with different license terms." >&2
    exit 2
fi

APP_ZIP="$DIST_DIR/SlimLuma-$VERSION-macOS-universal.zip"
CLI_ARCHIVE="$DIST_DIR/slimluma-$VERSION-macOS-universal.tar.gz"
DMG_PATH="$DIST_DIR/SlimLuma-$VERSION-macOS-universal.dmg"
CHECKSUMS_PATH="$DIST_DIR/SHA256SUMS"

verify_release_identity() {
    local target="$1"
    local require_runtime="$2"
    slimluma_verify_developer_id_signature "$target" "$require_runtime"
}

write_checksums() {
    local artifacts=(
        "$APP_ZIP"
        "$CLI_ARCHIVE"
        "$DMG_PATH"
    )
    for artifact in "${artifacts[@]}"; do
        [[ -f "$artifact" ]]
    done
    (
        cd "$DIST_DIR"
        shasum -a 256 \
            "$(basename "$APP_ZIP")" \
            "$(basename "$CLI_ARCHIVE")" \
            "$(basename "$DMG_PATH")" \
            > "$CHECKSUMS_PATH"
    )
}

slimluma_require_private_identity_config

if $CHECKSUMS_ONLY; then
    codesign --verify --strict "$DMG_PATH"
    verify_release_identity "$DMG_PATH" false
    xcrun stapler validate "$DMG_PATH"
    write_checksums
    echo "$CHECKSUMS_PATH"
    exit 0
fi

[[ -d "$APP_DIR" ]]
[[ -x "$CLI_PATH" ]]
if [[ -z "${SLIMLUMA_CODE_SIGN_IDENTITY:-}" \
    || "$SLIMLUMA_CODE_SIGN_IDENTITY" == "-" ]]; then
    echo "Release artifacts require the long-term Developer ID signing identity." >&2
    exit 2
fi
/usr/bin/xattr -cr "$APP_DIR"
/usr/bin/xattr -c "$CLI_PATH"
codesign --verify --deep --strict "$APP_DIR"
codesign --verify --strict "$CLI_PATH"
"$PROJECT_DIR/scripts/verify-release-privacy.sh" \
    "$APP_DIR" \
    "$CLI_PATH"

verify_release_identity "$APP_DIR" true
verify_release_identity "$CLI_PATH" true

APP_RESOURCES="$APP_DIR/Contents/Resources"
[[ -f "$APP_RESOURCES/LICENSE" ]]
[[ -f "$APP_RESOURCES/THIRD_PARTY_NOTICES.md" ]]
[[ -f "$APP_RESOURCES/ThirdPartyLicenses/SwiftArgumentParser-LICENSE.txt" ]]
cmp -s "$PROJECT_DIR/LICENSE" "$APP_RESOURCES/LICENSE"
cmp -s \
    "$PROJECT_DIR/THIRD_PARTY_NOTICES.md" \
    "$APP_RESOURCES/THIRD_PARTY_NOTICES.md"
xcrun stapler validate "$APP_DIR"

TEMP_DIR="$(mktemp -d "$DIST_DIR/.release-stage.XXXXXX")"
DMG_VERIFY_MOUNT=""
cleanup() {
    local exit_status=$?
    if [[ -n "$DMG_VERIFY_MOUNT" ]] \
        && mount | grep -F "on $DMG_VERIFY_MOUNT " >/dev/null; then
        hdiutil detach "$DMG_VERIFY_MOUNT" >/dev/null 2>&1 || true
    fi
    rm -rf "$TEMP_DIR"
    return "$exit_status"
}
trap cleanup EXIT

CLI_STAGE="$TEMP_DIR/slimluma-$VERSION"
mkdir -p "$CLI_STAGE"
cp "$CLI_PATH" "$CLI_STAGE/slimluma"
cp "$PROJECT_DIR/LICENSE" "$CLI_STAGE/LICENSE"
cp "$PROJECT_DIR/THIRD_PARTY_NOTICES.md" \
    "$CLI_STAGE/THIRD_PARTY_NOTICES.md"
mkdir -p "$CLI_STAGE/ThirdPartyLicenses"
cp \
    "$APP_DIR/Contents/Resources/ThirdPartyLicenses/SwiftArgumentParser-LICENSE.txt" \
    "$CLI_STAGE/ThirdPartyLicenses/SwiftArgumentParser-LICENSE.txt"

DMG_STAGE="$TEMP_DIR/dmg"
mkdir -p "$DMG_STAGE"
cp -R "$APP_DIR" "$DMG_STAGE/SlimLuma.app"
cp "$PROJECT_DIR/LICENSE" "$DMG_STAGE/LICENSE"
cp "$PROJECT_DIR/THIRD_PARTY_NOTICES.md" \
    "$DMG_STAGE/THIRD_PARTY_NOTICES.md"
cp -R "$APP_DIR/Contents/Resources/ThirdPartyLicenses" \
    "$DMG_STAGE/ThirdPartyLicenses"
ln -s /Applications "$DMG_STAGE/Applications"

/usr/bin/xattr -cr "$TEMP_DIR"
"$PROJECT_DIR/scripts/verify-release-privacy.sh" \
    "$CLI_STAGE" \
    "$DMG_STAGE"

rm -f "$APP_ZIP" "$CLI_ARCHIVE" "$DMG_PATH" "$CHECKSUMS_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$APP_ZIP"
tar \
    --uid 0 \
    --gid 0 \
    --uname root \
    --gname wheel \
    -C "$TEMP_DIR" \
    -czf "$CLI_ARCHIVE" \
    "slimluma-$VERSION"
hdiutil create \
    -volname "SlimLuma $VERSION" \
    -srcfolder "$DMG_STAGE" \
    -format UDZO \
    -ov \
    "$DMG_PATH" >/dev/null

ZIP_ENTRIES="$TEMP_DIR/app-zip-entries.txt"
CLI_ENTRIES="$TEMP_DIR/cli-archive-entries.txt"
unzip -Z1 "$APP_ZIP" > "$ZIP_ENTRIES"
tar -tzf "$CLI_ARCHIVE" > "$CLI_ENTRIES"
if grep -E '(^|/)__MACOSX(/|$)' "$ZIP_ENTRIES" >/dev/null; then
    echo "App archive contains unexpected extended-metadata entries." >&2
    exit 1
fi
if ! tar -tvzf "$CLI_ARCHIVE" \
    | awk 'NF > 4 && ($3 != "root" || $4 != "wheel") { exit 1 }'; then
    echo "CLI archive contains local owner or group metadata." >&2
    exit 1
fi
grep -Fx 'SlimLuma.app/Contents/Resources/LICENSE' \
    "$ZIP_ENTRIES" >/dev/null
grep -Fx 'SlimLuma.app/Contents/Resources/THIRD_PARTY_NOTICES.md' \
    "$ZIP_ENTRIES" >/dev/null
grep -Fx \
    'SlimLuma.app/Contents/Resources/ThirdPartyLicenses/SwiftArgumentParser-LICENSE.txt' \
    "$ZIP_ENTRIES" >/dev/null
grep -Fx "slimluma-$VERSION/LICENSE" \
    "$CLI_ENTRIES" >/dev/null
grep -Fx "slimluma-$VERSION/THIRD_PARTY_NOTICES.md" \
    "$CLI_ENTRIES" >/dev/null
grep -Fx \
    "slimluma-$VERSION/ThirdPartyLicenses/SwiftArgumentParser-LICENSE.txt" \
    "$CLI_ENTRIES" >/dev/null

unzip -p "$APP_ZIP" \
    'SlimLuma.app/Contents/Resources/LICENSE' \
    > "$TEMP_DIR/zip-LICENSE"
unzip -p "$APP_ZIP" \
    'SlimLuma.app/Contents/Resources/THIRD_PARTY_NOTICES.md' \
    > "$TEMP_DIR/zip-THIRD_PARTY_NOTICES.md"
unzip -p "$APP_ZIP" \
    'SlimLuma.app/Contents/Resources/ThirdPartyLicenses/SwiftArgumentParser-LICENSE.txt' \
    > "$TEMP_DIR/zip-SwiftArgumentParser-LICENSE.txt"
cmp -s "$PROJECT_DIR/LICENSE" "$TEMP_DIR/zip-LICENSE"
cmp -s \
    "$PROJECT_DIR/THIRD_PARTY_NOTICES.md" \
    "$TEMP_DIR/zip-THIRD_PARTY_NOTICES.md"
cmp -s \
    "$APP_RESOURCES/ThirdPartyLicenses/SwiftArgumentParser-LICENSE.txt" \
    "$TEMP_DIR/zip-SwiftArgumentParser-LICENSE.txt"

tar -xOf "$CLI_ARCHIVE" \
    "slimluma-$VERSION/LICENSE" \
    > "$TEMP_DIR/cli-LICENSE"
tar -xOf "$CLI_ARCHIVE" \
    "slimluma-$VERSION/THIRD_PARTY_NOTICES.md" \
    > "$TEMP_DIR/cli-THIRD_PARTY_NOTICES.md"
tar -xOf "$CLI_ARCHIVE" \
    "slimluma-$VERSION/ThirdPartyLicenses/SwiftArgumentParser-LICENSE.txt" \
    > "$TEMP_DIR/cli-SwiftArgumentParser-LICENSE.txt"
cmp -s "$PROJECT_DIR/LICENSE" "$TEMP_DIR/cli-LICENSE"
cmp -s \
    "$PROJECT_DIR/THIRD_PARTY_NOTICES.md" \
    "$TEMP_DIR/cli-THIRD_PARTY_NOTICES.md"
cmp -s \
    "$APP_RESOURCES/ThirdPartyLicenses/SwiftArgumentParser-LICENSE.txt" \
    "$TEMP_DIR/cli-SwiftArgumentParser-LICENSE.txt"

DMG_VERIFY_MOUNT="$TEMP_DIR/dmg-verify"
mkdir -p "$DMG_VERIFY_MOUNT"
hdiutil attach \
    -nobrowse \
    -readonly \
    -mountpoint "$DMG_VERIFY_MOUNT" \
    "$DMG_PATH" >/dev/null
cmp -s "$PROJECT_DIR/LICENSE" "$DMG_VERIFY_MOUNT/LICENSE"
cmp -s \
    "$PROJECT_DIR/THIRD_PARTY_NOTICES.md" \
    "$DMG_VERIFY_MOUNT/THIRD_PARTY_NOTICES.md"
cmp -s \
    "$APP_DIR/Contents/Resources/ThirdPartyLicenses/SwiftArgumentParser-LICENSE.txt" \
    "$DMG_VERIFY_MOUNT/ThirdPartyLicenses/SwiftArgumentParser-LICENSE.txt"
cmp -s \
    "$PROJECT_DIR/LICENSE" \
    "$DMG_VERIFY_MOUNT/SlimLuma.app/Contents/Resources/LICENSE"
cmp -s \
    "$PROJECT_DIR/THIRD_PARTY_NOTICES.md" \
    "$DMG_VERIFY_MOUNT/SlimLuma.app/Contents/Resources/THIRD_PARTY_NOTICES.md"
cmp -s \
    "$APP_RESOURCES/ThirdPartyLicenses/SwiftArgumentParser-LICENSE.txt" \
    "$DMG_VERIFY_MOUNT/SlimLuma.app/Contents/Resources/ThirdPartyLicenses/SwiftArgumentParser-LICENSE.txt"
hdiutil detach "$DMG_VERIFY_MOUNT" >/dev/null
DMG_VERIFY_MOUNT=""

codesign \
    --force \
    --timestamp \
    --sign "$SLIMLUMA_CODE_SIGN_IDENTITY" \
    "$DMG_PATH"
codesign --verify --strict "$DMG_PATH"
verify_release_identity "$DMG_PATH" false

write_checksums
printf '%s\n' "$APP_ZIP" "$CLI_ARCHIVE" "$DMG_PATH" "$CHECKSUMS_PATH"
