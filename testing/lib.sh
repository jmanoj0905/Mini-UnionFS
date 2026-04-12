#!/bin/bash
# lib.sh — Shared test utilities for Mini-UnionFS test suite

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FUSE_BINARY="${FUSE_BINARY:-$SCRIPT_DIR/../mini_unionfs}"

PASS_COUNT=0
FAIL_COUNT=0
TEST_ENV=""

# ── Reporting ────────────────────────────────────────────────────────────────

pass() {
    echo "  [PASS] $1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
    echo "  [FAIL] $1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

info() {
    echo "  [INFO] $1"
}

header() {
    echo ""
    echo "=== $1 ==="
}

section() {
    echo ""
    echo "  -- $1"
}

# ── Environment ───────────────────────────────────────────────────────────────

setup_env() {
    TEST_ENV=$(mktemp -d /tmp/unionfs_test_XXXXXX)
    LOWER_DIR="$TEST_ENV/lower"
    UPPER_DIR="$TEST_ENV/upper"
    MOUNT_DIR="$TEST_ENV/mnt"
    mkdir -p "$LOWER_DIR" "$UPPER_DIR" "$MOUNT_DIR"
    export LOWER_DIR UPPER_DIR MOUNT_DIR TEST_ENV
}

mount_fs() {
    "$FUSE_BINARY" "$LOWER_DIR" "$UPPER_DIR" "$MOUNT_DIR" 2>/dev/null
    sleep 1
    if ! mountpoint -q "$MOUNT_DIR" 2>/dev/null; then
        echo "  [ERROR] Failed to mount filesystem"
        return 1
    fi
    return 0
}

unmount_fs() {
    if mountpoint -q "$MOUNT_DIR" 2>/dev/null; then
        fusermount -u "$MOUNT_DIR" 2>/dev/null || umount "$MOUNT_DIR" 2>/dev/null
        sleep 0.3
    fi
}

teardown_env() {
    unmount_fs
    rm -rf "$TEST_ENV"
}

print_summary() {
    local total=$((PASS_COUNT + FAIL_COUNT))
    echo ""
    echo "  Results: $PASS_COUNT passed, $FAIL_COUNT failed  ($total total)"
    if [ "$FAIL_COUNT" -eq 0 ]; then
        echo "  All tests passed"
        return 0
    else
        echo "  $FAIL_COUNT test(s) failed"
        return 1
    fi
}

# ── Assertions ────────────────────────────────────────────────────────────────

assert_file_exists() {
    local path="$1" msg="$2"
    if [ -e "$path" ]; then
        pass "$msg"
    else
        fail "$msg  (expected '$path' to exist)"
    fi
}

assert_file_not_exists() {
    local path="$1" msg="$2"
    if [ ! -e "$path" ]; then
        pass "$msg"
    else
        fail "$msg  (expected '$path' to NOT exist)"
    fi
}

assert_contains() {
    local path="$1" pattern="$2" msg="$3"
    if grep -q "$pattern" "$path" 2>/dev/null; then
        pass "$msg"
    else
        fail "$msg  (pattern '$pattern' not found in '$path')"
    fi
}

assert_not_contains() {
    local path="$1" pattern="$2" msg="$3"
    if ! grep -q "$pattern" "$path" 2>/dev/null; then
        pass "$msg"
    else
        fail "$msg  (pattern '$pattern' unexpectedly found in '$path')"
    fi
}

assert_cmd_fails() {
    local msg="$1"
    shift
    if ! "$@" 2>/dev/null; then
        pass "$msg"
    else
        fail "$msg  (command '$*' should have failed)"
    fi
}

assert_mode() {
    local path="$1" expected="$2" msg="$3"
    local actual
    actual=$(stat -c '%a' "$path" 2>/dev/null)
    if [ "$actual" = "$expected" ]; then
        pass "$msg"
    else
        fail "$msg  (expected mode $expected, got $actual)"
    fi
}
