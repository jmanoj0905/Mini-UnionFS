#!/bin/bash
# test_04_create_new_file.sh
# Tests: Creating a new file through the mount goes to upper layer only.
# Covers: unionfs_create(), unionfs_write(), unionfs_release()

source "$(dirname "$0")/lib.sh"

header "TEST 04: New File Creation"
info "New files created through mount must land in upper layer only"

setup_env

echo "lower_existing" > "$LOWER_DIR/existing.txt"

if ! mount_fs; then
    teardown_env
    exit 1
fi

section "Create via redirect"
echo "brand_new_content" > "$MOUNT_DIR/brand_new.txt"

assert_file_exists     "$UPPER_DIR/brand_new.txt"          "new file in upper"
assert_file_not_exists "$LOWER_DIR/brand_new.txt"          "new file NOT in lower"
assert_contains        "$MOUNT_DIR/brand_new.txt" "brand_new_content"  "content correct"

section "Create empty file with touch"
touch "$MOUNT_DIR/empty_file.txt"
assert_file_exists     "$UPPER_DIR/empty_file.txt"         "empty file in upper"
assert_file_not_exists "$LOWER_DIR/empty_file.txt"         "empty file NOT in lower"

section "Multiple file creation"
for i in 1 2 3; do
    echo "content_$i" > "$MOUNT_DIR/multi_$i.txt"
    assert_file_exists     "$UPPER_DIR/multi_$i.txt"   "multi_$i.txt in upper"
    assert_file_not_exists "$LOWER_DIR/multi_$i.txt"   "multi_$i.txt NOT in lower"
done

section "Pre-existing lower file not CoW'd until written"
assert_contains        "$MOUNT_DIR/existing.txt" "lower_existing"  "lower file readable"
assert_file_not_exists "$UPPER_DIR/existing.txt"                   "no CoW copy of untouched lower file"

teardown_env
print_summary
