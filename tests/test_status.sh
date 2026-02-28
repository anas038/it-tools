#!/bin/sh
# test_status.sh — Tests for products/glpi/status.sh
# POSIX sh compliant — no bash-isms
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/test_helper.sh"
. "$PROJECT_ROOT/lib/common.sh"

echo "=== test_status.sh ==="

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
test_start "status_help_exits_0"
_result=0
_output=$(sh "$PROJECT_ROOT/bin/it" glpi status --help 2>&1) || _result=$?
assert_equals "0" "$_result" "--help should exit 0"
assert_contains "$_output" "Usage"
assert_contains "$_output" "Instance"

# ============================================================
# 2. Status always exits 0
# ============================================================
test_start "status_exits_0_always"
_save_conf
rm -f "$_CONF_PATH"
_result=0
sh "$PROJECT_ROOT/bin/it" glpi status 2>/dev/null || _result=$?
assert_equals "0" "$_result" "status should always exit 0"
_restore_conf

# ============================================================
# 3. All sections present in output
# ============================================================
test_start "status_sections_present"
_save_conf
cat > "$_CONF_PATH" << 'TESTCONF'
GLPI_INSTALL_PATH="/tmp"
TESTCONF
_result=0
_output=$(sh "$PROJECT_ROOT/bin/it" glpi status 2>&1) || _result=$?
assert_contains "$_output" "Instance"
assert_contains "$_output" "System"
assert_contains "$_output" "Database"
assert_contains "$_output" "Backup"
_restore_conf

# ============================================================
# 4. --quiet suppresses info output
# ============================================================
test_start "status_quiet_suppresses_info"
_save_conf
cat > "$_CONF_PATH" << 'TESTCONF'
GLPI_INSTALL_PATH="/tmp"
TESTCONF
_result=0
_output=$(sh "$PROJECT_ROOT/bin/it" glpi status --quiet 2>&1) || _result=$?
assert_not_contains "$_output" "Instance"
_restore_conf

test_summary
