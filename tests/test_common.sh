#!/bin/sh
# test_common.sh — Tests for lib/common.sh
# POSIX sh compliant — no bash-isms
set -eu

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

. "$TESTS_DIR/test_helper.sh"
. "$PROJECT_ROOT/lib/common.sh"

echo "=== test_common.sh ==="

# ============================================================
# 1. All 9 exit code constants have correct values
# ============================================================
test_start "exit_code_constants"
assert_equals "0" "$EXIT_OK" "EXIT_OK should be 0"
assert_equals "1" "$EXIT_CONFIG" "EXIT_CONFIG should be 1"
assert_equals "2" "$EXIT_DEPENDENCY" "EXIT_DEPENDENCY should be 2"
assert_equals "3" "$EXIT_DATABASE" "EXIT_DATABASE should be 3"
assert_equals "4" "$EXIT_SERVICE" "EXIT_SERVICE should be 4"
assert_equals "5" "$EXIT_FILESYSTEM" "EXIT_FILESYSTEM should be 5"
assert_equals "6" "$EXIT_LOCK" "EXIT_LOCK should be 6"
assert_equals "7" "$EXIT_SAFETY" "EXIT_SAFETY should be 7"
assert_equals "8" "$EXIT_PARTIAL" "EXIT_PARTIAL should be 8"

# ============================================================
# 2. log_info outputs to stderr and contains "INFO"
# ============================================================
test_start "log_info_outputs_to_stderr_with_INFO"
LOG_LEVEL="info"
_li_output=$(log_info "test message" 2>&1)
assert_contains "$_li_output" "INFO" "log_info should contain INFO"

# ============================================================
# 3. log_debug suppressed at info level
# ============================================================
test_start "log_debug_suppressed_at_info_level"
LOG_LEVEL="info"
_ld_output=$(log_debug "hidden message" 2>&1)
assert_equals "" "$_ld_output" "log_debug should be suppressed at info level"

# ============================================================
# 4. log_debug shown at debug level
# ============================================================
test_start "log_debug_shown_at_debug_level"
LOG_LEVEL="debug"
_ld2_output=$(log_debug "visible message" 2>&1)
assert_contains "$_ld2_output" "DEBUG" "log_debug should contain DEBUG at debug level"
assert_contains "$_ld2_output" "visible message" "log_debug should contain the message"

# ============================================================
# 5. log_warn shown at info level
# ============================================================
test_start "log_warn_shown_at_info_level"
LOG_LEVEL="info"
_lw_output=$(log_warn "warning message" 2>&1)
assert_contains "$_lw_output" "WARN" "log_warn should contain WARN"

# ============================================================
# 6. log_error shown at error level
# ============================================================
test_start "log_error_shown_at_error_level"
LOG_LEVEL="error"
_le_output=$(log_error "error message" 2>&1)
assert_contains "$_le_output" "ERROR" "log_error should contain ERROR"

# ============================================================
# 7. log_info suppressed at error level
# ============================================================
test_start "log_info_suppressed_at_error_level"
LOG_LEVEL="error"
_li2_output=$(log_info "hidden info" 2>&1)
assert_equals "" "$_li2_output" "log_info should be suppressed at error level"

# Reset log level for remaining tests
LOG_LEVEL="info"

# ============================================================
# 8. collect_error collects multiple errors
# ============================================================
test_start "collect_error_collects_multiple"
clear_errors
collect_error "error one"
collect_error "error two"
_ce_result=$(get_errors)
assert_contains "$_ce_result" "error one" "should contain first error"
assert_contains "$_ce_result" "error two" "should contain second error"

# ============================================================
# 9. has_errors returns true (0) when errors exist
# ============================================================
test_start "has_errors_true_when_errors_exist"
clear_errors
collect_error "some error"
has_errors
_he_result=$?
assert_true "$_he_result" "has_errors should return 0 when errors exist"

# ============================================================
# 10. has_errors returns false (non-zero) when no errors
# ============================================================
test_start "has_errors_false_when_no_errors"
clear_errors
_he2_result=0
has_errors || _he2_result=$?
assert_false "$_he2_result" "has_errors should return non-zero when no errors"

# ============================================================
# 11. acquire_lock creates file
# ============================================================
test_start "acquire_lock_creates_file"
_al_tmpdir=$(mktemp -d)
_al_lockfile="${_al_tmpdir}/test.lock"
acquire_lock "$_al_lockfile"
_al_exists=1
if [ -f "$_al_lockfile" ]; then _al_exists=0; fi
assert_true "$_al_exists" "acquire_lock should create lock file"
rm -rf "$_al_tmpdir"

# ============================================================
# 12. acquire_lock fails (exit code 6) if lock exists and not stale
# ============================================================
test_start "acquire_lock_fails_if_locked"
_al2_tmpdir=$(mktemp -d)
_al2_lockfile="${_al2_tmpdir}/test.lock"
acquire_lock "$_al2_lockfile"
# Try to acquire again — should fail with EXIT_LOCK (6)
# Run in subshell to capture return code without exiting
_al2_rc=0
acquire_lock "$_al2_lockfile" 2>/dev/null || _al2_rc=$?
assert_equals "6" "$_al2_rc" "acquire_lock should return EXIT_LOCK (6) when locked"
rm -rf "$_al2_tmpdir"

# ============================================================
# 13. release_lock removes file
# ============================================================
test_start "release_lock_removes_file"
_rl_tmpdir=$(mktemp -d)
_rl_lockfile="${_rl_tmpdir}/test.lock"
acquire_lock "$_rl_lockfile"
release_lock "$_rl_lockfile"
_rl_gone=0
if [ -f "$_rl_lockfile" ]; then _rl_gone=1; fi
assert_true "$_rl_gone" "release_lock should remove lock file"
rm -rf "$_rl_tmpdir"

# ============================================================
# 14. Stale lock is removed and acquire succeeds
# ============================================================
test_start "stale_lock_removed_and_acquire_succeeds"
_sl_tmpdir=$(mktemp -d)
_sl_lockfile="${_sl_tmpdir}/test.lock"
echo "old_pid" > "$_sl_lockfile"
# Make the lock file old (year 2000)
touch -t 200001010000 "$_sl_lockfile"
_sl_rc=0
acquire_lock "$_sl_lockfile" 2>/dev/null || _sl_rc=$?
assert_true "$_sl_rc" "acquire_lock should succeed on stale lock"
# Verify the file now has our PID
_sl_pid_in_lock=$(cat "$_sl_lockfile")
assert_equals "$$" "$_sl_pid_in_lock" "lock file should contain current PID"
rm -rf "$_sl_tmpdir"

# ============================================================
# 15. retry_cmd succeeds on first try
# ============================================================
test_start "retry_cmd_succeeds_first_try"
RETRY_DELAY_SECONDS=0
_rt_rc=0
retry_cmd true 2>/dev/null || _rt_rc=$?
assert_true "$_rt_rc" "retry_cmd should return 0 on success"

# ============================================================
# 16. retry_cmd fails after exhausting retries
# ============================================================
test_start "retry_cmd_fails_after_exhausting_retries"
RETRY_DELAY_SECONDS=0
RETRY_COUNT=3
_rt2_rc=0
retry_cmd false 2>/dev/null || _rt2_rc=$?
assert_false "$_rt2_rc" "retry_cmd should return non-zero after all attempts fail"

# Reset
RETRY_DELAY_SECONDS=10
RETRY_COUNT=3

# ============================================================
# Summary
# ============================================================
test_summary
