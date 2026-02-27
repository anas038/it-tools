#!/bin/sh
# test_restore.sh — Tests for products/glpi/restore.sh
# POSIX sh compliant — no bash-isms
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/test_helper.sh"
. "$PROJECT_ROOT/lib/common.sh"

echo "=== test_restore.sh ==="

# Pre-test cleanup: ensure no stale lock
rm -f "$PROJECT_ROOT/logs/glpi-restore.lock"
mkdir -p "$PROJECT_ROOT/logs"

# ============================================================
# 1. --help exits 0 and shows usage
# ============================================================
test_start "restore_help_exits_0"
_result=0
_output=$(sh "$PROJECT_ROOT/bin/it" glpi restore --help 2>&1) || _result=$?
assert_equals "0" "$_result" "--help should exit 0"
assert_contains "$_output" "Usage"
assert_contains "$_output" "--backup"
assert_contains "$_output" "--db"

# ============================================================
# 2. Nonexistent backup path exits 5 (EXIT_FILESYSTEM)
# ============================================================
test_start "restore_nonexistent_backup_exits_5"
_result=0
sh "$PROJECT_ROOT/bin/it" glpi restore --backup /nonexistent/path 2>/dev/null || _result=$?
assert_equals "5" "$_result" "nonexistent backup should exit 5"

# ============================================================
# 3. Partial backup exits 7 (EXIT_SAFETY)
# ============================================================
test_start "restore_partial_backup_exits_7"
_tmpdir=$(mktemp -d)
touch "$_tmpdir/.partial"
touch "$_tmpdir/glpi-db-2026-02-26-020000.sql.gz"
_result=0
sh "$PROJECT_ROOT/bin/it" glpi restore --backup "$_tmpdir" 2>/dev/null || _result=$?
assert_equals "7" "$_result" "partial backup should exit 7"
rm -rf "$_tmpdir"

# ============================================================
# 4. Empty backup dir exits 5 (EXIT_FILESYSTEM, no archives)
# ============================================================
test_start "restore_empty_backup_exits_5"
_tmpdir=$(mktemp -d)
_result=0
sh "$PROJECT_ROOT/bin/it" glpi restore --backup "$_tmpdir" 2>/dev/null || _result=$?
assert_equals "5" "$_result" "empty backup dir should exit 5"
rm -rf "$_tmpdir"

# ============================================================
# 5. Dry-run with valid backup exits 0 and shows plan
# ============================================================
test_start "restore_dry_run_exits_0"
_tmpdir=$(mktemp -d)
touch "$_tmpdir/glpi-db-2026-02-26-020000.sql.gz"
touch "$_tmpdir/glpi-files-2026-02-26-020000.tar.gz"
touch "$_tmpdir/glpi-webroot-2026-02-26-020000.tar.gz"
_result=0
_output=$(sh "$PROJECT_ROOT/bin/it" glpi restore --backup "$_tmpdir" --dry-run 2>&1) || _result=$?
assert_equals "0" "$_result" "dry-run should exit 0"
assert_contains "$_output" "Restore plan"
assert_contains "$_output" "database, files, webroot"
rm -rf "$_tmpdir"

# ============================================================
# 6. --db flag selects only database component
# ============================================================
test_start "restore_db_only_flag"
_tmpdir=$(mktemp -d)
touch "$_tmpdir/glpi-db-2026-02-26-020000.sql.gz"
touch "$_tmpdir/glpi-files-2026-02-26-020000.tar.gz"
touch "$_tmpdir/glpi-webroot-2026-02-26-020000.tar.gz"
_result=0
_output=$(sh "$PROJECT_ROOT/bin/it" glpi restore --backup "$_tmpdir" --db --dry-run 2>&1) || _result=$?
assert_contains "$_output" "database"
assert_not_contains "$_output" "files"
assert_not_contains "$_output" "webroot"
rm -rf "$_tmpdir"

# ============================================================
# 7. --files --webroot flags select files and webroot
# ============================================================
test_start "restore_files_webroot_flags"
_tmpdir=$(mktemp -d)
touch "$_tmpdir/glpi-db-2026-02-26-020000.sql.gz"
touch "$_tmpdir/glpi-files-2026-02-26-020000.tar.gz"
touch "$_tmpdir/glpi-webroot-2026-02-26-020000.tar.gz"
_result=0
_output=$(sh "$PROJECT_ROOT/bin/it" glpi restore --backup "$_tmpdir" --files --webroot --dry-run 2>&1) || _result=$?
assert_contains "$_output" "files"
assert_contains "$_output" "webroot"
assert_not_contains "$_output" "database"
rm -rf "$_tmpdir"

# ============================================================
# 8. Partial backup error message contains "partial"
# ============================================================
test_start "restore_partial_error_message"
_tmpdir=$(mktemp -d)
touch "$_tmpdir/.partial"
touch "$_tmpdir/glpi-db-2026-02-26-020000.sql.gz"
_result=0
_output=$(sh "$PROJECT_ROOT/bin/it" glpi restore --backup "$_tmpdir" 2>&1) || _result=$?
assert_contains "$_output" "partial"
rm -rf "$_tmpdir"

test_summary
