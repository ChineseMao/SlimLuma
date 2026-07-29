#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="${1:-$PROJECT_DIR/dist/SlimLuma.app}"
CONTENTS_DIR="$APP_DIR/Contents"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BINARY="$CONTENTS_DIR/MacOS/SlimLuma"
ACTIONS_DATA="$RESOURCES_DIR/Metadata.appintents/extract.actionsdata"
DOCUMENT_TYPE_KEY="支持的媒体文件"
SERVICE_MENU_KEY="添加到 SlimLuma 压缩队列"
SERVICE_DESCRIPTION_KEY="将所选图片、视频或 PDF 添加到 SlimLuma 的媒体压缩队列。"
SHORTCUT_PHRASE_KEYS=(
    '用 ${applicationName} 压缩文件'
    '添加文件到 ${applicationName}'
)
EXPECTED_SOURCE_KEY_COUNT="$(
    jq 'length' \
        "$PROJECT_DIR/Sources/SlimLuma/Resources/LocalizationKeys.json"
)"
EXPECTED_COPYRIGHT="Copyright © 2026 SlimLuma copyright holders. All rights reserved."
source "$PROJECT_DIR/scripts/release-identity.sh"

EXPECTED_LOCALES=(
    ar
    bn
    de
    en
    es-419
    es-ES
    fr
    hi
    id
    ja
    pa-Arab
    pcm
    pt-BR
    pt-PT
    ru
    sw
    te
    ur
    zh-Hans
    zh-Hant
)

[[ -x "$BINARY" ]]
[[ -f "$CONTENTS_DIR/Info.plist" ]]
[[ -d "$RESOURCES_DIR/Metadata.appintents" ]]
[[ -f "$ACTIONS_DATA" ]]
[[ -f "$RESOURCES_DIR/Metadata.appintents/version.json" ]]
[[ -f "$RESOURCES_DIR/LICENSE" ]]
[[ -f "$RESOURCES_DIR/THIRD_PARTY_NOTICES.md" ]]
[[ -f "$RESOURCES_DIR/ThirdPartyLicenses/SwiftArgumentParser-LICENSE.txt" ]]
"$PROJECT_DIR/scripts/verify-release-privacy.sh" "$APP_DIR"
cmp -s "$PROJECT_DIR/LICENSE" "$RESOURCES_DIR/LICENSE"
cmp -s \
    "$PROJECT_DIR/THIRD_PARTY_NOTICES.md" \
    "$RESOURCES_DIR/THIRD_PARTY_NOTICES.md"
cmp -s \
    "$PROJECT_DIR/.build/checkouts/swift-argument-parser/LICENSE.txt" \
    "$RESOURCES_DIR/ThirdPartyLicenses/SwiftArgumentParser-LICENSE.txt"
if ! otool -L "$BINARY" | grep -q '/SwiftUI.framework/'; then
    echo "Packaged app executable is not linked as a SwiftUI application." >&2
    exit 1
fi
if [[ -n "$(find "$RESOURCES_DIR" -type l -print -quit)" ]]; then
    echo "Packaged resources must not contain symbolic links." >&2
    exit 1
fi

plutil -lint "$CONTENTS_DIR/Info.plist" >/dev/null
if [[ "$(
    /usr/libexec/PlistBuddy \
        -c 'Print :NSHumanReadableCopyright' \
        "$CONTENTS_DIR/Info.plist"
)" != "$EXPECTED_COPYRIGHT" ]]; then
    echo "Packaged copyright notice does not match the long-term publisher." >&2
    exit 1
fi
jq -e . "$ACTIONS_DATA" >/dev/null
jq -e . "$RESOURCES_DIR/Metadata.appintents/version.json" >/dev/null
jq -e '
    (.version == 1)
    and (.generator.name == "xcode-tools")
    and (
        .generator.version
        | type == "string" and length > 0
    )
    and (
        .autoShortcutProviderMangledName
        | type == "string" and length > 0
    )
    and (
        .actions.AddMediaToSlimLumaIntent.identifier
        == "AddMediaToSlimLumaIntent"
    )
    and (
        .actions.AddMediaToSlimLumaIntent.fullyQualifiedTypeName
        == "SlimLuma.AddMediaToSlimLumaIntent"
    )
    and (
        .actions.AddMediaToSlimLumaIntent.mangledTypeNameV2
        | type == "string" and length > 0
    )
    and (
        .actions.AddMediaToSlimLumaIntent.isDiscoverable == true
    )
    and (
        .actions.AddMediaToSlimLumaIntent.openAppWhenRun == true
    )
    and (
        .actions.AddMediaToSlimLumaIntent.availabilityAnnotations
        == {
            "LNPlatformNameMACOS": {
                "introducedVersion": "15.0"
            },
            "LNPlatformNameWildcard": {
                "introducedVersion": "*"
            }
        }
    )
    and (
        .actions.AddMediaToSlimLumaIntent.supportedModes == 2
    )
    and (
        .actions.AddMediaToSlimLumaIntent.title.key
        == "添加到 SlimLuma 压缩队列"
    )
    and (
        .actions.AddMediaToSlimLumaIntent.descriptionMetadata.descriptionText.key
        == "把图片、视频或 PDF 交给 SlimLuma，并可在文件就绪后自动开始压缩。"
    )
    and (
        .actions.AddMediaToSlimLumaIntent
        .actionConfiguration.actionSummary.wrapper
        .summaryString.formatString
        == "把 ${files} 添加到 SlimLuma"
    )
    and (
        .actions.AddMediaToSlimLumaIntent
        .actionConfiguration.actionSummary.wrapper
        .summaryString.parameterIdentifiers
        == ["files"]
    )
    and (
        .actions.AddMediaToSlimLumaIntent
        .actionConfiguration.actionSummary.wrapper
        .otherParameterIdentifiers
        == []
    )
    and (
        .actions.AddMediaToSlimLumaIntent.visibilityMetadata
        == {
            "assistantOnly": false,
            "isDiscoverable": true
        }
    )
    and (
        [.actions.AddMediaToSlimLumaIntent.parameters[].name] | sort
        == ["files", "startsCompression"]
    )
    and (
        .actions.AddMediaToSlimLumaIntent.parameters[]
        | select(.name == "files")
        | .typeSpecificMetadata[0]
        == "LNValueTypeMetadataKeyFileSupportedTypes"
    )
    and (
        [
            .actions.AddMediaToSlimLumaIntent.parameters[]
            | select(.name == "files")
            | .typeSpecificMetadata[1].array.elements[]
            | .string.wrapper
        ] | sort
        == ["com.adobe.pdf", "public.image", "public.movie"]
    )
    and (
        .actions.AddMediaToSlimLumaIntent.parameters[]
        | select(.name == "files")
        | .valueType.array.wrapper.memberValueType.intents.wrapper.typeIdentifier
        == 12
    )
    and (
        .actions.AddMediaToSlimLumaIntent.parameters[]
        | select(.name == "files")
        | .valueType.array.wrapper.capabilities
        == 3
    )
    and (
        .actions.AddMediaToSlimLumaIntent.parameters[]
        | select(.name == "startsCompression")
        | .valueType.primitive.wrapper.typeIdentifier
        == 1
    )
    and (
        .actions.AddMediaToSlimLumaIntent.parameters[]
        | select(.name == "startsCompression")
        | .typeSpecificMetadata[0]
        == "LNValueTypeSpecificMetadataKeyDefaultValue"
    )
    and (
        .actions.AddMediaToSlimLumaIntent.parameters[]
        | select(.name == "startsCompression")
        | .typeSpecificMetadata[1].int.wrapper
        == 0
    )
    and (.autoShortcuts | length == 1)
    and (
        .autoShortcuts[0].actionIdentifier
        == "AddMediaToSlimLumaIntent"
    )
    and (
        .autoShortcuts[0].availabilityAnnotations
        == {
            "LNPlatformNameMACOS": {
                "introducedVersion": "15.0"
            },
            "LNPlatformNameWildcard": {
                "introducedVersion": "*"
            }
        }
    )
    and (
        [.autoShortcuts[0].phraseTemplates[].key] | sort
        == [
            "添加文件到 ${applicationName}",
            "用 ${applicationName} 压缩文件"
        ]
    )
    and (
        .autoShortcuts[0].shortTitle.key
        == "添加到压缩队列"
    )
    and (
        .autoShortcuts[0].systemImageName
        == "arrow.down.right.and.arrow.up.left"
    )
' "$ACTIONS_DATA" >/dev/null
METADATA_VERSION_FILE="$RESOURCES_DIR/Metadata.appintents/version.json"
[[ "$(jq -er '.version' "$METADATA_VERSION_FILE")" == "3.0" ]]
METADATA_TOOLS_VERSION="$(
    jq -er '.toolsVersion | select(type == "string" and length > 0)' \
        "$METADATA_VERSION_FILE"
)"
[[ "$(
    jq -er '.generator.version | select(type == "string" and length > 0)' \
        "$ACTIONS_DATA"
)" == "$METADATA_TOOLS_VERSION" ]]
codesign --verify --deep --strict "$APP_DIR"
if [[ "${SLIMLUMA_REQUIRE_DEVELOPER_ID:-0}" == "1" ]]; then
    slimluma_require_private_identity_config
    slimluma_verify_developer_id_signature "$APP_DIR" true
    if ! ENTITLEMENTS="$(
        codesign -d --entitlements - --xml "$APP_DIR" 2>/dev/null
    )"; then
        echo "Release app entitlements could not be read." >&2
        codesign -d --entitlements - --xml "$APP_DIR" >/dev/null || :
        exit 1
    fi
    if [[ -n "$ENTITLEMENTS" ]] \
        && ! print -r -- "$ENTITLEMENTS" | plutil -lint - >/dev/null; then
        echo "Release app entitlements are not a valid property list." >&2
        exit 1
    fi
    if [[ -n "$ENTITLEMENTS" ]] \
        && GET_TASK_ALLOW="$(
            print -r -- "$ENTITLEMENTS" \
                | plutil -extract \
                    'com\.apple\.security\.get-task-allow' \
                    raw \
                    -o - \
                    - \
                    2>/dev/null
        )" \
        && [[ "$GET_TASK_ALLOW" == "true" ]]; then
        echo "Release app must not contain get-task-allow." >&2
        exit 1
    fi
fi

ARCHITECTURES=("$(lipo -archs "$BINARY")")
for required_architecture in arm64 x86_64; do
    if [[ " ${ARCHITECTURES[*]} " != *" $required_architecture "* ]]; then
        echo "Missing architecture: $required_architecture" >&2
        exit 1
    fi
done

ACTUAL_LOCALES=(
    "${(@f)$(find "$RESOURCES_DIR" -mindepth 1 -maxdepth 1 \
        -type d -name '*.lproj' -exec basename {} .lproj \; | sort)}"
)
if [[ "${(j:,:)ACTUAL_LOCALES}" != "${(j:,:)EXPECTED_LOCALES}" ]]; then
    echo "Packaged locale set does not match the product locale set." >&2
    echo "Expected: ${(j:, :)EXPECTED_LOCALES}" >&2
    echo "Actual: ${(j:, :)ACTUAL_LOCALES}" >&2
    exit 1
fi

DECLARED_LOCALES=(
    "${(@f)$(plutil -convert json -o - "$CONTENTS_DIR/Info.plist" \
        | jq -r '.CFBundleLocalizations[]' | sort)}"
)
if [[ "${(j:,:)DECLARED_LOCALES}" != "${(j:,:)EXPECTED_LOCALES}" ]]; then
    echo "Info.plist locale declarations do not match packaged resources." >&2
    exit 1
fi

SOURCE_LOCALIZABLE="$RESOURCES_DIR/zh-Hans.lproj/Localizable.strings"
[[ ! -e "$RESOURCES_DIR/zh-Hans.lproj/AppShortcuts.strings" ]]
SOURCE_KEY_COUNT="$(
    plutil -convert json -o - "$SOURCE_LOCALIZABLE" | jq 'keys | length'
)"
if [[ "$SOURCE_KEY_COUNT" != "$EXPECTED_SOURCE_KEY_COUNT" ]]; then
    echo "Packaged source localization key count is stale." >&2
    echo "Expected: $EXPECTED_SOURCE_KEY_COUNT" >&2
    echo "Actual: $SOURCE_KEY_COUNT" >&2
    exit 1
fi
EXPECTED_PLURAL_KEY_COUNT="$(
    plutil -convert json -o - \
        "$RESOURCES_DIR/zh-Hans.lproj/Localizable.stringsdict" \
        | jq 'keys | length'
)"
SOURCE_KEY_HASH="$(
    plutil -convert json -o - "$SOURCE_LOCALIZABLE" \
        | jq -S 'keys' \
        | shasum -a 256 \
        | awk '{print $1}'
)"

for locale in "${EXPECTED_LOCALES[@]}"; do
    localization_dir="$RESOURCES_DIR/$locale.lproj"
    for table in \
        Localizable.strings \
        Localizable.stringsdict \
        InfoPlist.strings \
        ServicesMenu.strings; do
        plutil -lint "$localization_dir/$table" >/dev/null
    done

    localizable_json="$(
        plutil -convert json -o - "$localization_dir/Localizable.strings"
    )"
    locale_key_hash="$(
        print -r -- "$localizable_json" \
            | jq -S 'keys' \
            | shasum -a 256 \
            | awk '{print $1}'
    )"
    if [[ "$locale_key_hash" != "$SOURCE_KEY_HASH" ]]; then
        echo "$locale does not contain the complete ${EXPECTED_SOURCE_KEY_COUNT}-key localization table." >&2
        exit 1
    fi
    plural_key_count="$(
        plutil -convert json -o - \
            "$localization_dir/Localizable.stringsdict" \
            | jq 'keys | length'
    )"
    if [[ "$plural_key_count" != "$EXPECTED_PLURAL_KEY_COUNT" ]]; then
        echo "$locale does not contain the complete ${EXPECTED_PLURAL_KEY_COUNT}-key plural table." >&2
        exit 1
    fi

    expected_document_type="$(
        print -r -- "$localizable_json" \
            | jq -er --arg key "$DOCUMENT_TYPE_KEY" '.[$key]'
    )"
    actual_document_type="$(
        plutil -convert json -o - "$localization_dir/InfoPlist.strings" \
            | jq -er '.CFBundleTypeName'
    )"
    if [[ "$actual_document_type" != "$expected_document_type" ]]; then
        echo "$locale has a stale Finder document type translation." >&2
        exit 1
    fi

    expected_service_menu="$(
        print -r -- "$localizable_json" \
            | jq -er --arg key "$SERVICE_MENU_KEY" '.[$key]'
    )"
    expected_service_description="$(
        print -r -- "$localizable_json" \
            | jq -er --arg key "$SERVICE_DESCRIPTION_KEY" '.[$key]'
    )"
    services_json="$(
        plutil -convert json -o - "$localization_dir/ServicesMenu.strings"
    )"
    actual_service_menu="$(
        print -r -- "$services_json" \
            | jq -er --arg key "$SERVICE_MENU_KEY" '.[$key]'
    )"
    actual_service_description="$(
        print -r -- "$services_json" \
            | jq -er '.SLIMLUMA_SERVICE_DESCRIPTION'
    )"
    if [[ "$actual_service_menu" != "$expected_service_menu" \
        || "$actual_service_description" != "$expected_service_description" ]]; then
        echo "$locale has stale Finder service translations." >&2
        exit 1
    fi

    if [[ "$locale" != "zh-Hans" ]]; then
        plutil -lint "$localization_dir/AppShortcuts.strings" >/dev/null
        shortcuts_json="$(
            plutil -convert json -o - \
                "$localization_dir/AppShortcuts.strings"
        )"
        if [[ "$(print -r -- "$shortcuts_json" | jq 'keys | length')" != "2" ]]; then
            echo "$locale does not contain both App Shortcut phrases." >&2
            exit 1
        fi
        for key in "${SHORTCUT_PHRASE_KEYS[@]}"; do
            expected_shortcut="$(
                print -r -- "$localizable_json" \
                    | jq -er --arg key "$key" '.[$key]'
            )"
            actual_shortcut="$(
                print -r -- "$shortcuts_json" \
                    | jq -er --arg key "$key" '.[$key]'
            )"
            if [[ "$actual_shortcut" != "$expected_shortcut" ]]; then
                echo "$locale has a stale App Shortcut phrase: $key" >&2
                exit 1
            fi
        done
    fi
done

echo "Verified Universal app, signature, metadata, and 20 localization bundles:"
echo "$APP_DIR"
