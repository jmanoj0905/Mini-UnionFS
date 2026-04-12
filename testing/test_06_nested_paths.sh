#!/bin/bash
# test_10_nested_paths.sh
# Tests: Files and operations in subdirectories.
# Covers: resolve_path with non-root paths, make_parent_dirs, nested CoW and whiteout

source "$(dirname "$0")/lib.sh"

header "TEST 06: Nested Path Operations"
info "Subdirectory files must support visibility, CoW, whiteout, and creation"

setup_env

mkdir -p "$LOWER_DIR/subdir/deep"
echo "nested_content"    > "$LOWER_DIR/subdir/nested.txt"
echo "deep_content"      > "$LOWER_DIR/subdir/deep/deepfile.txt"
echo "lower_subdir_only" > "$LOWER_DIR/subdir/subdir_only.txt"

if ! mount_fs; then
    teardown_env
    exit 1
fi

section "Nested file visibility"
assert_file_exists "$MOUNT_DIR/subdir/nested.txt"        "subdir/nested.txt visible"
assert_contains    "$MOUNT_DIR/subdir/nested.txt" "nested_content"  "content correct"
assert_file_exists "$MOUNT_DIR/subdir/deep/deepfile.txt" "deep/deepfile.txt visible"
assert_contains    "$MOUNT_DIR/subdir/deep/deepfile.txt" "deep_content"  "deep content correct"

section "CoW on nested file"
echo "modified_nested" >> "$MOUNT_DIR/subdir/nested.txt"

assert_file_exists     "$UPPER_DIR/subdir/nested.txt"                  "CoW copy in upper/subdir/"
assert_contains        "$UPPER_DIR/subdir/nested.txt" "nested_content" "CoW preserves original"
assert_contains        "$UPPER_DIR/subdir/nested.txt" "modified_nested" "CoW copy has new content"
assert_not_contains    "$LOWER_DIR/subdir/nested.txt" "modified_nested" "lower unchanged"

section "Whiteout for nested file"
rm "$MOUNT_DIR/subdir/subdir_only.txt"

assert_file_not_exists "$MOUNT_DIR/subdir/subdir_only.txt"        "nested file hidden"
assert_file_exists     "$UPPER_DIR/subdir/.wh.subdir_only.txt"    "whiteout in correct subdir"
assert_file_exists     "$LOWER_DIR/subdir/subdir_only.txt"        "lower file preserved"

section "Create new nested file"
echo "new_nested" > "$MOUNT_DIR/subdir/new_nested.txt"

assert_file_exists     "$UPPER_DIR/subdir/new_nested.txt"    "new nested file in upper"
assert_file_not_exists "$LOWER_DIR/subdir/new_nested.txt"    "new nested file NOT in lower"
assert_contains        "$MOUNT_DIR/subdir/new_nested.txt" "new_nested"  "content correct"

teardown_env
print_summary
