#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:-$PROJECT_DIR/dist/SlimLuma.app}"

if [[ ! -e "$TARGET" ]]; then
    echo "Notarization target does not exist: $TARGET" >&2
    exit 2
fi

AUTH_ARGS=()
if [[ -n "${SLIMLUMA_NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
    AUTH_ARGS=(
        --keychain-profile "$SLIMLUMA_NOTARY_KEYCHAIN_PROFILE"
    )
elif [[ -n "${APPLE_API_KEY_ID:-}" \
    && -n "${APPLE_API_ISSUER_ID:-}" \
    && -n "${APPLE_API_PRIVATE_KEY_PATH:-}" ]]; then
    AUTH_ARGS=(
        --key "$APPLE_API_PRIVATE_KEY_PATH"
        --key-id "$APPLE_API_KEY_ID"
        --issuer "$APPLE_API_ISSUER_ID"
    )
else
    echo "Configure SLIMLUMA_NOTARY_KEYCHAIN_PROFILE or App Store Connect API credentials." >&2
    exit 2
fi

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/SlimLuma-notary.XXXXXX")"
cleanup() {
    local exit_status=$?
    rm -rf "$TEMP_DIR"
    return "$exit_status"
}
trap cleanup EXIT

SUBMISSION_TARGET="$TARGET"
if [[ -d "$TARGET" && "$TARGET" == *.app ]]; then
    SUBMISSION_TARGET="$TEMP_DIR/SlimLuma-notary.zip"
    ditto -c -k --sequesterRsrc --keepParent \
        "$TARGET" "$SUBMISSION_TARGET"
elif [[ "$TARGET" != *.dmg && "$TARGET" != *.pkg && "$TARGET" != *.zip ]]; then
    SUBMISSION_TARGET="$TEMP_DIR/$(basename "$TARGET").zip"
    ditto -c -k --keepParent "$TARGET" "$SUBMISSION_TARGET"
fi

RESULT_JSON="$TEMP_DIR/notary-result.json"
SUBMISSION_ID="${SLIMLUMA_NOTARY_SUBMISSION_ID:-}"
if [[ -z "$SUBMISSION_ID" ]]; then
    xcrun notarytool submit "$SUBMISSION_TARGET" \
        --no-wait \
        --output-format json \
        "${AUTH_ARGS[@]}" > "$RESULT_JSON"
    SUBMISSION_ID="$(jq -er '.id' "$RESULT_JSON")"
else
    echo "Resuming notarization submission: $SUBMISSION_ID"
fi

POLL_INTERVAL_SECONDS="${SLIMLUMA_NOTARY_POLL_INTERVAL_SECONDS:-15}"
MAX_WAIT_SECONDS="${SLIMLUMA_NOTARY_MAX_WAIT_SECONDS:-1800}"
if [[ ! "$POLL_INTERVAL_SECONDS" =~ '^[1-9][0-9]*$' \
    || ! "$MAX_WAIT_SECONDS" =~ '^[1-9][0-9]*$' ]]; then
    echo "Notarization polling intervals must be positive integers." >&2
    exit 2
fi
DEADLINE_EPOCH="$(($(date +%s) + MAX_WAIT_SECONDS))"
NOTARY_STATE=""
while [[ "$(date +%s)" -lt "$DEADLINE_EPOCH" ]]; do
    if xcrun notarytool info "$SUBMISSION_ID" \
        --output-format json \
        "${AUTH_ARGS[@]}" > "$RESULT_JSON"; then
        NOTARY_STATE="$(jq -er '.status' "$RESULT_JSON")"
        case "$NOTARY_STATE" in
            Accepted)
                break
                ;;
            Invalid|Rejected)
                echo "Apple notarization failed with status: $NOTARY_STATE" >&2
                xcrun notarytool log \
                    "$SUBMISSION_ID" "${AUTH_ARGS[@]}" >&2 || true
                exit 1
                ;;
            *)
                echo "Apple notarization status: $NOTARY_STATE"
                ;;
        esac
    else
        echo "Apple notarization status check failed; retrying." >&2
    fi
    sleep "$POLL_INTERVAL_SECONDS"
done
if [[ "$NOTARY_STATE" != "Accepted" ]]; then
    echo "Apple notarization did not finish within ${MAX_WAIT_SECONDS}s." >&2
    echo "Resume with SLIMLUMA_NOTARY_SUBMISSION_ID=$SUBMISSION_ID" >&2
    exit 1
fi

if [[ -d "$TARGET" && "$TARGET" == *.app ]]; then
    xcrun stapler staple "$TARGET"
    xcrun stapler validate "$TARGET"
    spctl --assess --type execute --verbose=4 "$TARGET"
elif [[ "$TARGET" == *.dmg ]]; then
    xcrun stapler staple "$TARGET"
    xcrun stapler validate "$TARGET"
    spctl --assess \
        --type open \
        --context context:primary-signature \
        --verbose=4 \
        "$TARGET"
else
    # A standalone command-line executable is not an app, bundle, package, or
    # disk image, so spctl can report "does not seem to be an app" even after
    # the submitted archive is accepted. The Accepted notary result above plus
    # strict code-signature verification are the applicable release gates.
    codesign --verify --strict --verbose=2 "$TARGET"
fi

echo "Accepted: $SUBMISSION_ID"
