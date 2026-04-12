#!/bin/bash
# test_08_readdir_merge.sh
# Tests: Directory listing merges both layers with deduplication.
# Covers: unionfs_readdir()

source "$(dirname "$0")/lib.sh"

header "TEST 04: ReadDir Merge and Deduplication"
info "Directory listing must merge layers, deduplicate, and hide whiteouts"

setup_env

echo "la" > "$LOWER_DIR/a.txt"
echo "lb" > "$LOWER_DIR/b.txt"
echo "lc" > "$LOWER_DIR/c_hidden.txt"
echo "ub" > "$UPPER_DIR/b.txt"
echo "ud" > "$UPPER_DIR/d.txt"
touch "$UPPER_DIR/.wh.c_hidden.txt"

if ! mount_fs; then
    teardown_env
    exit 1
fi

listing=$(ls "$MOUNT_DIR")

section "All expected files present"
for f in a.txt b.txt d.txt; do
    echo "$listing" | grep -qx "$f" && pass "$f present" || fail "$f missing from listing"
done

section "No duplicates"
count_b=$(ls "$MOUNT_DIR" | grep -c "^b.txt$")
[ "$count_b" -eq 1 ] && pass "b.txt listed exactly once" || fail "b.txt listed $count_b times"

section "Whited-out and whiteout marker files hidden"
echo "$listing" | grep -q "c_hidden.txt" && fail "c_hidden.txt must be hidden" || pass "c_hidden.txt hidden by whiteout"
echo "$listing" | grep -q "^\.wh\."      && fail ".wh. markers must not appear" || pass "no .wh. markers in listing"

section "Exact listing — no unexpected entries"
unexpected=0
for f in $(ls "$MOUNT_DIR"); do
    case "$f" in
        a.txt|b.txt|d.txt) ;;
        *) echo "  [FAIL] Unexpected entry: $f"; unexpected=1 ;;
    esac
done
[ "$unexpected" -eq 0 ] && pass "listing contains exactly expected files" || ((FAIL_COUNT++))

teardown_env
print_summary
