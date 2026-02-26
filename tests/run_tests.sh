#!/bin/sh
# run_tests.sh — Test runner for it-tools
# POSIX sh compliant — no bash-isms

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
TOTAL_FILES=0
TOTAL_PASSED=0
TOTAL_FAILED=0

echo "==============================="
echo "  it-tools test runner"
echo "==============================="
echo ""

# Find all test_*.sh files in the tests directory
found_tests=0
for test_file in "$TESTS_DIR"/test_*.sh; do
    # Guard against no matches (glob returns literal pattern)
    [ -f "$test_file" ] || continue
    found_tests=1

    TOTAL_FILES=$(( TOTAL_FILES + 1 ))
    file_name="$(basename "$test_file")"

    echo "--- Running: ${file_name} ---"
    if sh "$test_file"; then
        echo "  => ${file_name}: OK"
        TOTAL_PASSED=$(( TOTAL_PASSED + 1 ))
    else
        echo "  => ${file_name}: FAILED"
        TOTAL_FAILED=$(( TOTAL_FAILED + 1 ))
    fi
    echo ""
done

if [ "$found_tests" -eq 0 ]; then
    echo "No test files found (tests/test_*.sh)"
    echo ""
fi

echo "==============================="
echo "  Total files: ${TOTAL_FILES}"
echo "  Passed:      ${TOTAL_PASSED}"
echo "  Failed:      ${TOTAL_FAILED}"
echo "==============================="

if [ "$TOTAL_FAILED" -gt 0 ]; then
    exit 1
fi

exit 0
