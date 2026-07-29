#!/bin/zsh

# Shared Developer ID validation without storing the publisher's legal identity
# or Apple team identifier in the public repository.

slimluma_require_private_identity_config() {
    if [[ -z "${SLIMLUMA_EXPECTED_DEVELOPER_ID_AUTHORITY:-}" \
        || -z "${SLIMLUMA_EXPECTED_TEAM_ID:-}" ]]; then
        echo "Release identity is not privately configured." >&2
        return 1
    fi
}

slimluma_verify_developer_id_details() {
    local details="$1"
    local require_runtime="${2:-true}"
    local authority=""
    local team_identifier=""
    local line

    while IFS= read -r line; do
        if [[ -z "$authority" && "$line" == Authority=* ]]; then
            authority="${line#Authority=}"
        elif [[ "$line" == TeamIdentifier=* ]]; then
            team_identifier="${line#TeamIdentifier=}"
        fi
    done <<< "$details"

    if [[ "$authority" != "Developer ID Application: "* ]]; then
        echo "Release signature is not a Developer ID Application signature." >&2
        return 1
    fi
    if ! print -rn -- "$team_identifier" | grep -Eq '^[A-Z0-9]{10}$'; then
        echo "Release signature does not contain a valid Apple team identifier." >&2
        return 1
    fi
    if [[ "$details" != *"Timestamp="* ]]; then
        echo "Release signature has no secure timestamp." >&2
        return 1
    fi
    if [[ "$require_runtime" == "true" \
        && "$details" != *"flags=0x10000(runtime)"* ]]; then
        echo "Release binary does not enable Hardened Runtime." >&2
        return 1
    fi

    if [[ -n "${SLIMLUMA_EXPECTED_DEVELOPER_ID_AUTHORITY:-}" \
        && "$authority" != "$SLIMLUMA_EXPECTED_DEVELOPER_ID_AUTHORITY" ]]; then
        echo "Release signature does not match the privately configured authority." >&2
        return 1
    fi
    if [[ -n "${SLIMLUMA_EXPECTED_TEAM_ID:-}" \
        && "$team_identifier" != "$SLIMLUMA_EXPECTED_TEAM_ID" ]]; then
        echo "Release signature does not match the privately configured team." >&2
        return 1
    fi
}

slimluma_verify_developer_id_signature() {
    local target="$1"
    local require_runtime="${2:-true}"
    local details

    codesign --verify --strict "$target"
    details="$(codesign -dvvv "$target" 2>&1)"
    slimluma_verify_developer_id_details "$details" "$require_runtime"
}
