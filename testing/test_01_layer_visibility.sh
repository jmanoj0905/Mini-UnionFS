#!/bin/bash
# test_01_layer_visibility.sh
# Tests: files from lower and upper layers are visible through the mount point.
# Covers: unionfs_getattr, unionfs_read, resolve_path

source "$(dirname "$0")/lib.sh"

header "TEST 01: Layer Visibility"
info "Files from both layers must appear under the mount point"

setup_env

echo "content_from_lower" > "$LOWER_DIR/lower_file.txt"
echo "content_from_upper" > "$UPPER_DIR/upper_file.txt"
echo "shared_lower_version" > "$LOWER_DIR/shared.txt"

if ! mount_fs; then
    teardown_env
    exit 1
fi

section "Lower layer visibility"
assert_file_exists "$MOUNT_DIR/lower_file.txt"         "lower_file.txt visible through mount"
assert_contains    "$MOUNT_DIR/lower_file.txt" "content_from_lower"  "lower_file.txt content correct"

section "Upper layer visibility"
assert_file_exists "$MOUNT_DIR/upper_file.txt"         "upper_file.txt visible through mount"
assert_contains    "$MOUNT_DIR/upper_file.txt" "content_from_upper"  "upper_file.txt content correct"

section "Upper shadows lower for same filename"
echo "upper_version" > "$UPPER_DIR/shared.txt"
assert_contains    "$MOUNT_DIR/shared.txt" "upper_version"       "mount shows upper version when both layers have same file"
assert_not_contains "$MOUNT_DIR/shared.txt" "shared_lower_version" "lower version not shown when upper exists"
assert_contains    "$LOWER_DIR/shared.txt" "shared_lower_version"  "lower file itself unchanged"

section "Non-existent file returns error"
assert_cmd_fails "stat on missing file fails" stat "$MOUNT_DIR/does_not_exist.txt"

teardown_env
print_summary
