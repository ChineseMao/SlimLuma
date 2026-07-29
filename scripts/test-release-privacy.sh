#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHECKER="$PROJECT_DIR/scripts/verify-release-privacy.sh"
FIXTURE_DIR="$(/usr/bin/mktemp -d -t slimluma-privacy-tests)"
trap '/bin/rm -rf "$FIXTURE_DIR"' EXIT

assert_rejected() {
    local fixture="$FIXTURE_DIR/$1"
    local value="$2"
    /usr/bin/printf '%s' "$value" > "$fixture"
    if "$CHECKER" "$fixture" >/dev/null 2>&1; then
        echo "Privacy fixture was not rejected: $1" >&2
        exit 1
    fi
}

assert_checker_status() {
    local expected="$1"
    local target="$2"
    local actual
    set +e
    "$CHECKER" "$target" >/dev/null 2>&1
    actual=$?
    set -e
    if (( actual != expected )); then
        echo "Privacy checker returned $actual instead of $expected." >&2
        exit 1
    fi
}

/usr/bin/printf '%s' \
    'This release contains only portable resource names.' \
    > "$FIXTURE_DIR/portable.bin"
"$CHECKER" "$FIXTURE_DIR/portable.bin" >/dev/null

assert_rejected mac-ascii.bin '/Users/example/Build/App'
assert_rejected mac-unicode.bin '/Users/测试/Build/App'
assert_rejected mac-lowercase.bin '/users/example/Build/App'
assert_rejected linux.bin '/home/example/build/app'
assert_rejected darwin-private.bin '/private/var/folders/ab/cache'
assert_rejected darwin-short.bin '/var/folders/ab/cache'
assert_rejected windows.bin 'C:\Users\example\Build\App'

private_link="$FIXTURE_DIR/private-link"
/bin/ln -s '/Users/example/private-target' "$private_link"
assert_checker_status 1 "$private_link"

xattr_file="$FIXTURE_DIR/extended-metadata.bin"
/usr/bin/printf '%s' 'portable' > "$xattr_file"
/usr/bin/xattr -w com.slimluma.fixture 'synthetic' "$xattr_file"
assert_checker_status 1 "$xattr_file"
/usr/bin/xattr -c "$xattr_file"

fifo_directory="$FIXTURE_DIR/fifo-directory"
/bin/mkdir "$fifo_directory"
/usr/bin/mkfifo "$fifo_directory/unsupported-node"
assert_checker_status 2 "$fifo_directory"

unreadable_file="$FIXTURE_DIR/unreadable.bin"
/usr/bin/printf '%s' 'portable' > "$unreadable_file"
/bin/chmod 000 "$unreadable_file"
assert_checker_status 2 "$unreadable_file"
/bin/chmod 600 "$unreadable_file"

unreadable_directory="$FIXTURE_DIR/unreadable-directory"
/bin/mkdir "$unreadable_directory"
/bin/chmod 000 "$unreadable_directory"
assert_checker_status 2 "$unreadable_directory"
/bin/chmod 700 "$unreadable_directory"

echo "Release privacy checker fixtures passed."
