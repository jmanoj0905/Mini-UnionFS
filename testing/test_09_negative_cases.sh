#!/bin/bash
# test_15_negative_cases.sh
# Tests: Error-path behaviour — ENOENT for missing/whited-out paths.
# Covers: resolve_path -ENOENT, unlink on non-existent file

source "$(dirname "$0")/lib.sh"

header "TEST 09: Negative / Error Cases"
info "Operations on non-existent paths must fail gracefully"

setup_env

echo "real_file" > "$LOWER_DIR/real.txt"

if ! mount_fs; then
    teardown_env
    exit 1
fi

section "stat/read/delete non-existent file"
assert_cmd_fails "stat on missing file fails"  stat "$MOUNT_DIR/ghost.txt"
assert_cmd_fails "cat on missing file fails"   cat  "$MOUNT_DIR/ghost.txt"

rm_exit=0
rm "$MOUNT_DIR/ghost.txt" 2>/dev/null || rm_exit=$?
[ "$rm_exit" -ne 0 ] && pass "rm on missing file fails" || fail "rm on missing file should fail"

section "Write to path where parent dir does not exist"
write_exit=0
echo "data" > "$MOUNT_DIR/no_such_dir/file.txt" 2>/dev/null || write_exit=$?
[ "$write_exit" -ne 0 ] && pass "write to missing parent dir fails" || fail "write to missing parent should fail"

section "Read empty file returns empty content"
touch "$LOWER_DIR/empty.txt"
result=$(cat "$MOUNT_DIR/empty.txt" 2>/dev/null)
[ -z "$result" ] && pass "empty file returns empty content" || fail "empty file returned unexpected: '$result'"

section "stat on pre-whited-out path fails"
echo "hidden" > "$LOWER_DIR/hidden.txt"
touch "$UPPER_DIR/.wh.hidden.txt"
assert_cmd_fails "stat on pre-whited-out path fails" stat "$MOUNT_DIR/hidden.txt"

section "Real file accessible throughout"
assert_file_exists "$MOUNT_DIR/real.txt"              "real.txt accessible"
assert_contains    "$MOUNT_DIR/real.txt" "real_file"  "real.txt content correct"

teardown_env
print_summary
