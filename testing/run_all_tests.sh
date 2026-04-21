#!/bin/bash
# run_all_tests.sh — Mini-UnionFS Complete Test Suite Runner
# Usage: ./testing/run_all_tests.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

TESTS=(
    "test_01_layer_visibility.sh"
    "test_02_cow_write.sh"
    "test_03_whiteout.sh"
    "test_04_create_new_file.sh"
)

BINARY="${FUSE_BINARY:-$PROJECT_DIR/mini_unionfs}"

echo "Mini-UnionFS Test Suite"
echo "  Project : $PROJECT_DIR"
echo "  Binary  : $BINARY"
echo "  Tests   : ${#TESTS[@]} scripts"
echo ""

# Pre-flight
if [ ! -f "$BINARY" ]; then
    echo "[ERROR] Binary not found: $BINARY"
    echo "        Run 'make' in $PROJECT_DIR first"
    echo ""
    echo "Attempting build..."
    if ! make -C "$PROJECT_DIR" 2>&1 | tail -5; then
        echo "[ERROR] Build failed"
        exit 1
    fi
fi

if ! command -v fusermount &>/dev/null; then
    echo "[WARN]  fusermount not found — unmount will fall back to umount"
fi

echo ""

TOTAL=0
PASSED=0
FAILED=0
FAILED_NAMES=()

DIVIDER="------------------------------------------------------------"

for test_script in "${TESTS[@]}"; do
    test_path="$SCRIPT_DIR/$test_script"

    if [ ! -f "$test_path" ]; then
        echo "$DIVIDER"
        echo "[MISSING] $test_script"
        ((FAILED++))
        FAILED_NAMES+=("$test_script (missing)")
        ((TOTAL++))
        continue
    fi

    chmod +x "$test_path"
    ((TOTAL++))

    echo "$DIVIDER"
    bash "$test_path"
    exit_code=$?

    if [ "$exit_code" -eq 0 ]; then
        ((PASSED++))
        echo "  Script result: PASSED"
    else
        ((FAILED++))
        FAILED_NAMES+=("$test_script")
        echo "  Script result: FAILED"
    fi
    echo ""
done

echo "$DIVIDER"
echo "Final Summary"
echo "  Scripts run    : $TOTAL"
echo "  Scripts passed : $PASSED"
echo "  Scripts failed : $FAILED"
echo ""

if [ "${#FAILED_NAMES[@]}" -gt 0 ]; then
    echo "  Failed:"
    for name in "${FAILED_NAMES[@]}"; do
        echo "    - $name"
    done
    echo ""
fi

if [ "$FAILED" -eq 0 ]; then
    echo "  ALL TESTS PASSED"
    exit 0
else
    echo "  SOME TESTS FAILED"
    exit 1
fi
