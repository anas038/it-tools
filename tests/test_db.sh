#!/bin/sh
# test_db.sh — Tests for lib/db.sh
# POSIX sh compliant — no bash-isms
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/test_helper.sh"
. "$PROJECT_ROOT/lib/common.sh"
. "$PROJECT_ROOT/lib/db.sh"

echo "=== test_db.sh ==="

# ============================================================
# 1. Direct credential loading
# ============================================================
test_start "db_load_creds_direct"
DB_AUTO_DETECT=false
DB_HOST="dbhost"
DB_NAME="testdb"
DB_USER="testuser"
DB_PASS="testpass"
db_load_credentials
assert_equals "dbhost" "$_DB_HOST" "DB_HOST should match"
assert_equals "testdb" "$_DB_NAME" "DB_NAME should match"
assert_equals "testuser" "$_DB_USER" "DB_USER should match"
assert_equals "testpass" "$_DB_PASS" "DB_PASS should match"

# ============================================================
# 2. Auto-detect from GLPI config_db.php
# ============================================================
test_start "db_parse_glpi_config"
_TEST_DIR=$(mktemp -d)
mkdir -p "$_TEST_DIR/config"
cat > "$_TEST_DIR/config/config_db.php" << 'PHPEOF'
<?php
class DB extends DBmysql {
   public $dbhost = 'glpihost';
   public $dbuser = 'glpiuser';
   public $dbpassword = 'glpipass123';
   public $dbdefault = 'glpidb';
}
PHPEOF

DB_AUTO_DETECT=true
GLPI_INSTALL_PATH="$_TEST_DIR"
db_load_credentials
assert_equals "glpihost" "$_DB_HOST" "auto-detected DB_HOST"
assert_equals "glpidb" "$_DB_NAME" "auto-detected DB_NAME"
assert_equals "glpiuser" "$_DB_USER" "auto-detected DB_USER"
assert_equals "glpipass123" "$_DB_PASS" "auto-detected DB_PASS"

rm -rf "$_TEST_DIR"

# ============================================================
# 3. Build mysqldump args
# ============================================================
test_start "db_build_dump_args"
_DB_HOST="localhost"
_DB_NAME="testdb"
_DB_USER="admin"
_DB_PASS="secret"
_args=$(db_build_dump_args)
assert_contains "$_args" "-h localhost" "should contain host flag"
assert_contains "$_args" "-u admin" "should contain user flag"
assert_contains "$_args" "testdb" "should contain database name"

test_summary
