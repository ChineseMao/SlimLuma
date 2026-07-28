#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$PROJECT_DIR/dist"
FINAL_APP_DIR="$DIST_DIR/SlimLuma.app"
FINAL_CLI="$DIST_DIR/slimluma"
CODE_SIGN_IDENTITY="${SLIMLUMA_CODE_SIGN_IDENTITY:--}"
EXPECTED_DEVELOPER_ID_AUTHORITY="Developer ID Application: private release identity"
EXPECTED_TEAM_ID="PRIVATE_TEAM_ID"
APP_VERSION="$(
    /usr/libexec/PlistBuddy \
        -c 'Print :CFBundleShortVersionString' \
        "$PROJECT_DIR/Support/Info.plist"
)"
if [[ "$APP_VERSION" == "0.2.0" ]] \
    && [[ "$(sed -n '1p' "$PROJECT_DIR/LICENSE")" != "MIT License" ]]; then
    echo "Refusing to rebuild historical MIT version 0.2.0 with different license terms." >&2
    exit 2
fi
mkdir -p "$DIST_DIR"
PACKAGE_LOCK_FILE="$DIST_DIR/.SlimLuma-package.lock"
exec 9>"$PACKAGE_LOCK_FILE"
if ! /usr/bin/lockf -s -t 0 9; then
    echo "Another SlimLuma package build is already running." >&2
    exit 75
fi

STAGE_ROOT=""
APP_DIR=""
CONTENTS_DIR=""
ICONSET_DIR=""
METADATA_TEMP_DIR=""
ATOMIC_SWAP_TOOL=""
CLI_STAGE=""
APP_RELEASE_BINARY=""
CLI_RELEASE_BINARY=""
PROMOTION_SWAPPED=false
FIRST_PROMOTION_MOVED=false
PROMOTION_VERIFIED=false

cleanup() {
    local exit_status=$?
    local preserve_stage=false
    set +e

    if $PROMOTION_SWAPPED && ! $PROMOTION_VERIFIED \
        && [[ -x "$ATOMIC_SWAP_TOOL" ]] \
        && [[ -e "$APP_DIR" && -e "$FINAL_APP_DIR" ]]; then
        if "$ATOMIC_SWAP_TOOL" "$APP_DIR" "$FINAL_APP_DIR"; then
            PROMOTION_SWAPPED=false
        else
            preserve_stage=true
            echo "Automatic app rollback failed; previous app preserved at:" >&2
            echo "$APP_DIR" >&2
        fi
    fi
    if $FIRST_PROMOTION_MOVED && ! $PROMOTION_VERIFIED \
        && [[ -e "$FINAL_APP_DIR" && ! -e "$APP_DIR" ]]; then
        if mv "$FINAL_APP_DIR" "$APP_DIR"; then
            FIRST_PROMOTION_MOVED=false
        else
            preserve_stage=true
            echo "Unverified first-install app remains at:" >&2
            echo "$FINAL_APP_DIR" >&2
        fi
    fi

    if [[ -n "$METADATA_TEMP_DIR" ]]; then
        rm -rf "$METADATA_TEMP_DIR"
    fi
    if [[ -n "$STAGE_ROOT" ]] && ! $preserve_stage; then
        rm -rf "$STAGE_ROOT"
    fi
    if [[ -n "$ICONSET_DIR" && -e "$ICONSET_DIR" ]]; then
        rm -rf "$ICONSET_DIR"
    fi
    return "$exit_status"
}
trap cleanup EXIT

STAGE_ROOT="$(mktemp -d "$DIST_DIR/.SlimLuma-stage.XXXXXX")"
APP_DIR="$STAGE_ROOT/SlimLuma.app"
CONTENTS_DIR="$APP_DIR/Contents"
ICONSET_DIR="$STAGE_ROOT/SlimLuma.iconset"
METADATA_TEMP_DIR="$(mktemp -d)"
ATOMIC_SWAP_TOOL="$STAGE_ROOT/atomic-swap"
CLI_STAGE="$STAGE_ROOT/slimluma"

cd "$PROJECT_DIR"
node "scripts/sync-system-localizations.mjs"
node "scripts/sync-system-localizations.mjs" --check
swift test
swift build -c release --arch arm64 --arch x86_64
xcrun swiftc "scripts/atomic-swap.swift" -o "$ATOMIC_SWAP_TOOL"

APP_RELEASE_BINARY="$PROJECT_DIR/.build/apple/Products/Release/SlimLumaApp"
CLI_RELEASE_BINARY="$PROJECT_DIR/.build/apple/Products/Release/slimluma"
[[ -x "$APP_RELEASE_BINARY" ]]
[[ -x "$CLI_RELEASE_BINARY" ]]
if cmp -s "$APP_RELEASE_BINARY" "$CLI_RELEASE_BINARY"; then
    echo "App and CLI release products unexpectedly contain the same binary." >&2
    exit 1
fi

rm -rf "$ICONSET_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"

cp "$APP_RELEASE_BINARY" "$CONTENTS_DIR/MacOS/SlimLuma"
cp "$CLI_RELEASE_BINARY" "$CLI_STAGE"
cp "Support/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "LICENSE" "$CONTENTS_DIR/Resources/LICENSE"
cp "THIRD_PARTY_NOTICES.md" \
    "$CONTENTS_DIR/Resources/THIRD_PARTY_NOTICES.md"
mkdir -p "$CONTENTS_DIR/Resources/ThirdPartyLicenses"
SWIFT_ARGUMENT_PARSER_LICENSE=".build/checkouts/swift-argument-parser/LICENSE.txt"
if [[ ! -f "$SWIFT_ARGUMENT_PARSER_LICENSE" ]]; then
    echo "Swift Argument Parser license was not found after package resolution." >&2
    exit 1
fi
cp "$SWIFT_ARGUMENT_PARSER_LICENSE" \
    "$CONTENTS_DIR/Resources/ThirdPartyLicenses/SwiftArgumentParser-LICENSE.txt"
for localization_dir in Sources/SlimLuma/Resources/*.lproj; do
    cp -R "$localization_dir" "$CONTENTS_DIR/Resources/"
done
xcrun xcstringstool compile \
    "Sources/SlimLuma/Resources/AppShortcuts.xcstrings" \
    --output-directory "$CONTENTS_DIR/Resources"

APPINTENTS_PROCESSOR="$(xcrun --find appintentsmetadataprocessor)"
TOOLCHAIN_DIR="$(dirname "$(dirname "$(dirname "$APPINTENTS_PROCESSOR")")")"
SDK_ROOT="$(xcrun --sdk macosx --show-sdk-path)"
XCODE_BUILD_VERSION="$(xcodebuild -version | sed -n 's/^Build version //p')"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Support/Info.plist)"
APP_BUILD_DIR="$PROJECT_DIR/.build/apple/Intermediates.noindex/SlimLuma.build/Release/SlimLumaApp.build"
ARM64_OBJECTS_DIR="$APP_BUILD_DIR/Objects-normal/arm64"
X86_64_OBJECTS_DIR="$APP_BUILD_DIR/Objects-normal/x86_64"
ARM64_CONST_VALUES_LIST="$METADATA_TEMP_DIR/arm64.constvalues.list"
X86_64_CONST_VALUES_LIST="$METADATA_TEMP_DIR/x86_64.constvalues.list"

printf '%s\n' \
    "$ARM64_OBJECTS_DIR/SlimLumaApp-primary.swiftconstvalues" \
    > "$ARM64_CONST_VALUES_LIST"
printf '%s\n' \
    "$X86_64_OBJECTS_DIR/SlimLumaApp-primary.swiftconstvalues" \
    > "$X86_64_CONST_VALUES_LIST"

"$APPINTENTS_PROCESSOR" \
    --toolchain-dir "$TOOLCHAIN_DIR" \
    --module-name SlimLuma \
    --sdk-root "$SDK_ROOT" \
    --xcode-version "$XCODE_BUILD_VERSION" \
    --platform-family macOS \
    --deployment-target 14.0 \
    --bundle-identifier "$BUNDLE_ID" \
    --output "$METADATA_TEMP_DIR/SlimLuma.appintents" \
    --target-triple arm64-apple-macos14.0 \
    --target-triple x86_64-apple-macos14.0 \
    --binary-file "$APP_RELEASE_BINARY" \
    --dependency-file "$ARM64_OBJECTS_DIR/SlimLumaApp_dependency_info.dat" \
    --dependency-file "$X86_64_OBJECTS_DIR/SlimLumaApp_dependency_info.dat" \
    --stringsdata-file "$METADATA_TEMP_DIR/arm64.stringsdata" \
    --stringsdata-file "$METADATA_TEMP_DIR/x86_64.stringsdata" \
    --source-file-list "$ARM64_OBJECTS_DIR/SlimLumaApp.SwiftFileList" \
    --source-file-list "$X86_64_OBJECTS_DIR/SlimLumaApp.SwiftFileList" \
    --swift-const-vals-list "$ARM64_CONST_VALUES_LIST" \
    --swift-const-vals-list "$X86_64_CONST_VALUES_LIST" \
    --force \
    --compile-time-extraction \
    --deployment-aware-processing \
    --validate-assistant-intents

cp -R \
    "$METADATA_TEMP_DIR/SlimLuma.appintents/Metadata.appintents" \
    "$CONTENTS_DIR/Resources/Metadata.appintents"

swift "scripts/generate-icon.swift" "$ICONSET_DIR"
iconutil -c icns "$ICONSET_DIR" -o "$CONTENTS_DIR/Resources/AppIcon.icns"

if [[ "$CODE_SIGN_IDENTITY" == "-" ]]; then
    codesign --force --sign - "$CONTENTS_DIR/MacOS/SlimLuma"
    codesign --force --sign - "$APP_DIR"
    codesign --force --sign - "$CLI_STAGE"
else
    codesign \
        --force \
        --options runtime \
        --timestamp \
        --sign "$CODE_SIGN_IDENTITY" \
        "$CONTENTS_DIR/MacOS/SlimLuma"
    codesign \
        --force \
        --options runtime \
        --timestamp \
        --sign "$CODE_SIGN_IDENTITY" \
        "$APP_DIR"
    codesign \
        --force \
        --options runtime \
        --timestamp \
        --sign "$CODE_SIGN_IDENTITY" \
        "$CLI_STAGE"
    export SLIMLUMA_REQUIRE_DEVELOPER_ID=1
fi
codesign --verify --strict "$CLI_STAGE"
if [[ "$CODE_SIGN_IDENTITY" != "-" ]]; then
    CLI_SIGNATURE_DETAILS="$(codesign -dvvv "$CLI_STAGE" 2>&1)"
    if [[ "$CLI_SIGNATURE_DETAILS" != *"Authority=$EXPECTED_DEVELOPER_ID_AUTHORITY"* ]]; then
        echo "Release CLI signing authority does not match the long-term publisher." >&2
        exit 1
    fi
    if [[ "$CLI_SIGNATURE_DETAILS" != *"TeamIdentifier=$EXPECTED_TEAM_ID"* ]]; then
        echo "Release CLI TeamIdentifier does not match $EXPECTED_TEAM_ID." >&2
        exit 1
    fi
fi
for required_architecture in arm64 x86_64; do
    if [[ " $(lipo -archs "$CLI_STAGE") " != *" $required_architecture "* ]]; then
        echo "CLI is missing architecture: $required_architecture" >&2
        exit 1
    fi
done
"$PROJECT_DIR/scripts/verify-packaged-app.sh" "$APP_DIR"

if [[ -L "$FINAL_APP_DIR" ]]; then
    echo "Refusing to replace a symbolic-link app path:" >&2
    echo "$FINAL_APP_DIR" >&2
    exit 1
fi
if [[ -e "$FINAL_APP_DIR" && ! -d "$FINAL_APP_DIR" ]]; then
    echo "Refusing to replace a non-directory app path:" >&2
    echo "$FINAL_APP_DIR" >&2
    exit 1
fi

if [[ -e "$FINAL_APP_DIR" ]]; then
    "$ATOMIC_SWAP_TOOL" "$APP_DIR" "$FINAL_APP_DIR"
    PROMOTION_SWAPPED=true
else
    mv "$APP_DIR" "$FINAL_APP_DIR"
    FIRST_PROMOTION_MOVED=true
fi

if ! "$PROJECT_DIR/scripts/verify-packaged-app.sh" "$FINAL_APP_DIR"; then
    if $PROMOTION_SWAPPED; then
        "$ATOMIC_SWAP_TOOL" "$APP_DIR" "$FINAL_APP_DIR"
        PROMOTION_SWAPPED=false
    elif $FIRST_PROMOTION_MOVED; then
        mv "$FINAL_APP_DIR" "$APP_DIR"
        FIRST_PROMOTION_MOVED=false
    fi
    exit 1
fi

mv -f "$CLI_STAGE" "$FINAL_CLI"
codesign --verify --strict "$FINAL_CLI"

PROMOTION_VERIFIED=true
PROMOTION_SWAPPED=false
FIRST_PROMOTION_MOVED=false

echo "$FINAL_APP_DIR"
echo "$FINAL_CLI"
