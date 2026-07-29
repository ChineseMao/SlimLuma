#!/bin/zsh
set -euo pipefail

if (( $# == 0 )); then
    echo "Usage: $0 <Mach-O binary> [...]" >&2
    exit 2
fi

# Do not print matching strings: the rejected value is itself private data.
# Match every non-control path component, including Unicode user names.
PRIVATE_PATH_PATTERN='/Users/[^/[:cntrl:]]+|/home/[^/[:cntrl:]]+|/(private/)?var/folders/[^/[:cntrl:]]+|[A-Za-z]:\\Users\\[^\\[:cntrl:]]+'
typeset -a privacy_temp_files=()

cleanup() {
    local file
    for file in "${privacy_temp_files[@]}"; do
        /bin/rm -f "$file"
    done
}
trap cleanup EXIT

scan_xattrs() {
    local target="$1"
    local label="$2"
    local xattr_list
    xattr_list="$(/usr/bin/mktemp -t slimluma-xattrs)"
    privacy_temp_files+=("$xattr_list")
    if [[ -L "$target" ]]; then
        if ! /usr/bin/xattr -s -l "$target" \
            > "$xattr_list" 2>/dev/null; then
            echo "Release privacy check could not inspect metadata: $label" >&2
            exit 2
        fi
    elif ! /usr/bin/xattr -l "$target" \
        > "$xattr_list" 2>/dev/null; then
        echo "Release privacy check could not inspect metadata: $label" >&2
        exit 2
    fi
    if [[ -s "$xattr_list" ]]; then
        echo "Release privacy check failed: $label contains extended metadata." >&2
        exit 1
    fi
}

scan_file() {
    local file="$1"
    local label="$2"
    local grep_status
    if LC_ALL=C /usr/bin/grep -a -E -i "$PRIVATE_PATH_PATTERN" "$file" \
        >/dev/null 2>&1; then
        echo "Release privacy check failed: $label embeds a private build path." >&2
        exit 1
    else
        grep_status=$?
        if (( grep_status != 1 )); then
            echo "Release privacy check could not read: $label" >&2
            exit 2
        fi
    fi
}

scan_symlink() {
    local link="$1"
    local label="$2"
    local destination
    local grep_status
    if ! destination="$(/usr/bin/readlink "$link" 2>/dev/null)"; then
        echo "Release privacy check could not read link: $label" >&2
        exit 2
    fi
    if /usr/bin/printf '%s' "$destination" \
        | LC_ALL=C /usr/bin/grep -a -E -i "$PRIVATE_PATH_PATTERN" \
            >/dev/null 2>&1; then
        echo "Release privacy check failed: $label embeds a private link path." >&2
        exit 1
    else
        grep_status=$?
        if (( grep_status != 1 )); then
            echo "Release privacy check could not inspect link: $label" >&2
            exit 2
        fi
    fi
}

for target in "$@"; do
    if [[ -L "$target" ]]; then
        scan_xattrs "$target" "$(basename "$target")"
        scan_symlink "$target" "$(basename "$target")"
    elif [[ -f "$target" ]]; then
        scan_xattrs "$target" "$(basename "$target")"
        scan_file "$target" "$(basename "$target")"
    elif [[ -d "$target" ]]; then
        scan_xattrs "$target" "$(basename "$target")"
        file_list="$(/usr/bin/mktemp -t slimluma-privacy)"
        privacy_temp_files+=("$file_list")
        if ! /usr/bin/find "$target" -print0 \
            > "$file_list" 2>/dev/null; then
            echo "Release privacy check could not traverse: $(basename "$target")" >&2
            exit 2
        fi
        while IFS= read -r -d '' file; do
            if [[ -L "$file" ]]; then
                scan_xattrs "$file" "$(basename "$target")"
                scan_symlink "$file" "$(basename "$target")"
            elif [[ -d "$file" ]]; then
                if [[ "$file" != "$target" ]]; then
                    scan_xattrs "$file" "$(basename "$target")"
                fi
                continue
            elif [[ -f "$file" ]]; then
                scan_xattrs "$file" "$(basename "$target")"
                scan_file "$file" "$(basename "$target")"
            else
                echo "Release privacy check found an unsupported file type: $(basename "$target")" >&2
                exit 2
            fi
        done < "$file_list"
    else
        echo "Release privacy check target is missing: $target" >&2
        exit 2
    fi
    echo "Release privacy check passed: $(basename "$target")"
done
