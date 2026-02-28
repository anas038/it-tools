#!/bin/sh
# test_backup.sh — Tests for products/glpi/backup.sh
# POSIX sh compliant — no bash-isms
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/test_helper.sh"
. "$PROJECT_ROOT/lib/common.sh"

echo "=== test_backup.sh ==="

_CONF_PATH="$PROJECT_ROOT/products/glpi/glpi.conf"

# Pre-test cleanup: ensure no stale lock
rm -f "$PROJECT_ROOT/logs/glpi-backup.lock"
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
    rm -f "$PROJECT_ROOT/logs/glpi-backup.lock"
}

# ============================================================
# 1. --help exits 0 and shows usage
# ============================================================
test_start "backup_help_exits_0"
_result=0
_output=$(sh "$PROJECT_ROOT/bin/it" glpi backup --help 2>&1) || _result=$?
assert_equals "0" "$_result" "--help should exit 0"
assert_contains "$_output" "Usage"
assert_contains "$_output" "database dump"

# ============================================================
# 2. Missing BACKUP_DEST exits 1 (EXIT_CONFIG)
# ============================================================
test_start "backup_missing_dest_exits_1"
_save_conf
cat > "$_CONF_PATH" << 'TESTCONF'
GLPI_INSTALL_PATH="/tmp"
BACKUP_DEST=""
TESTCONF
_result=0
_output=$(sh "$PROJECT_ROOT/bin/it" glpi backup 2>&1) || _result=$?
assert_equals "1" "$_result" "missing BACKUP_DEST should exit 1"
assert_contains "$_output" "BACKUP_DEST"
_restore_conf

# ============================================================
# 3. Nonexistent dest with dry-run exits 0
# ============================================================
test_start "backup_nonexistent_dest_dry_run"
_save_conf
cat > "$_CONF_PATH" << 'TESTCONF'
BACKUP_DEST="/nonexistent"
GLPI_INSTALL_PATH="/tmp"
BACKUP_VERIFY_MOUNT=false
DB_NAME="testdb"
DB_USER="testuser"
DB_PASS="testpass"
TESTCONF
_result=0
_output=$(sh "$PROJECT_ROOT/bin/it" glpi backup --dry-run 2>&1) || _result=$?
assert_equals "0" "$_result" "dry-run should exit 0"
assert_contains "$_output" "dry-run"
_restore_conf

# ============================================================
# 4. Dry-run shows all 3 steps
# ============================================================
test_start "backup_dry_run_shows_steps"
_save_conf
_tmpdir=$(mktemp -d)
cat > "$_CONF_PATH" << TESTCONF
BACKUP_DEST="$_tmpdir"
GLPI_INSTALL_PATH="/tmp"
BACKUP_VERIFY_MOUNT=false
DB_NAME="testdb"
DB_USER="testuser"
DB_PASS="testpass"
TESTCONF
_result=0
_output=$(sh "$PROJECT_ROOT/bin/it" glpi backup --dry-run 2>&1) || _result=$?
assert_contains "$_output" "Step 1/3"
assert_contains "$_output" "Step 2/3"
assert_contains "$_output" "Step 3/3"
rm -rf "$_tmpdir"
_restore_conf

test_summary
