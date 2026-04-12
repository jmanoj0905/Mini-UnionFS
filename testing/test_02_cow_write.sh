#!/bin/bash
# test_03_cow_write.sh
# Tests: Copy-on-Write when writing to a lower-layer file.
# Covers: cow_copy(), unionfs_open(), unionfs_write(), unionfs_truncate()

source "$(dirname "$0")/lib.sh"

header "TEST 02: Copy-on-Write"
info "Writing or truncating a lower-layer file must copy it to upper first"

setup_env

echo "original_content" > "$LOWER_DIR/cow_target.txt"
printf 'ABCDEFGHIJ' > "$LOWER_DIR/trunc_target.txt"   # 10 bytes
echo "upper_existing" > "$UPPER_DIR/upper_only.txt"

if ! mount_fs; then
    teardown_env
    exit 1
fi

section "CoW triggered on append"
echo "appended_line" >> "$MOUNT_DIR/cow_target.txt"

assert_file_exists     "$UPPER_DIR/cow_target.txt"                     "CoW copy created in upper"
assert_contains        "$UPPER_DIR/cow_target.txt" "original_content"  "CoW copy preserved original"
assert_contains        "$UPPER_DIR/cow_target.txt" "appended_line"     "CoW copy has appended content"
assert_not_contains    "$LOWER_DIR/cow_target.txt" "appended_line"     "lower file unchanged"
assert_contains        "$MOUNT_DIR/cow_target.txt" "appended_line"     "mount shows new content"

section "CoW triggered on overwrite"
echo "overwritten" > "$MOUNT_DIR/cow_target.txt"
assert_contains        "$MOUNT_DIR/cow_target.txt" "overwritten"       "mount shows overwritten content"
assert_not_contains    "$LOWER_DIR/cow_target.txt" "overwritten"       "lower file unaffected by overwrite"

section "CoW triggered on truncate"
truncate -s 5 "$MOUNT_DIR/trunc_target.txt" 2>/dev/null

assert_file_exists "$UPPER_DIR/trunc_target.txt"   "CoW copy created on truncate"

upper_size=$(stat -c '%s' "$UPPER_DIR/trunc_target.txt" 2>/dev/null)
lower_size=$(stat -c '%s' "$LOWER_DIR/trunc_target.txt" 2>/dev/null)
mount_size=$(stat -c '%s' "$MOUNT_DIR/trunc_target.txt" 2>/dev/null)

[ "$upper_size" = "5" ]  && pass "upper truncated to 5 bytes"  || fail "upper size wrong (got $upper_size)"
[ "$lower_size" = "10" ] && pass "lower unchanged at 10 bytes"  || fail "lower size wrong (got $lower_size)"
[ "$mount_size" = "5" ]  && pass "mount shows 5 bytes"          || fail "mount size wrong (got $mount_size)"

section "Writing upper-only file (no CoW needed)"
echo "modified_upper" >> "$MOUNT_DIR/upper_only.txt"
assert_contains "$UPPER_DIR/upper_only.txt" "upper_existing"   "original content preserved"
assert_contains "$UPPER_DIR/upper_only.txt" "modified_upper"   "upper file directly modified"

teardown_env
print_summary
