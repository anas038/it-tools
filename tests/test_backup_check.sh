#!/bin/sh
# test_backup_check.sh — Tests for lib/backup_check.sh
# POSIX sh compliant — no bash-isms
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/test_helper.sh"
. "$PROJECT_ROOT/lib/common.sh"
. "$PROJECT_ROOT/lib/backup_check.sh"

echo "=== test_backup_check.sh ==="

_TEST_DIR=$(mktemp -d)

# ============================================================
# 1. Recent backup passes
# ============================================================
test_start "recent_backup_passes"
BACKUP_DEST="$_TEST_DIR"
BACKUP_MAX_AGE_HOURS=24
REQUIRE_RECENT_BACKUP=true
touch "$_TEST_DIR/glpi-backup-2026-02-26-020000.tar.gz"
_result=0
check_recent_backup || _result=$?
assert_equals "0" "$_result" "recent backup should pass"

# ============================================================
# 2. No backup exists — fails with EXIT_SAFETY
# ============================================================
test_start "no_backup_fails"
_empty_dir=$(mktemp -d)
BACKUP_DEST="$_empty_dir"
BACKUP_MAX_AGE_HOURS=24
REQUIRE_RECENT_BACKUP=true
_result=0
check_recent_backup 2>/dev/null || _result=$?
assert_equals "$EXIT_SAFETY" "$_result" "no backup should fail with EXIT_SAFETY"
rm -rf "$_empty_dir"

# ============================================================
# 3. Old backup fails with EXIT_SAFETY
# ============================================================
test_start "old_backup_fails"
_old_dir=$(mktemp -d)
BACKUP_DEST="$_old_dir"
BACKUP_MAX_AGE_HOURS=1
REQUIRE_RECENT_BACKUP=true
touch -t 202501010000 "$_old_dir/glpi-backup-2025-01-01-000000.tar.gz"
_result=0
check_recent_backup 2>/dev/null || _result=$?
assert_equals "$EXIT_SAFETY" "$_result" "old backup should fail with EXIT_SAFETY"
rm -rf "$_old_dir"

# ============================================================
# 4. Safety gate disabled skips check
# ============================================================
test_start "safety_gate_disabled_skips_check"
_empty2=$(mktemp -d)
BACKUP_DEST="$_empty2"
REQUIRE_RECENT_BACKUP=false
_result=0
check_recent_backup || _result=$?
assert_equals "0" "$_result" "disabled safety gate should pass"
rm -rf "$_empty2"

rm -rf "$_TEST_DIR"

test_summary
