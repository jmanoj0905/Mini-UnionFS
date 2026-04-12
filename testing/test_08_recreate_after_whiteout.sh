#!/bin/bash
# test_14_recreate_after_whiteout.sh
# Tests: Re-creating a file after deletion clears the whiteout marker.
# Covers: unionfs_create() whiteout clearing, unionfs_mkdir() regression

source "$(dirname "$0")/lib.sh"

header "TEST 08: Re-create After Whiteout"
info "Re-creating a deleted file must clear the stale whiteout"

setup_env

echo "original" > "$LOWER_DIR/phoenix.txt"

if ! mount_fs; then
    teardown_env
    exit 1
fi

section "Delete creates whiteout"
rm "$MOUNT_DIR/phoenix.txt"

assert_file_exists     "$UPPER_DIR/.wh.phoenix.txt"    "whiteout created"
assert_file_not_exists "$MOUNT_DIR/phoenix.txt"        "file hidden"
assert_file_exists     "$LOWER_DIR/phoenix.txt"        "lower preserved"

section "Re-create clears whiteout"
echo "reborn_content" > "$MOUNT_DIR/phoenix.txt"

assert_file_not_exists "$UPPER_DIR/.wh.phoenix.txt"             "stale whiteout cleared"
assert_file_exists     "$MOUNT_DIR/phoenix.txt"                 "file visible after re-create"
assert_contains        "$MOUNT_DIR/phoenix.txt" "reborn_content" "new content correct"
assert_not_contains    "$MOUNT_DIR/phoenix.txt" "original"       "old content not visible"

section "Repeated delete/re-create cycle"
rm "$MOUNT_DIR/phoenix.txt"
assert_file_not_exists "$MOUNT_DIR/phoenix.txt"        "hidden after second delete"
assert_file_exists     "$UPPER_DIR/.wh.phoenix.txt"    "whiteout re-established"

echo "third_life" > "$MOUNT_DIR/phoenix.txt"
assert_file_exists     "$MOUNT_DIR/phoenix.txt"        "visible after third creation"
assert_contains        "$MOUNT_DIR/phoenix.txt" "third_life"  "third content correct"
assert_file_not_exists "$UPPER_DIR/.wh.phoenix.txt"    "whiteout cleared again"

section "mkdir re-create regression check"
mkdir "$MOUNT_DIR/new_dir" 2>/dev/null
rmdir "$MOUNT_DIR/new_dir" 2>/dev/null
mkdir "$MOUNT_DIR/new_dir" 2>/dev/null
assert_file_exists "$MOUNT_DIR/new_dir"                "mkdir re-create works"

teardown_env
print_summary
