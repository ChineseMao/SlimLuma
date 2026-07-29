#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$PROJECT_DIR/scripts/release-identity.sh"

VALID_DETAILS=$'Authority=Developer ID Application: Example Publisher (ABCDE12345)\nTeamIdentifier=ABCDE12345\nTimestamp=Jul 29, 2026\nCodeDirectory v=20500 flags=0x10000(runtime)'

if slimluma_require_private_identity_config >/dev/null 2>&1; then
    echo "Missing private release identity configuration was accepted." >&2
    exit 1
fi

SLIMLUMA_EXPECTED_DEVELOPER_ID_AUTHORITY='Developer ID Application: Example Publisher (ABCDE12345)' \
SLIMLUMA_EXPECTED_TEAM_ID='ABCDE12345' \
    slimluma_require_private_identity_config

slimluma_verify_developer_id_details "$VALID_DETAILS" true

SLIMLUMA_EXPECTED_DEVELOPER_ID_AUTHORITY='Developer ID Application: Example Publisher (ABCDE12345)' \
SLIMLUMA_EXPECTED_TEAM_ID='ABCDE12345' \
    slimluma_verify_developer_id_details "$VALID_DETAILS" true

if slimluma_verify_developer_id_details \
    $'Authority=Developer ID Application: Example Publisher (ABCDE12345)\nTeamIdentifier=invalid\nTimestamp=Jul 29, 2026\nCodeDirectory v=20500 flags=0x10000(runtime)' \
    true \
    >/dev/null 2>&1; then
    echo "Invalid team identifier was accepted." >&2
    exit 1
fi

if slimluma_verify_developer_id_details \
    $'Authority=Developer ID Application: Example Publisher (ABCDE12345)\nTeamIdentifier=ABCDE12345\nCodeDirectory v=20500 flags=0x10000(runtime)' \
    true \
    >/dev/null 2>&1; then
    echo "Signature without a secure timestamp was accepted." >&2
    exit 1
fi

if slimluma_verify_developer_id_details \
    $'Authority=Developer ID Application: Example Publisher (ABCDE12345)\nTeamIdentifier=ABCDE12345\nTimestamp=Jul 29, 2026' \
    true \
    >/dev/null 2>&1; then
    echo "Signature without Hardened Runtime was accepted." >&2
    exit 1
fi

MISMATCH_OUTPUT="$(
    SLIMLUMA_EXPECTED_DEVELOPER_ID_AUTHORITY='Developer ID Application: Private Expected Value (ZZZZZ99999)' \
    SLIMLUMA_EXPECTED_TEAM_ID='ZZZZZ99999' \
        slimluma_verify_developer_id_details "$VALID_DETAILS" true 2>&1 \
        || true
)"
if [[ "$MISMATCH_OUTPUT" == *"ZZZZZ99999"* \
    || "$MISMATCH_OUTPUT" == *"Example Publisher"* ]]; then
    echo "Identity mismatch output disclosed configured identifiers." >&2
    exit 1
fi

echo "Release identity validation tests passed."
