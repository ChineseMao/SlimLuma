#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

failures=()

if git ls-files \
    | grep -E '\.(p8|p12|pem|key|cer|csr|pfx|mobileprovision)$' \
    >/dev/null; then
    failures+=("tracked credential or certificate file")
fi

if git grep -nI -E -- \
    '-----BEGIN ([A-Z0-9 ]+ )?PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9_]+|AKIA[0-9A-Z]{16}|xox[baprs]-|AIza[0-9A-Za-z_-]{20,}' \
    -- . >/dev/null; then
    failures+=("high-confidence credential material")
fi

if git grep -nI -E -- \
    'TechnologyCo[.]|Developer ID Application:[^[:cntrl:]]*[(][A-Z0-9]{10}[)]|Team(Identifier| ID)?[^[:cntrl:]]{0,40}[` (][A-Z0-9]{10}[` )]' \
    -- . \
    ':(exclude)scripts/test-release-identity.sh' \
    ':(exclude)scripts/verify-repository-privacy.sh' \
    >/dev/null; then
    failures+=("embedded legal publisher or Apple team identifier")
fi

if git grep -nI -E -- \
    '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' \
    -- . >/dev/null; then
    failures+=("persisted operational UUID")
fi

if git grep -nI -E -- \
    'releases/download/v0[.]2[.]0/(SlimLuma-0[.]2[.]0-macOS-universal[.](dmg|zip)|slimluma-0[.]2[.]0-macOS-universal[.]tar[.]gz)' \
    -- . \
    ':(exclude)scripts/verify-repository-privacy.sh' \
    >/dev/null; then
    failures+=("link to a withdrawn privacy-affected release artifact")
fi

PERSONAL_PATH_HITS="$(
    git grep -nI -E -- '/Users/[^/[:space:]]+' -- . \
        ':(exclude)scripts/test-release-privacy.sh' \
        ':(exclude)scripts/verify-release-privacy.sh' \
        ':(exclude)scripts/verify-repository-privacy.sh' \
        || true
)"
if [[ -n "$PERSONAL_PATH_HITS" ]]; then
    failures+=("tracked absolute macOS user path")
fi

EMAIL_HITS="$(
    git grep -nI -E -- \
        '[[:alnum:]._%+-]+@[[:alnum:].-]+[.][[:alpha:]]{2,}' \
        -- . \
        | grep -Ev 'users[.]noreply[.]github[.]com|noreply@github[.]com' \
        || true
)"
if [[ -n "$EMAIL_HITS" ]]; then
    failures+=("tracked non-noreply email address")
fi

if (( ${#failures[@]} > 0 )); then
    printf 'Repository privacy check failed: %s\n' "${failures[@]}" >&2
    exit 1
fi

echo "Repository privacy checks passed."
