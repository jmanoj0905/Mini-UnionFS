#!/bin/bash
# test_11_directory_ops.sh
# Tests: mkdir and rmdir operations.
# Covers: unionfs_mkdir(), unionfs_rmdir()

source "$(dirname "$0")/lib.sh"

header "TEST 07: Directory Operations"
info "mkdir goes to upper; rmdir depends on whether dir exists in lower"

setup_env

mkdir -p "$LOWER_DIR/lower_dir"
echo "file_in_lower_dir" > "$LOWER_DIR/lower_dir/file.txt"

if ! mount_fs; then
    teardown_env
    exit 1
fi

section "mkdir creates in upper only"
mkdir "$MOUNT_DIR/brand_new_dir"

assert_file_exists     "$UPPER_DIR/brand_new_dir"     "new dir in upper"
assert_file_not_exists "$LOWER_DIR/brand_new_dir"     "new dir NOT in lower"
assert_file_exists     "$MOUNT_DIR/brand_new_dir"     "new dir visible in mount"

section "Files inside new dir go to upper"
echo "in_new_dir" > "$MOUNT_DIR/brand_new_dir/child.txt"
assert_file_exists     "$UPPER_DIR/brand_new_dir/child.txt"  "child file in upper"
assert_file_not_exists "$LOWER_DIR/brand_new_dir/child.txt"  "child file NOT in lower"

section "rmdir upper-only directory"
rm "$MOUNT_DIR/brand_new_dir/child.txt"
rmdir "$MOUNT_DIR/brand_new_dir"

assert_file_not_exists "$UPPER_DIR/brand_new_dir"         "upper-only dir removed"
assert_file_not_exists "$MOUNT_DIR/brand_new_dir"         "dir gone from mount"
assert_file_not_exists "$UPPER_DIR/.wh.brand_new_dir"     "no whiteout for upper-only dir"

section "Lower-only directory visible with contents"
assert_file_exists "$MOUNT_DIR/lower_dir"              "lower_dir visible"
listing=$(ls "$MOUNT_DIR/lower_dir")
echo "$listing" | grep -q "file.txt" && pass "lower_dir contents visible" || fail "lower_dir contents not visible"

section "rmdir on lower-only directory returns EPERM"
rmdir "$MOUNT_DIR/lower_dir" 2>/dev/null
rc=$?
[ "$rc" -ne 0 ] && pass "rmdir on lower-only dir denied (EPERM)" || fail "rmdir on lower-only dir should have failed"

teardown_env
print_summary
