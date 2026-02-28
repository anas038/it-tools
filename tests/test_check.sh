#!/bin/sh
# test_check.sh — Tests for products/glpi/check.sh
# POSIX sh compliant — no bash-isms
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/test_helper.sh"
. "$PROJECT_ROOT/lib/common.sh"

echo "=== test_check.sh ==="

_CONF_PATH="$PROJECT_ROOT/products/glpi/glpi.conf"

# ---- Config backup/restore helpers ----
_SAVED_CONF=""
_save_conf() {
    _SAVED_CONF=""
    if [ -f "$_CONF_PATH" ]; then
        _SAVED_CONF=$(mktemp)
        cp "$_CONF_PATH" "$_SAVED_CONF"
    fi
}
_restore_conf() {
    if [ -n "$_SAVED_CONF" ]; then
        cp "$_SAVED_CONF" "$_CONF_PATH"
        rm -f "$_SAVED_CONF"
    else
        rm -f "$_CONF_PATH"
    fi
}

# ============================================================
# 1. --help exits 0 and shows usage
# ============================================================
test_start "check_help_exits_0"
_result=0
_output=$(sh "$PROJECT_ROOT/bin/it" glpi check --help 2>&1) || _result=$?
assert_equals "0" "$_result" "--help should exit 0"
assert_contains "$_output" "Usage"
assert_contains "$_output" "Dependencies"

# ============================================================
# 2. Missing config reports FAIL
# ============================================================
test_start "check_missing_config_reports_fail"
_save_conf
rm -f "$_CONF_PATH"
_result=0
_output=$(sh "$PROJECT_ROOT/bin/it" glpi check 2>&1) || _result=$?
assert_contains "$_output" "[FAIL]"
assert_contains "$_output" "Config file not found"
_restore_conf

# ============================================================
# 3. Invalid syntax reports FAIL
# ============================================================
test_start "check_invalid_syntax_reports_fail"
_save_conf
cat > "$_CONF_PATH" << 'TESTCONF'
GLPI_URL="unclosed
TESTCONF
_result=0
_output=$(sh "$PROJECT_ROOT/bin/it" glpi check 2>&1) || _result=$?
assert_contains "$_output" "[FAIL]"
assert_contains "$_output" "syntax"
_restore_conf

# ============================================================
# 4. All 5 sections present
# ============================================================
test_start "check_all_sections_present"
_save_conf
cat > "$_CONF_PATH" << 'TESTCONF'
GLPI_INSTALL_PATH="/tmp"
TESTCONF
_result=0
_output=$(sh "$PROJECT_ROOT/bin/it" glpi check 2>&1) || _result=$?
assert_contains "$_output" "Config File"
assert_contains "$_output" "Dependencies"
assert_contains "$_output" "Paths"
assert_contains "$_output" "Database"
assert_contains "$_output" "Config Values"
_restore_conf

# ============================================================
# 5. Summary line present
# ============================================================
test_start "check_summary_present"
_save_conf
cat > "$_CONF_PATH" << 'TESTCONF'
GLPI_INSTALL_PATH="/tmp"
TESTCONF
_result=0
_output=$(sh "$PROJECT_ROOT/bin/it" glpi check 2>&1) || _result=$?
assert_contains "$_output" "Summary:"
assert_contains "$_output" "passed"
assert_contains "$_output" "warnings"
assert_contains "$_output" "failed"
_restore_conf

# ============================================================
# 6. Bad ARCHIVE_MODE reports FAIL
# ============================================================
test_start "check_bad_archive_mode"
_save_conf
cat > "$_CONF_PATH" << 'TESTCONF'
ARCHIVE_MODE="badvalue"
GLPI_INSTALL_PATH="/tmp"
TESTCONF
_result=0
_output=$(sh "$PROJECT_ROOT/bin/it" glpi check 2>&1) || _result=$?
assert_contains "$_output" "[FAIL]"
assert_contains "$_output" "ARCHIVE_MODE"
_restore_conf

# ============================================================
# 7. Bad LOG_LEVEL reports FAIL
# ============================================================
test_start "check_bad_log_level"
_save_conf
cat > "$_CONF_PATH" << 'TESTCONF'
LOG_LEVEL="badlevel"
GLPI_INSTALL_PATH="/tmp"
TESTCONF
_result=0
_output=$(sh "$PROJECT_ROOT/bin/it" glpi check 2>&1) || _result=$?
assert_contains "$_output" "[FAIL]"
assert_contains "$_output" "LOG_LEVEL"
_restore_conf

# ============================================================
# 8. Nonexistent path reports FAIL
# ============================================================
test_start "check_nonexistent_path_fails"
_save_conf
cat > "$_CONF_PATH" << 'TESTCONF'
GLPI_INSTALL_PATH="/nonexistent/path"
TESTCONF
_result=0
_output=$(sh "$PROJECT_ROOT/bin/it" glpi check 2>&1) || _result=$?
assert_contains "$_output" "[FAIL]"
assert_contains "$_output" "GLPI_INSTALL_PATH"
_restore_conf

# ============================================================
# 9. Valid minimal config runs to completion
# ============================================================
test_start "check_valid_minimal_config_runs"
_save_conf
cat > "$_CONF_PATH" << 'TESTCONF'
GLPI_INSTALL_PATH="/tmp"
TESTCONF
_result=0
_output=$(sh "$PROJECT_ROOT/bin/it" glpi check 2>&1) || _result=$?
assert_contains "$_output" "Summary:"
_restore_conf

# ============================================================
# 10. --quiet suppresses OK lines
# ============================================================
test_start "check_quiet_suppresses_ok"
_save_conf
cat > "$_CONF_PATH" << 'TESTCONF'
GLPI_INSTALL_PATH="/tmp"
TESTCONF
_result=0
_output=$(sh "$PROJECT_ROOT/bin/it" glpi check --quiet 2>&1) || _result=$?
assert_not_contains "$_output" "[OK]"
_restore_conf

test_summary
