#!/bin/sh
# test_archive.sh — Tests for products/glpi/archive.sh
# POSIX sh compliant — no bash-isms
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/test_helper.sh"
. "$PROJECT_ROOT/lib/common.sh"

echo "=== test_archive.sh ==="

_CONF_PATH="$PROJECT_ROOT/products/glpi/glpi.conf"

# Pre-test cleanup: ensure no stale lock
rm -f "$PROJECT_ROOT/logs/glpi-archive.lock"
mkdir -p "$PROJECT_ROOT/logs"

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
    rm -f "$PROJECT_ROOT/logs/glpi-archive.lock"
}

# ============================================================
# 1. --help exits 0 and shows usage
# ============================================================
test_start "archive_help_exits_0"
_result=0
_output=$(sh "$PROJECT_ROOT/bin/it" glpi archive --help 2>&1) || _result=$?
assert_equals "0" "$_result" "--help should exit 0"
assert_contains "$_output" "Usage"
assert_contains "$_output" "sqldump"

# ============================================================
# 2. Archive requires backup safety gate
# ============================================================
test_start "archive_requires_backup_safety_gate"
_save_conf
cat > "$_CONF_PATH" << 'TESTCONF'
GLPI_INSTALL_PATH="/tmp"
BACKUP_DEST="/nonexistent"
TESTCONF
_result=0
_output=$(sh "$PROJECT_ROOT/bin/it" glpi archive 2>&1) || _result=$?
assert_equals "7" "$_result" "missing backup should exit 7"
assert_contains "$_output" "Backup"
_restore_conf

# ============================================================
# 3. --months flag accepted in help
# ============================================================
test_start "archive_months_flag_accepted"
_result=0
_output=$(sh "$PROJECT_ROOT/bin/it" glpi archive --help 2>&1) || _result=$?
assert_contains "$_output" "--months"

test_summary
