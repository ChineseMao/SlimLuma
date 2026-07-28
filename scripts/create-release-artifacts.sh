#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$PROJECT_DIR/dist"
APP_DIR="$DIST_DIR/SlimLuma.app"
CLI_PATH="$DIST_DIR/slimluma"
CHECKSUMS_ONLY=false

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

APP_ZIP="$DIST_DIR/SlimLuma-$VERSION-macOS-universal.zip"
CLI_ARCHIVE="$DIST_DIR/slimluma-$VERSION-macOS-universal.tar.gz"
DMG_PATH="$DIST_DIR/SlimLuma-$VERSION-macOS-universal.dmg"
CHECKSUMS_PATH="$DIST_DIR/SHA256SUMS"

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

if $CHECKSUMS_ONLY; then
    write_checksums
    echo "$CHECKSUMS_PATH"
    exit 0
fi

[[ -d "$APP_DIR" ]]
[[ -x "$CLI_PATH" ]]
codesign --verify --deep --strict "$APP_DIR"
codesign --verify --strict "$CLI_PATH"
xcrun stapler validate "$APP_DIR"

TEMP_DIR="$(mktemp -d "$DIST_DIR/.release-stage.XXXXXX")"
cleanup() {
    local exit_status=$?
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

DMG_STAGE="$TEMP_DIR/dmg"
mkdir -p "$DMG_STAGE"
cp -R "$APP_DIR" "$DMG_STAGE/SlimLuma.app"
ln -s /Applications "$DMG_STAGE/Applications"

rm -f "$APP_ZIP" "$CLI_ARCHIVE" "$DMG_PATH" "$CHECKSUMS_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$APP_ZIP"
tar -C "$TEMP_DIR" -czf "$CLI_ARCHIVE" "slimluma-$VERSION"
hdiutil create \
    -volname "SlimLuma $VERSION" \
    -srcfolder "$DMG_STAGE" \
    -format UDZO \
    -ov \
    "$DMG_PATH" >/dev/null

if [[ -n "${SLIMLUMA_CODE_SIGN_IDENTITY:-}" \
    && "$SLIMLUMA_CODE_SIGN_IDENTITY" != "-" ]]; then
    codesign \
        --force \
        --timestamp \
        --sign "$SLIMLUMA_CODE_SIGN_IDENTITY" \
        "$DMG_PATH"
fi

write_checksums
printf '%s\n' "$APP_ZIP" "$CLI_ARCHIVE" "$DMG_PATH" "$CHECKSUMS_PATH"
