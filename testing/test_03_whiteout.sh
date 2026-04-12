#!/bin/bash
# test_05_whiteout_lower_only.sh
# Tests: Deleting a lower-only file creates a whiteout marker.
# Covers: unionfs_unlink() PATH B and PATH A (upper-only delete)

source "$(dirname "$0")/lib.sh"

header "TEST 03: Whiteout on Deletion"
info "Deleting a lower file must create a whiteout; deleting an upper-only file must not"

setup_env

echo "to_be_hidden" > "$LOWER_DIR/victim.txt"
echo "keep_me"      > "$LOWER_DIR/innocent.txt"
echo "upper_data"   > "$UPPER_DIR/upper_only.txt"

if ! mount_fs; then
    teardown_env
    exit 1
fi

section "Delete lower-only file creates whiteout"
rm "$MOUNT_DIR/victim.txt"

assert_file_not_exists "$MOUNT_DIR/victim.txt"       "victim.txt hidden after deletion"
assert_file_exists     "$LOWER_DIR/victim.txt"       "lower/victim.txt preserved"
assert_file_exists     "$UPPER_DIR/.wh.victim.txt"   "whiteout marker .wh.victim.txt created"
assert_file_exists     "$MOUNT_DIR/innocent.txt"     "innocent.txt unaffected"

section "Whiteout file hidden from directory listing"
listing=$(ls "$MOUNT_DIR")
echo "$listing" | grep -q "^\.wh\." && fail "whiteout files must not appear in listing" || pass "no .wh. entries in listing"
echo "$listing" | grep -q "victim.txt"  && fail "victim.txt must not appear in listing"  || pass "victim.txt absent from listing"

section "stat on whited-out path returns error"
assert_cmd_fails "stat on whited-out path fails" stat "$MOUNT_DIR/victim.txt"

section "Delete upper-only file — no whiteout created"
rm "$MOUNT_DIR/upper_only.txt"

assert_file_not_exists "$UPPER_DIR/upper_only.txt"       "upper-only file removed"
assert_file_not_exists "$UPPER_DIR/.wh.upper_only.txt"   "no whiteout created for upper-only file"

teardown_env
print_summary
