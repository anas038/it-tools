#!/bin/sh
# test_alert.sh — Tests for lib/alert.sh
# POSIX sh compliant — no bash-isms
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/test_helper.sh"
. "$PROJECT_ROOT/lib/common.sh"
. "$PROJECT_ROOT/lib/alert.sh"

echo "=== test_alert.sh ==="

_TEST_LOG_DIR=$(mktemp -d)

# ============================================================
# 1. Log-only alert creates file
# ============================================================
test_start "alert_to_log_creates_file"
ALERT_CHANNELS="log"
LOG_DIR="$_TEST_LOG_DIR"
send_alert "Test Alert" "Something went wrong" "monitor"
assert_file_exists "$_TEST_LOG_DIR/alerts.log"

# ============================================================
# 2. Log contains subject and body
# ============================================================
test_start "alert_log_contains_message"
_content=$(cat "$_TEST_LOG_DIR/alerts.log")
assert_contains "$_content" "Test Alert"
assert_contains "$_content" "Something went wrong"

# ============================================================
# 3. Cooldown suppresses repeat alerts
# ============================================================
test_start "alert_cooldown_suppresses_repeat"
ALERT_CHANNELS="log"
ALERT_COOLDOWN_MINUTES=60
LOG_DIR="$_TEST_LOG_DIR"
# First alert should go through
_before=$(wc -l < "$_TEST_LOG_DIR/alerts.log")
send_alert "Down Alert" "Service is down" "monitor"
_after=$(wc -l < "$_TEST_LOG_DIR/alerts.log")
_al_grew=1
if [ "$_after" -gt "$_before" ]; then _al_grew=0; fi
assert_true "$_al_grew" "First alert should be logged"

# Second identical alert should be suppressed
_before2=$(wc -l < "$_TEST_LOG_DIR/alerts.log")
send_alert "Down Alert" "Service is down" "monitor"
_after2=$(wc -l < "$_TEST_LOG_DIR/alerts.log")
assert_equals "$_before2" "$_after2" "Repeat alert should be suppressed"

rm -rf "$_TEST_LOG_DIR"

test_summary
