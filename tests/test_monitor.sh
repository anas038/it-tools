#!/bin/sh
# test_monitor.sh — Tests for products/glpi/monitor.sh
# POSIX sh compliant — no bash-isms
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/test_helper.sh"
. "$PROJECT_ROOT/lib/common.sh"

echo "=== test_monitor.sh ==="

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
test_start "monitor_help_exits_0"
_result=0
_output=$(sh "$PROJECT_ROOT/bin/it" glpi monitor --help 2>&1) || _result=$?
assert_equals "0" "$_result" "--help should exit 0"
assert_contains "$_output" "Usage"
assert_contains "$_output" "DNS"
assert_contains "$_output" "SSL certificate expiry"

# ============================================================
# 2. Monitor runs without config
# ============================================================
test_start "monitor_runs_without_config"
_save_conf
rm -f "$_CONF_PATH"
_result=0
_output=$(sh "$PROJECT_ROOT/bin/it" glpi monitor 2>&1) || _result=$?
assert_contains "$_output" "health check"
_restore_conf

# ============================================================
# 3. All check names present in output
# ============================================================
test_start "monitor_all_check_names_present"
_save_conf
cat > "$_CONF_PATH" << 'TESTCONF'
GLPI_URL="https://localhost"
GLPI_INSTALL_PATH="/tmp"
TESTCONF
_result=0
_output=$(sh "$PROJECT_ROOT/bin/it" glpi monitor 2>&1) || _result=$?
assert_contains "$_output" "DNS"
assert_contains "$_output" "HTTP"
assert_contains "$_output" "Service"
assert_contains "$_output" "Disk"
_restore_conf

# ============================================================
# 4. --quiet suppresses OK messages
# ============================================================
test_start "monitor_quiet_suppresses_ok"
_save_conf
rm -f "$_CONF_PATH"
_result=0
_output=$(sh "$PROJECT_ROOT/bin/it" glpi monitor --quiet 2>&1) || _result=$?
assert_not_contains "$_output" "OK:"
_restore_conf

# ============================================================
# 5. SSL check skipped for HTTP URLs
# ============================================================
test_start "monitor_ssl_skipped_for_http"
_save_conf
cat > "$_CONF_PATH" << 'TESTCONF'
GLPI_URL="http://example.com"
GLPI_INSTALL_PATH="/tmp"
TESTCONF
_result=0
_output=$(sh "$PROJECT_ROOT/bin/it" glpi monitor --verbose 2>&1) || _result=$?
assert_contains "$_output" "not HTTPS"
_restore_conf

# ============================================================
# 6. Recovery state file created on failure
# ============================================================
test_start "monitor_recovery_state_created"
_save_conf
cat > "$_CONF_PATH" << 'TESTCONF'
GLPI_URL="https://localhost"
GLPI_INSTALL_PATH="/tmp"
TESTCONF
_state_file="/tmp/.monitor_failure_state"
rm -f "$_state_file"
_result=0
sh "$PROJECT_ROOT/bin/it" glpi monitor 2>/dev/null || _result=$?
# Monitor will fail on dev env (DNS, HTTP, services not running)
if [ "$_result" -ne 0 ]; then
    assert_file_exists "$_state_file"
else
    # If monitor somehow passes, state file should NOT exist
    _test_pass
fi
rm -f "$_state_file"
_restore_conf

test_summary
