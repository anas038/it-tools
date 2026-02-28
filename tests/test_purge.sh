#!/bin/sh
# test_purge.sh — Tests for products/glpi/purge.sh
# POSIX sh compliant — no bash-isms
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/test_helper.sh"
. "$PROJECT_ROOT/lib/common.sh"

echo "=== test_purge.sh ==="

_CONF_PATH="$PROJECT_ROOT/products/glpi/glpi.conf"

# Pre-test cleanup: ensure no stale lock
rm -f "$PROJECT_ROOT/logs/glpi-purge.lock"
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
    rm -f "$PROJECT_ROOT/logs/glpi-purge.lock"
}

# ============================================================
# 1. --help exits 0 and shows usage
# ============================================================
test_start "purge_help_exits_0"
_result=0
_output=$(sh "$PROJECT_ROOT/bin/it" glpi purge --help 2>&1) || _result=$?
assert_equals "0" "$_result" "--help should exit 0"
assert_contains "$_output" "Usage"
assert_contains "$_output" "PURGE_CLOSED_TICKETS_MONTHS"

# ============================================================
# 2. Purge requires backup safety gate
# ============================================================
test_start "purge_requires_backup_safety_gate"
_save_conf
cat > "$_CONF_PATH" << 'TESTCONF'
GLPI_INSTALL_PATH="/tmp"
BACKUP_DEST="/nonexistent"
TESTCONF
_result=0
_output=$(sh "$PROJECT_ROOT/bin/it" glpi purge 2>&1) || _result=$?
assert_equals "7" "$_result" "missing backup should exit 7"
assert_contains "$_output" "Backup"
_restore_conf

# ============================================================
# 3. Dry-run with no thresholds (all default 0)
# ============================================================
test_start "purge_dry_run_with_no_thresholds"
_save_conf
_tmpdir=$(mktemp -d)
touch "$_tmpdir/recent-backup.tar.gz"
cat > "$_CONF_PATH" << TESTCONF
GLPI_INSTALL_PATH="/tmp"
BACKUP_DEST="$_tmpdir"
DB_NAME="testdb"
DB_USER="testuser"
DB_PASS="testpass"
TESTCONF
_result=0
_output=$(sh "$PROJECT_ROOT/bin/it" glpi purge --dry-run 2>&1) || _result=$?
assert_equals "0" "$_result" "dry-run with no thresholds should exit 0"
rm -rf "$_tmpdir"
_restore_conf

test_summary
