# IT-Tools Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a POSIX sh CLI toolkit for automating GLPI administration tasks (monitoring, backup, purge, archive) with multi-channel alerting, safety gates, and a configurable installer.

**Architecture:** Convention-based per-product layout under `products/<name>/` with shared libraries in `lib/`. A unified `bin/it` dispatcher auto-discovers products and tools. All scripts are POSIX sh (`#!/bin/sh`, `set -eu`), no bash-isms.

**Tech Stack:** POSIX sh, cron, curl, mysqldump, tar, systemctl, mail/msmtp

**Design doc:** `docs/plans/2026-02-25-it-tools-design.md`

---

## Task 1: Project Skeleton + Test Framework

**Files:**
- Create: `tests/test_helper.sh`
- Create: `tests/run_tests.sh`
- Create: `lib/.gitkeep` (removed after lib files exist)
- Create: `products/glpi/.gitkeep` (removed after product files exist)
- Create: `logs/.gitkeep`
- Create: `bin/.gitkeep` (removed after bin/it exists)
- Create: `cron/.gitkeep` (removed after cron files exist)

**Step 1: Create directory structure**

```sh
mkdir -p bin lib products/glpi logs cron tests
```

**Step 2: Write test helper with assert functions**

Create `tests/test_helper.sh`:

```sh
#!/bin/sh
# Test helper — lightweight assertion library for POSIX sh tests
# Usage: source this file, then call assert functions

_TESTS_RUN=0
_TESTS_PASSED=0
_TESTS_FAILED=0
_CURRENT_TEST=""

test_start() {
    _CURRENT_TEST="$1"
    _TESTS_RUN=$(( _TESTS_RUN + 1 ))
}

assert_equals() {
    _expected="$1"
    _actual="$2"
    _msg="${3:-"expected '$_expected', got '$_actual'"}"
    if [ "$_expected" = "$_actual" ]; then
        _TESTS_PASSED=$(( _TESTS_PASSED + 1 ))
    else
        _TESTS_FAILED=$(( _TESTS_FAILED + 1 ))
        printf "  FAIL [%s]: %s\n" "$_CURRENT_TEST" "$_msg" >&2
    fi
}

assert_true() {
    _actual="$1"
    _msg="${2:-"expected true (0), got '$_actual'"}"
    if [ "$_actual" -eq 0 ] 2>/dev/null; then
        _TESTS_PASSED=$(( _TESTS_PASSED + 1 ))
    else
        _TESTS_FAILED=$(( _TESTS_FAILED + 1 ))
        printf "  FAIL [%s]: %s\n" "$_CURRENT_TEST" "$_msg" >&2
    fi
}

assert_false() {
    _actual="$1"
    _msg="${2:-"expected non-zero, got '$_actual'"}"
    if [ "$_actual" -ne 0 ] 2>/dev/null; then
        _TESTS_PASSED=$(( _TESTS_PASSED + 1 ))
    else
        _TESTS_FAILED=$(( _TESTS_FAILED + 1 ))
        printf "  FAIL [%s]: %s\n" "$_CURRENT_TEST" "$_msg" >&2
    fi
}

assert_contains() {
    _haystack="$1"
    _needle="$2"
    _msg="${3:-"expected output to contain '$_needle'"}"
    case "$_haystack" in
        *"$_needle"*)
            _TESTS_PASSED=$(( _TESTS_PASSED + 1 ))
            ;;
        *)
            _TESTS_FAILED=$(( _TESTS_FAILED + 1 ))
            printf "  FAIL [%s]: %s\n" "$_CURRENT_TEST" "$_msg" >&2
            ;;
    esac
}

assert_not_contains() {
    _haystack="$1"
    _needle="$2"
    _msg="${3:-"expected output to NOT contain '$_needle'"}"
    case "$_haystack" in
        *"$_needle"*)
            _TESTS_FAILED=$(( _TESTS_FAILED + 1 ))
            printf "  FAIL [%s]: %s\n" "$_CURRENT_TEST" "$_msg" >&2
            ;;
        *)
            _TESTS_PASSED=$(( _TESTS_PASSED + 1 ))
            ;;
    esac
}

assert_file_exists() {
    _path="$1"
    _msg="${2:-"expected file '$_path' to exist"}"
    if [ -f "$_path" ]; then
        _TESTS_PASSED=$(( _TESTS_PASSED + 1 ))
    else
        _TESTS_FAILED=$(( _TESTS_FAILED + 1 ))
        printf "  FAIL [%s]: %s\n" "$_CURRENT_TEST" "$_msg" >&2
    fi
}

test_summary() {
    printf "\n%d tests run, %d passed, %d failed\n" \
        "$_TESTS_RUN" "$_TESTS_PASSED" "$_TESTS_FAILED"
    if [ "$_TESTS_FAILED" -gt 0 ]; then
        return 1
    fi
    return 0
}
```

**Step 3: Write the test runner**

Create `tests/run_tests.sh`:

```sh
#!/bin/sh
# Run all test files matching tests/test_*.sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FAILURES=0
TOTAL=0

for test_file in "$SCRIPT_DIR"/test_*.sh; do
    [ -f "$test_file" ] || continue
    TOTAL=$(( TOTAL + 1 ))
    printf "=== Running %s ===\n" "$(basename "$test_file")"
    if sh "$test_file"; then
        printf "  OK\n"
    else
        FAILURES=$(( FAILURES + 1 ))
        printf "  FAILED\n"
    fi
    printf "\n"
done

printf "========================================\n"
printf "Test suites: %d total, %d failed\n" "$TOTAL" "$FAILURES"

if [ "$FAILURES" -gt 0 ]; then
    exit 1
fi
exit 0
```

**Step 4: Create .gitkeep files for empty directories**

```sh
touch lib/.gitkeep products/glpi/.gitkeep logs/.gitkeep bin/.gitkeep cron/.gitkeep
```

**Step 5: Make scripts executable and commit**

```sh
chmod +x tests/test_helper.sh tests/run_tests.sh
git add tests/ lib/.gitkeep products/glpi/.gitkeep logs/.gitkeep bin/.gitkeep cron/.gitkeep
git commit -m "feat: add project skeleton and test framework"
```

---

## Task 2: lib/common.sh — Exit Codes and Core Logging

**Files:**
- Create: `lib/common.sh`
- Create: `tests/test_common.sh`

**Step 1: Write the failing test**

Create `tests/test_common.sh`:

```sh
#!/bin/sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/test_helper.sh"

# --- Exit codes ---
test_start "exit_code_constants"
assert_equals "0" "$EXIT_OK"
assert_equals "1" "$EXIT_CONFIG"
assert_equals "2" "$EXIT_DEPENDENCY"
assert_equals "3" "$EXIT_DATABASE"
assert_equals "4" "$EXIT_SERVICE"
assert_equals "5" "$EXIT_FILESYSTEM"
assert_equals "6" "$EXIT_LOCK"
assert_equals "7" "$EXIT_SAFETY"
assert_equals "8" "$EXIT_PARTIAL"

# --- Logging ---
test_start "log_info_outputs_to_stderr"
LOG_LEVEL="info"
_output=$(log_info "hello world" 2>&1 >/dev/null)
assert_contains "$_output" "hello world"
assert_contains "$_output" "INFO"

test_start "log_debug_suppressed_at_info_level"
LOG_LEVEL="info"
_output=$(log_debug "debug msg" 2>&1 >/dev/null)
assert_equals "" "$_output"

test_start "log_debug_shown_at_debug_level"
LOG_LEVEL="debug"
_output=$(log_debug "debug msg" 2>&1 >/dev/null)
assert_contains "$_output" "debug msg"

test_start "log_warn_shown_at_info_level"
LOG_LEVEL="info"
_output=$(log_warn "warning" 2>&1 >/dev/null)
assert_contains "$_output" "WARN"

test_start "log_error_shown_at_error_level"
LOG_LEVEL="error"
_output=$(log_error "failure" 2>&1 >/dev/null)
assert_contains "$_output" "ERROR"

test_start "log_info_suppressed_at_error_level"
LOG_LEVEL="error"
_output=$(log_info "should not show" 2>&1 >/dev/null)
assert_equals "" "$_output"

# --- Error collection ---
test_start "error_collection"
_ERRORS=""
collect_error "first problem"
collect_error "second problem"
assert_contains "$_ERRORS" "first problem"
assert_contains "$_ERRORS" "second problem"

test_start "has_errors_returns_true_when_errors_exist"
_ERRORS="something"
has_errors
assert_true "$?"

test_start "has_errors_returns_false_when_no_errors"
_ERRORS=""
has_errors
assert_false "$?"

test_summary
```

**Step 2: Run test to verify it fails**

Run: `sh tests/test_common.sh`
Expected: FAIL — common.sh not sourced, variables undefined

**Step 3: Write the implementation**

Create `lib/common.sh`:

```sh
#!/bin/sh
# lib/common.sh — Core utilities for it-tools
# Provides: logging, exit codes, error collection, argument helpers

# ---- Exit Codes (design doc §15) ----
EXIT_OK=0
EXIT_CONFIG=1
EXIT_DEPENDENCY=2
EXIT_DATABASE=3
EXIT_SERVICE=4
EXIT_FILESYSTEM=5
EXIT_LOCK=6
EXIT_SAFETY=7
EXIT_PARTIAL=8

# ---- Globals ----
LOG_LEVEL="${LOG_LEVEL:-info}"
LOG_DIR="${LOG_DIR:-}"
DRY_RUN="${DRY_RUN:-false}"
VERBOSE="${VERBOSE:-false}"
QUIET="${QUIET:-false}"

_ERRORS=""

# ---- Log Level Ordering ----
_log_level_num() {
    case "$1" in
        debug) echo 0 ;;
        info)  echo 1 ;;
        warn)  echo 2 ;;
        error) echo 3 ;;
        *)     echo 1 ;;
    esac
}

# ---- Logging Functions ----
# All log output goes to stderr so stdout remains clean for data

_log() {
    _level="$1"
    shift
    _current=$(_log_level_num "$LOG_LEVEL")
    _msg_level=$(_log_level_num "$_level")
    if [ "$_msg_level" -lt "$_current" ]; then
        return 0
    fi
    _timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    _level_upper=$(echo "$_level" | tr '[:lower:]' '[:upper:]')
    printf "[%s] %s: %s\n" "$_timestamp" "$_level_upper" "$*" >&2

    # Also write to log file if LOG_DIR is set
    if [ -n "$LOG_DIR" ] && [ -d "$LOG_DIR" ]; then
        printf "[%s] %s: %s\n" "$_timestamp" "$_level_upper" "$*" \
            >> "$LOG_DIR/it-tools.log"
    fi
}

log_debug() { _log "debug" "$@"; }
log_info()  { _log "info"  "$@"; }
log_warn()  { _log "warn"  "$@"; }
log_error() { _log "error" "$@"; }

# ---- Error Collection (design doc §9) ----

collect_error() {
    if [ -z "$_ERRORS" ]; then
        _ERRORS="$1"
    else
        _ERRORS="$_ERRORS
$1"
    fi
}

has_errors() {
    [ -n "$_ERRORS" ]
}

get_errors() {
    printf '%s\n' "$_ERRORS"
}

clear_errors() {
    _ERRORS=""
}

# ---- Argument Helpers ----

require_arg() {
    _name="$1"
    _value="$2"
    if [ -z "$_value" ]; then
        log_error "Required argument missing: $_name"
        exit "$EXIT_CONFIG"
    fi
}

# ---- Confirmation Prompt ----

confirm() {
    _prompt="${1:-Continue?}"
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[dry-run] Would prompt: $_prompt"
        return 0
    fi
    printf "%s [y/N] " "$_prompt" >&2
    read -r _answer
    case "$_answer" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

# ---- Common Flag Parsing ----
# Call: parse_common_flags "$@" — sets DRY_RUN, VERBOSE, QUIET, LOG_LEVEL

parse_common_flags() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run)  DRY_RUN=true ;;
            --verbose)  VERBOSE=true; LOG_LEVEL=debug ;;
            --quiet)    QUIET=true; LOG_LEVEL=error ;;
            --help|-h)  return 2 ;;  # signal caller to show help
            *)          ;; # ignore unknown flags — callers handle their own
        esac
        shift
    done
    return 0
}

# ---- Config Loading ----

load_config() {
    _config_file="$1"
    if [ ! -f "$_config_file" ]; then
        log_error "Config file not found: $_config_file"
        exit "$EXIT_CONFIG"
    fi
    # shellcheck source=/dev/null
    . "$_config_file"
    log_debug "Loaded config: $_config_file"
}

# ---- Resolve Project Root ----
# Finds the it-tools root directory relative to any script location

resolve_project_root() {
    _script_path="$1"
    _dir="$(cd "$(dirname "$_script_path")" && pwd)"
    # Walk up until we find lib/common.sh
    while [ "$_dir" != "/" ]; do
        if [ -f "$_dir/lib/common.sh" ]; then
            echo "$_dir"
            return 0
        fi
        _dir="$(dirname "$_dir")"
    done
    echo ""
    return 1
}
```

**Step 4: Update test to source common.sh, run to verify it passes**

Add this line near the top of `tests/test_common.sh`, after the PROJECT_ROOT line:

```sh
. "$PROJECT_ROOT/lib/common.sh"
```

Run: `sh tests/test_common.sh`
Expected: All tests PASS

**Step 5: Commit**

```sh
chmod +x lib/common.sh
git add lib/common.sh tests/test_common.sh
git commit -m "feat: add lib/common.sh with logging, exit codes, error collection"
```

---

## Task 3: lib/common.sh — Lock File Management

**Files:**
- Modify: `lib/common.sh`
- Modify: `tests/test_common.sh`

**Step 1: Write the failing test**

Append to `tests/test_common.sh` (before `test_summary`):

```sh
# --- Lock files ---
_TEST_LOCK_DIR=$(mktemp -d)

test_start "acquire_lock_creates_file"
LOCK_TIMEOUT_MINUTES=120
acquire_lock "$_TEST_LOCK_DIR/test.lock"
assert_file_exists "$_TEST_LOCK_DIR/test.lock"

test_start "acquire_lock_fails_if_locked"
_result=0
acquire_lock "$_TEST_LOCK_DIR/test.lock" 2>/dev/null || _result=$?
assert_equals "6" "$_result"

test_start "release_lock_removes_file"
release_lock "$_TEST_LOCK_DIR/test.lock"
_exists=0
[ -f "$_TEST_LOCK_DIR/test.lock" ] || _exists=1
assert_equals "1" "$_exists"

test_start "stale_lock_is_removed"
# Create a stale lock (older than timeout)
echo "99999" > "$_TEST_LOCK_DIR/stale.lock"
touch -t 200001010000 "$_TEST_LOCK_DIR/stale.lock"
LOCK_TIMEOUT_MINUTES=1
acquire_lock "$_TEST_LOCK_DIR/stale.lock"
assert_file_exists "$_TEST_LOCK_DIR/stale.lock"
release_lock "$_TEST_LOCK_DIR/stale.lock"

rm -rf "$_TEST_LOCK_DIR"
```

**Step 2: Run test to verify it fails**

Run: `sh tests/test_common.sh`
Expected: FAIL — acquire_lock undefined

**Step 3: Write the implementation**

Append to `lib/common.sh`:

```sh
# ---- Lock File Management (design doc §10) ----

LOCK_TIMEOUT_MINUTES="${LOCK_TIMEOUT_MINUTES:-120}"

acquire_lock() {
    _lock_file="$1"

    if [ -f "$_lock_file" ]; then
        # Check if stale
        _lock_age_seconds=$(( $(date +%s) - $(date -r "$_lock_file" +%s) ))
        _timeout_seconds=$(( LOCK_TIMEOUT_MINUTES * 60 ))
        if [ "$_lock_age_seconds" -gt "$_timeout_seconds" ]; then
            log_warn "Stale lock detected (age: ${_lock_age_seconds}s), removing: $_lock_file"
            rm -f "$_lock_file"
        else
            log_error "Lock file exists: $_lock_file (age: ${_lock_age_seconds}s)"
            return "$EXIT_LOCK"
        fi
    fi

    echo "$$" > "$_lock_file"
    log_debug "Lock acquired: $_lock_file (PID $$)"
}

release_lock() {
    _lock_file="$1"
    if [ -f "$_lock_file" ]; then
        rm -f "$_lock_file"
        log_debug "Lock released: $_lock_file"
    fi
}
```

**Step 4: Run test to verify it passes**

Run: `sh tests/test_common.sh`
Expected: All tests PASS

**Step 5: Commit**

```sh
git add lib/common.sh tests/test_common.sh
git commit -m "feat: add lock file management to lib/common.sh"
```

---

## Task 4: lib/common.sh — Retry Logic

**Files:**
- Modify: `lib/common.sh`
- Modify: `tests/test_common.sh`

**Step 1: Write the failing test**

Append to `tests/test_common.sh` (before `test_summary`):

```sh
# --- Retry logic ---
test_start "retry_cmd_succeeds_on_first_try"
RETRY_COUNT=3
RETRY_DELAY_SECONDS=0
_output=$(retry_cmd true 2>&1)
assert_true "$?"

test_start "retry_cmd_fails_after_exhausting_retries"
RETRY_COUNT=2
RETRY_DELAY_SECONDS=0
_result=0
retry_cmd false 2>/dev/null || _result=$?
assert_false "0"  # should be non-zero
```

**Step 2: Run test to verify it fails**

Run: `sh tests/test_common.sh`
Expected: FAIL — retry_cmd undefined

**Step 3: Write the implementation**

Append to `lib/common.sh`:

```sh
# ---- Retry Logic (design doc §12) ----

RETRY_COUNT="${RETRY_COUNT:-3}"
RETRY_DELAY_SECONDS="${RETRY_DELAY_SECONDS:-10}"

retry_cmd() {
    _attempt=1
    while [ "$_attempt" -le "$RETRY_COUNT" ]; do
        if "$@"; then
            return 0
        fi
        log_warn "Attempt $_attempt/$RETRY_COUNT failed: $*"
        _attempt=$(( _attempt + 1 ))
        if [ "$_attempt" -le "$RETRY_COUNT" ] && [ "$RETRY_DELAY_SECONDS" -gt 0 ]; then
            sleep "$RETRY_DELAY_SECONDS"
        fi
    done
    log_error "All $RETRY_COUNT attempts failed: $*"
    return 1
}
```

**Step 4: Run test to verify it passes**

Run: `sh tests/test_common.sh`
Expected: All tests PASS

**Step 5: Commit**

```sh
git add lib/common.sh tests/test_common.sh
git commit -m "feat: add retry logic to lib/common.sh"
```

---

## Task 5: lib/alert.sh — Multi-Channel Alerting

**Files:**
- Create: `lib/alert.sh`
- Create: `tests/test_alert.sh`

**Step 1: Write the failing test**

Create `tests/test_alert.sh`:

```sh
#!/bin/sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/test_helper.sh"
. "$PROJECT_ROOT/lib/common.sh"
. "$PROJECT_ROOT/lib/alert.sh"

_TEST_LOG_DIR=$(mktemp -d)

# --- Log-only alert ---
test_start "alert_to_log_creates_file"
ALERT_CHANNELS="log"
LOG_DIR="$_TEST_LOG_DIR"
send_alert "Test Alert" "Something went wrong" "monitor"
assert_file_exists "$_TEST_LOG_DIR/alerts.log"

test_start "alert_log_contains_message"
_content=$(cat "$_TEST_LOG_DIR/alerts.log")
assert_contains "$_content" "Test Alert"
assert_contains "$_content" "Something went wrong"

# --- Cooldown ---
test_start "alert_cooldown_suppresses_repeat"
ALERT_CHANNELS="log"
ALERT_COOLDOWN_MINUTES=60
LOG_DIR="$_TEST_LOG_DIR"
# First alert should go through
_before=$(wc -l < "$_TEST_LOG_DIR/alerts.log")
send_alert "Down Alert" "Service is down" "monitor"
_after=$(wc -l < "$_TEST_LOG_DIR/alerts.log")
assert_true "$(( _after > _before ))" "First alert should be logged"

# Second identical alert should be suppressed
_before2=$(wc -l < "$_TEST_LOG_DIR/alerts.log")
send_alert "Down Alert" "Service is down" "monitor"
_after2=$(wc -l < "$_TEST_LOG_DIR/alerts.log")
assert_equals "$_before2" "$_after2" "Repeat alert should be suppressed"

rm -rf "$_TEST_LOG_DIR"

test_summary
```

**Step 2: Run test to verify it fails**

Run: `sh tests/test_alert.sh`
Expected: FAIL — alert.sh doesn't exist

**Step 3: Write the implementation**

Create `lib/alert.sh`:

```sh
#!/bin/sh
# lib/alert.sh — Multi-channel alert dispatching
# Depends on: lib/common.sh (must be sourced first)
#
# Supports: email, teams (Microsoft Teams webhook), slack, log
# Config keys: ALERT_CHANNELS, ALERT_EMAIL_TO, ALERT_TEAMS_WEBHOOK,
#              ALERT_SLACK_WEBHOOK, ALERT_COOLDOWN_MINUTES

ALERT_CHANNELS="${ALERT_CHANNELS:-log}"
ALERT_EMAIL_TO="${ALERT_EMAIL_TO:-}"
ALERT_TEAMS_WEBHOOK="${ALERT_TEAMS_WEBHOOK:-}"
ALERT_SLACK_WEBHOOK="${ALERT_SLACK_WEBHOOK:-}"
ALERT_COOLDOWN_MINUTES="${ALERT_COOLDOWN_MINUTES:-60}"

# ---- Cooldown State ----

_cooldown_file() {
    _tool="$1"
    _subject="$2"
    _hash=$(printf '%s:%s' "$_tool" "$_subject" | cksum | cut -d' ' -f1)
    _state_dir="${LOG_DIR:-/tmp}"
    echo "$_state_dir/.alert_cooldown_${_hash}"
}

_is_in_cooldown() {
    _tool="$1"
    _subject="$2"
    _cf=$(_cooldown_file "$_tool" "$_subject")
    if [ -f "$_cf" ]; then
        _age=$(( $(date +%s) - $(date -r "$_cf" +%s) ))
        _timeout=$(( ALERT_COOLDOWN_MINUTES * 60 ))
        if [ "$_age" -lt "$_timeout" ]; then
            log_debug "Alert suppressed (cooldown: ${_age}s/${_timeout}s): $_subject"
            return 0  # still in cooldown
        fi
        rm -f "$_cf"
    fi
    return 1  # not in cooldown
}

_set_cooldown() {
    _tool="$1"
    _subject="$2"
    _cf=$(_cooldown_file "$_tool" "$_subject")
    touch "$_cf"
}

# ---- Channel Senders ----

_alert_log() {
    _subject="$1"
    _body="$2"
    _tool="$3"
    _log_file="${LOG_DIR:-/tmp}/alerts.log"
    _ts=$(date '+%Y-%m-%d %H:%M:%S')
    printf "[%s] [%s] %s: %s\n" "$_ts" "$_tool" "$_subject" "$_body" \
        >> "$_log_file"
}

_alert_email() {
    _subject="$1"
    _body="$2"
    _tool="$3"
    if [ -z "$ALERT_EMAIL_TO" ]; then
        log_warn "ALERT_EMAIL_TO not configured, skipping email alert"
        return 0
    fi
    printf '%s\n' "$_body" | mail -s "[it-tools/$_tool] $_subject" "$ALERT_EMAIL_TO" \
        2>/dev/null || {
        log_warn "Failed to send email alert to $ALERT_EMAIL_TO"
        collect_error "Email alert failed: $_subject"
    }
}

_alert_teams() {
    _subject="$1"
    _body="$2"
    _tool="$3"
    if [ -z "$ALERT_TEAMS_WEBHOOK" ]; then
        log_warn "ALERT_TEAMS_WEBHOOK not configured, skipping Teams alert"
        return 0
    fi
    _payload=$(printf '{"@type":"MessageCard","summary":"%s","sections":[{"activityTitle":"[it-tools/%s] %s","text":"%s"}]}' \
        "$_subject" "$_tool" "$_subject" "$_body")
    curl -s -o /dev/null -w '' -H "Content-Type: application/json" \
        -d "$_payload" "$ALERT_TEAMS_WEBHOOK" 2>/dev/null || {
        log_warn "Failed to send Teams alert"
        collect_error "Teams alert failed: $_subject"
    }
}

_alert_slack() {
    _subject="$1"
    _body="$2"
    _tool="$3"
    if [ -z "$ALERT_SLACK_WEBHOOK" ]; then
        log_warn "ALERT_SLACK_WEBHOOK not configured, skipping Slack alert"
        return 0
    fi
    _payload=$(printf '{"text":"*[it-tools/%s] %s*\n%s"}' \
        "$_tool" "$_subject" "$_body")
    curl -s -o /dev/null -w '' -H "Content-Type: application/json" \
        -d "$_payload" "$ALERT_SLACK_WEBHOOK" 2>/dev/null || {
        log_warn "Failed to send Slack alert"
        collect_error "Slack alert failed: $_subject"
    }
}

# ---- Main Dispatcher ----

send_alert() {
    _subject="$1"
    _body="$2"
    _tool="${3:-unknown}"

    # Check cooldown
    if _is_in_cooldown "$_tool" "$_subject"; then
        return 0
    fi

    log_info "Sending alert: $_subject"

    # Parse channels (comma-separated)
    _channels="$ALERT_CHANNELS"
    _old_ifs="$IFS"
    IFS=','
    for _channel in $_channels; do
        # Trim whitespace
        _channel=$(echo "$_channel" | tr -d ' ')
        case "$_channel" in
            log)   _alert_log   "$_subject" "$_body" "$_tool" ;;
            email) _alert_email "$_subject" "$_body" "$_tool" ;;
            teams) _alert_teams "$_subject" "$_body" "$_tool" ;;
            slack) _alert_slack "$_subject" "$_body" "$_tool" ;;
            *)     log_warn "Unknown alert channel: $_channel" ;;
        esac
    done
    IFS="$_old_ifs"

    # Set cooldown after sending
    _set_cooldown "$_tool" "$_subject"
}
```

**Step 4: Run test to verify it passes**

Run: `sh tests/test_alert.sh`
Expected: All tests PASS

**Step 5: Commit**

```sh
chmod +x lib/alert.sh
git add lib/alert.sh tests/test_alert.sh
git commit -m "feat: add lib/alert.sh with multi-channel alerting and cooldown"
```

---

## Task 6: lib/db.sh — Database Helpers

**Files:**
- Create: `lib/db.sh`
- Create: `tests/test_db.sh`

**Step 1: Write the failing test**

Create `tests/test_db.sh` — testing credential parsing logic (no live DB needed):

```sh
#!/bin/sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/test_helper.sh"
. "$PROJECT_ROOT/lib/common.sh"
. "$PROJECT_ROOT/lib/db.sh"

# --- Direct credentials ---
test_start "db_load_creds_direct"
DB_AUTO_DETECT=false
DB_HOST="dbhost"
DB_NAME="testdb"
DB_USER="testuser"
DB_PASS="testpass"
db_load_credentials
assert_equals "dbhost" "$_DB_HOST"
assert_equals "testdb" "$_DB_NAME"
assert_equals "testuser" "$_DB_USER"
assert_equals "testpass" "$_DB_PASS"

# --- Auto-detect from GLPI config_db.php ---
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
assert_equals "glpihost" "$_DB_HOST"
assert_equals "glpidb" "$_DB_NAME"
assert_equals "glpiuser" "$_DB_USER"
assert_equals "glpipass123" "$_DB_PASS"

rm -rf "$_TEST_DIR"

# --- Build mysqldump args ---
test_start "db_build_dump_args"
_DB_HOST="localhost"
_DB_NAME="testdb"
_DB_USER="admin"
_DB_PASS="secret"
_args=$(db_build_dump_args)
assert_contains "$_args" "-h localhost"
assert_contains "$_args" "-u admin"
assert_contains "$_args" "testdb"

test_summary
```

**Step 2: Run test to verify it fails**

Run: `sh tests/test_db.sh`
Expected: FAIL — db.sh doesn't exist

**Step 3: Write the implementation**

Create `lib/db.sh`:

```sh
#!/bin/sh
# lib/db.sh — Database helpers for it-tools
# Depends on: lib/common.sh (must be sourced first)
#
# Provides credential loading (direct or auto-detect from GLPI config_db.php),
# query execution, and dump helpers.

DB_AUTO_DETECT="${DB_AUTO_DETECT:-false}"
DB_HOST="${DB_HOST:-localhost}"
DB_NAME="${DB_NAME:-}"
DB_USER="${DB_USER:-}"
DB_PASS="${DB_PASS:-}"
GLPI_INSTALL_PATH="${GLPI_INSTALL_PATH:-/var/www/html/glpi}"

# Internal resolved credentials
_DB_HOST=""
_DB_NAME=""
_DB_USER=""
_DB_PASS=""

# ---- Credential Loading ----

_parse_glpi_config_db() {
    _config_file="$GLPI_INSTALL_PATH/config/config_db.php"
    if [ ! -f "$_config_file" ]; then
        log_error "GLPI config_db.php not found: $_config_file"
        return "$EXIT_CONFIG"
    fi

    _DB_HOST=$(grep "dbhost" "$_config_file" | sed "s/.*= *'//;s/'.*//" | head -1)
    _DB_USER=$(grep "dbuser" "$_config_file" | sed "s/.*= *'//;s/'.*//" | head -1)
    _DB_PASS=$(grep "dbpassword" "$_config_file" | sed "s/.*= *'//;s/'.*//" | head -1)
    _DB_NAME=$(grep "dbdefault" "$_config_file" | sed "s/.*= *'//;s/'.*//" | head -1)

    log_debug "Auto-detected DB credentials from GLPI config"
}

db_load_credentials() {
    if [ "$DB_AUTO_DETECT" = "true" ]; then
        _parse_glpi_config_db
    else
        _DB_HOST="$DB_HOST"
        _DB_NAME="$DB_NAME"
        _DB_USER="$DB_USER"
        _DB_PASS="$DB_PASS"
    fi

    if [ -z "$_DB_NAME" ]; then
        log_error "Database name not configured"
        return "$EXIT_CONFIG"
    fi
}

# ---- Query Helpers ----

db_build_dump_args() {
    printf '%s' "-h $_DB_HOST -u $_DB_USER $_DB_NAME"
}

db_query() {
    _sql="$1"
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[dry-run] Would execute SQL: $_sql"
        return 0
    fi
    MYSQL_PWD="$_DB_PASS" mysql -h "$_DB_HOST" -u "$_DB_USER" "$_DB_NAME" \
        -N -B -e "$_sql" 2>/dev/null
}

db_dump() {
    _output_file="$1"
    shift
    _extra_args="$*"
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[dry-run] Would dump database $_DB_NAME to $_output_file"
        return 0
    fi
    MYSQL_PWD="$_DB_PASS" mysqldump -h "$_DB_HOST" -u "$_DB_USER" \
        $_extra_args "$_DB_NAME" > "$_output_file" 2>/dev/null
}

db_dump_tables() {
    _output_file="$1"
    shift
    # Remaining args are table names
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[dry-run] Would dump tables ($*) to $_output_file"
        return 0
    fi
    MYSQL_PWD="$_DB_PASS" mysqldump -h "$_DB_HOST" -u "$_DB_USER" \
        "$_DB_NAME" "$@" > "$_output_file" 2>/dev/null
}

db_count() {
    _table="$1"
    _where="${2:-1=1}"
    db_query "SELECT COUNT(*) FROM $_table WHERE $_where"
}
```

**Step 4: Run test to verify it passes**

Run: `sh tests/test_db.sh`
Expected: All tests PASS

**Step 5: Commit**

```sh
chmod +x lib/db.sh
git add lib/db.sh tests/test_db.sh
git commit -m "feat: add lib/db.sh with credential loading and query helpers"
```

---

## Task 7: lib/backup_check.sh — Safety Gate

**Files:**
- Create: `lib/backup_check.sh`
- Create: `tests/test_backup_check.sh`

**Step 1: Write the failing test**

Create `tests/test_backup_check.sh`:

```sh
#!/bin/sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/test_helper.sh"
. "$PROJECT_ROOT/lib/common.sh"
. "$PROJECT_ROOT/lib/backup_check.sh"

_TEST_DIR=$(mktemp -d)

# --- Recent backup exists ---
test_start "recent_backup_passes"
BACKUP_DEST="$_TEST_DIR"
BACKUP_MAX_AGE_HOURS=24
REQUIRE_RECENT_BACKUP=true
touch "$_TEST_DIR/glpi-backup-2026-02-26-020000.tar.gz"
_result=0
check_recent_backup || _result=$?
assert_equals "0" "$_result"

# --- No backup exists ---
test_start "no_backup_fails"
_empty_dir=$(mktemp -d)
BACKUP_DEST="$_empty_dir"
BACKUP_MAX_AGE_HOURS=24
REQUIRE_RECENT_BACKUP=true
_result=0
check_recent_backup 2>/dev/null || _result=$?
assert_equals "$EXIT_SAFETY" "$_result"
rm -rf "$_empty_dir"

# --- Old backup fails ---
test_start "old_backup_fails"
_old_dir=$(mktemp -d)
BACKUP_DEST="$_old_dir"
BACKUP_MAX_AGE_HOURS=1
REQUIRE_RECENT_BACKUP=true
touch -t 202501010000 "$_old_dir/glpi-backup-2025-01-01-000000.tar.gz"
_result=0
check_recent_backup 2>/dev/null || _result=$?
assert_equals "$EXIT_SAFETY" "$_result"
rm -rf "$_old_dir"

# --- Safety gate disabled ---
test_start "safety_gate_disabled_skips_check"
_empty2=$(mktemp -d)
BACKUP_DEST="$_empty2"
REQUIRE_RECENT_BACKUP=false
_result=0
check_recent_backup || _result=$?
assert_equals "0" "$_result"
rm -rf "$_empty2"

rm -rf "$_TEST_DIR"

test_summary
```

**Step 2: Run test to verify it fails**

Run: `sh tests/test_backup_check.sh`
Expected: FAIL — backup_check.sh doesn't exist

**Step 3: Write the implementation**

Create `lib/backup_check.sh`:

```sh
#!/bin/sh
# lib/backup_check.sh — Pre-flight check for recent backup
# Depends on: lib/common.sh (must be sourced first)
#
# Design doc §5: purge and archive refuse to proceed without a recent backup

REQUIRE_RECENT_BACKUP="${REQUIRE_RECENT_BACKUP:-true}"
BACKUP_MAX_AGE_HOURS="${BACKUP_MAX_AGE_HOURS:-24}"
BACKUP_DEST="${BACKUP_DEST:-}"

check_recent_backup() {
    if [ "$REQUIRE_RECENT_BACKUP" != "true" ]; then
        log_debug "Safety gate disabled (REQUIRE_RECENT_BACKUP=false)"
        return 0
    fi

    if [ -z "$BACKUP_DEST" ]; then
        log_error "BACKUP_DEST not configured, cannot verify recent backup"
        return "$EXIT_SAFETY"
    fi

    if [ ! -d "$BACKUP_DEST" ]; then
        log_error "Backup directory does not exist: $BACKUP_DEST"
        return "$EXIT_SAFETY"
    fi

    # Find the most recent backup file
    _max_age_minutes=$(( BACKUP_MAX_AGE_HOURS * 60 ))
    _recent=$(find "$BACKUP_DEST" -maxdepth 1 -name "*.tar.gz" -o -name "*.sql.gz" \
        | head -1)

    if [ -z "$_recent" ]; then
        log_error "No backup files found in $BACKUP_DEST"
        return "$EXIT_SAFETY"
    fi

    # Check age of newest backup
    _newest=""
    _newest_age=999999999
    for _f in "$BACKUP_DEST"/*.tar.gz "$BACKUP_DEST"/*.sql.gz; do
        [ -f "$_f" ] || continue
        _age=$(( $(date +%s) - $(date -r "$_f" +%s) ))
        if [ "$_age" -lt "$_newest_age" ]; then
            _newest="$_f"
            _newest_age="$_age"
        fi
    done

    _max_age_seconds=$(( BACKUP_MAX_AGE_HOURS * 3600 ))
    if [ "$_newest_age" -gt "$_max_age_seconds" ]; then
        _hours=$(( _newest_age / 3600 ))
        log_error "Most recent backup is ${_hours}h old (max: ${BACKUP_MAX_AGE_HOURS}h): $_newest"
        return "$EXIT_SAFETY"
    fi

    log_info "Recent backup verified: $_newest (age: $(( _newest_age / 60 ))m)"
    return 0
}
```

**Step 4: Run test to verify it passes**

Run: `sh tests/test_backup_check.sh`
Expected: All tests PASS

**Step 5: Commit**

```sh
chmod +x lib/backup_check.sh
git add lib/backup_check.sh tests/test_backup_check.sh
git commit -m "feat: add lib/backup_check.sh safety gate for destructive operations"
```

---

## Task 8: bin/it — Unified Dispatcher

**Files:**
- Create: `bin/it`
- Create: `tests/test_dispatcher.sh`

**Step 1: Write the failing test**

Create `tests/test_dispatcher.sh`:

```sh
#!/bin/sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/test_helper.sh"

# --- Help output ---
test_start "dispatcher_help_shows_usage"
_output=$("$PROJECT_ROOT/bin/it" help 2>&1 || true)
assert_contains "$_output" "Usage"

# --- List shows products ---
test_start "dispatcher_list_shows_products"
# Create a dummy product for testing
_dummy_dir="$PROJECT_ROOT/products/testprod"
mkdir -p "$_dummy_dir"
cat > "$_dummy_dir/dummy.sh" << 'EOF'
#!/bin/sh
# description: A test tool
run() { echo "dummy output"; }
if [ "${0##*/}" = "dummy.sh" ]; then run "$@"; fi
EOF
chmod +x "$_dummy_dir/dummy.sh"

_output=$("$PROJECT_ROOT/bin/it" list 2>&1 || true)
assert_contains "$_output" "testprod"

# --- Unknown product ---
test_start "dispatcher_unknown_product_fails"
_result=0
"$PROJECT_ROOT/bin/it" nonexistent monitor 2>/dev/null || _result=$?
assert_false "0"

# Cleanup
rm -rf "$_dummy_dir"

test_summary
```

**Step 2: Run test to verify it fails**

Run: `sh tests/test_dispatcher.sh`
Expected: FAIL — bin/it doesn't exist

**Step 3: Write the implementation**

Create `bin/it`:

```sh
#!/bin/sh
# bin/it — Unified dispatcher for it-tools
# Auto-discovers products under products/<name>/ and tools within them
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$PROJECT_ROOT/lib/common.sh"

VERSION="0.1.0"

# ---- Usage ----

show_usage() {
    cat >&2 << EOF
it-tools v$VERSION — IT Administration Automation Toolkit

Usage:
  it <product> <tool> [options]    Run a tool for a product
  it <product> list                List available tools for a product
  it list                          List available products
  it help                          Show this help message
  it version                       Show version

Examples:
  it glpi monitor                  Run GLPI health check
  it glpi backup                   Run GLPI backup
  it glpi purge --dry-run          Preview GLPI purge
  it glpi list                     List GLPI tools

Options (passed to tools):
  --dry-run       Preview changes without executing
  --verbose       Enable debug-level logging
  --quiet         Suppress all output except errors
  --help          Show tool-specific help
EOF
}

# ---- Product/Tool Discovery ----

list_products() {
    _products_dir="$PROJECT_ROOT/products"
    if [ ! -d "$_products_dir" ]; then
        log_error "Products directory not found: $_products_dir"
        exit "$EXIT_CONFIG"
    fi
    printf "Available products:\n"
    for _prod_dir in "$_products_dir"/*/; do
        [ -d "$_prod_dir" ] || continue
        _name=$(basename "$_prod_dir")
        # Count tools
        _count=0
        for _t in "$_prod_dir"/*.sh; do
            [ -f "$_t" ] && _count=$(( _count + 1 ))
        done
        printf "  %-20s (%d tools)\n" "$_name" "$_count"
    done
}

list_tools() {
    _product="$1"
    _prod_dir="$PROJECT_ROOT/products/$_product"
    if [ ! -d "$_prod_dir" ]; then
        log_error "Unknown product: $_product"
        exit "$EXIT_CONFIG"
    fi
    printf "Available tools for %s:\n" "$_product"
    for _tool_path in "$_prod_dir"/*.sh; do
        [ -f "$_tool_path" ] || continue
        _tool_name=$(basename "$_tool_path" .sh)
        _desc=$(grep '^# description:' "$_tool_path" | head -1 | sed 's/^# description: *//')
        _desc="${_desc:-No description}"
        printf "  %-20s %s\n" "$_tool_name" "$_desc"
    done
}

# ---- Main Dispatch ----

if [ $# -eq 0 ]; then
    show_usage
    exit 0
fi

case "$1" in
    help|--help|-h)
        show_usage
        exit 0
        ;;
    version|--version)
        printf "it-tools v%s\n" "$VERSION"
        exit 0
        ;;
    list)
        list_products
        exit 0
        ;;
esac

# Expect: it <product> <tool> [args...]
_product="$1"
shift

_prod_dir="$PROJECT_ROOT/products/$_product"
if [ ! -d "$_prod_dir" ]; then
    log_error "Unknown product: $_product"
    printf "Run 'it list' to see available products.\n" >&2
    exit "$EXIT_CONFIG"
fi

if [ $# -eq 0 ] || [ "$1" = "list" ]; then
    list_tools "$_product"
    exit 0
fi

_tool="$1"
shift

_tool_path="$_prod_dir/${_tool}.sh"
if [ ! -f "$_tool_path" ]; then
    log_error "Unknown tool: $_tool (product: $_product)"
    printf "Run 'it %s list' to see available tools.\n" "$_product" >&2
    exit "$EXIT_CONFIG"
fi

# Dispatch to the tool
exec sh "$_tool_path" "$@"
```

**Step 4: Run test to verify it passes**

```sh
chmod +x bin/it
sh tests/test_dispatcher.sh
```
Expected: All tests PASS

**Step 5: Commit**

```sh
rm -f bin/.gitkeep
git add bin/it tests/test_dispatcher.sh
git commit -m "feat: add bin/it unified dispatcher with product/tool discovery"
```

---

## Task 9: products/glpi/glpi.conf.example — Config Template

**Files:**
- Create: `products/glpi/glpi.conf.example`

**Step 1: Create the config template**

Create `products/glpi/glpi.conf.example` — copy the full config reference from the design doc (§Config File Reference). This is the complete file from the design document.

**Step 2: Commit**

```sh
rm -f products/glpi/.gitkeep
git add products/glpi/glpi.conf.example
git commit -m "feat: add GLPI config template"
```

---

## Task 10: products/glpi/monitor.sh — Health Check

**Files:**
- Create: `products/glpi/monitor.sh`

**Step 1: Write the implementation**

Create `products/glpi/monitor.sh`:

```sh
#!/bin/sh
# description: Full stack health check for GLPI
# usage: it glpi monitor [--verbose] [--quiet]
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

. "$PROJECT_ROOT/lib/common.sh"
. "$PROJECT_ROOT/lib/alert.sh"
. "$PROJECT_ROOT/lib/db.sh"

# ---- Config ----
_CONFIG_FILE="$SCRIPT_DIR/glpi.conf"
if [ -f "$_CONFIG_FILE" ]; then
    load_config "$_CONFIG_FILE"
fi

GLPI_URL="${GLPI_URL:-}"
MONITOR_DISK_WARN_PCT="${MONITOR_DISK_WARN_PCT:-80}"
MONITOR_DISK_CRIT_PCT="${MONITOR_DISK_CRIT_PCT:-95}"
GLPI_INSTALL_PATH="${GLPI_INSTALL_PATH:-/var/www/html/glpi}"

# ---- Parse flags ----
parse_common_flags "$@" || {
    cat >&2 << EOF
Usage: it glpi monitor [--verbose] [--quiet]

Performs full stack health check:
  - DNS resolution
  - HTTP(S) response
  - Apache service
  - MariaDB service
  - PHP availability
  - Disk space
EOF
    exit 0
}

# ---- Checks ----

_failed_checks=""

_record_failure() {
    _check="$1"
    _detail="$2"
    collect_error "$_check: $_detail"
    if [ -z "$_failed_checks" ]; then
        _failed_checks="$_check"
    else
        _failed_checks="$_failed_checks, $_check"
    fi
}

check_dns() {
    if [ -z "$GLPI_URL" ]; then
        log_warn "GLPI_URL not configured, skipping DNS check"
        return 0
    fi
    _hostname=$(echo "$GLPI_URL" | sed 's|https\?://||' | sed 's|/.*||' | sed 's|:.*||')
    log_debug "Checking DNS resolution: $_hostname"
    if retry_cmd nslookup "$_hostname" >/dev/null 2>&1; then
        log_info "DNS OK: $_hostname"
    else
        _record_failure "DNS" "Cannot resolve $_hostname"
    fi
}

check_http() {
    if [ -z "$GLPI_URL" ]; then
        log_warn "GLPI_URL not configured, skipping HTTP check"
        return 0
    fi
    log_debug "Checking HTTP response: $GLPI_URL"
    _status=$(retry_cmd curl -s -o /dev/null -w '%{http_code}' \
        --max-time 10 "$GLPI_URL" 2>/dev/null) || _status="000"
    if [ "$_status" -ge 200 ] 2>/dev/null && [ "$_status" -lt 400 ] 2>/dev/null; then
        log_info "HTTP OK: $GLPI_URL (status: $_status)"
    else
        _record_failure "HTTP" "$GLPI_URL returned status $_status"
    fi
}

check_service() {
    _svc_name="$1"
    log_debug "Checking service: $_svc_name"
    if systemctl is-active "$_svc_name" >/dev/null 2>&1; then
        log_info "Service OK: $_svc_name"
    else
        _record_failure "Service" "$_svc_name is not running"
    fi
}

check_mariadb_connectivity() {
    log_debug "Checking MariaDB connectivity"
    if retry_cmd mysqladmin ping -h "$_DB_HOST" -u "$_DB_USER" \
        --password="$_DB_PASS" >/dev/null 2>&1; then
        log_info "MariaDB OK: connectivity verified"
    else
        _record_failure "MariaDB" "Cannot connect to database"
    fi
}

check_php() {
    log_debug "Checking PHP availability"
    if command -v php >/dev/null 2>&1; then
        _php_version=$(php -v 2>/dev/null | head -1)
        log_info "PHP OK: $_php_version"
    else
        _record_failure "PHP" "php command not found"
        return
    fi
    # Check if PHP-FPM is running (if applicable)
    if systemctl list-units --type=service 2>/dev/null | grep -q "php.*fpm"; then
        _fpm_svc=$(systemctl list-units --type=service 2>/dev/null \
            | grep "php.*fpm" | awk '{print $1}' | head -1)
        if systemctl is-active "$_fpm_svc" >/dev/null 2>&1; then
            log_info "PHP-FPM OK: $_fpm_svc"
        else
            _record_failure "PHP-FPM" "$_fpm_svc is not running"
        fi
    fi
}

check_disk() {
    log_debug "Checking disk space for: $GLPI_INSTALL_PATH"
    _usage=$(df "$GLPI_INSTALL_PATH" 2>/dev/null | tail -1 | awk '{print $5}' \
        | tr -d '%')
    if [ -z "$_usage" ]; then
        _record_failure "Disk" "Cannot determine disk usage for $GLPI_INSTALL_PATH"
        return
    fi
    if [ "$_usage" -ge "$MONITOR_DISK_CRIT_PCT" ]; then
        _record_failure "Disk" "CRITICAL: ${_usage}% used (threshold: ${MONITOR_DISK_CRIT_PCT}%)"
    elif [ "$_usage" -ge "$MONITOR_DISK_WARN_PCT" ]; then
        log_warn "Disk WARNING: ${_usage}% used (threshold: ${MONITOR_DISK_WARN_PCT}%)"
    else
        log_info "Disk OK: ${_usage}% used"
    fi
}

# ---- Main ----

log_info "Starting GLPI health check"

# Load DB credentials for connectivity test
db_load_credentials 2>/dev/null || log_warn "DB credentials not available, skipping DB check"

check_dns
check_http
check_service "apache2"
check_service "mariadb"
if [ -n "$_DB_HOST" ]; then
    check_mariadb_connectivity
fi
check_php
check_disk

# Report results
if has_errors; then
    _summary="GLPI health check FAILED: $_failed_checks"
    _details=$(get_errors)
    log_error "$_summary"
    send_alert "$_summary" "$_details" "monitor"
    exit "$EXIT_SERVICE"
else
    log_info "GLPI health check PASSED — all checks OK"
    exit "$EXIT_OK"
fi
```

**Step 2: Make executable and commit**

```sh
chmod +x products/glpi/monitor.sh
git add products/glpi/monitor.sh
git commit -m "feat: add products/glpi/monitor.sh full stack health check"
```

---

## Task 11: products/glpi/backup.sh — Full Backup

**Files:**
- Create: `products/glpi/backup.sh`

**Step 1: Write the implementation**

Create `products/glpi/backup.sh`:

```sh
#!/bin/sh
# description: Full backup of GLPI (database + files + webroot)
# usage: it glpi backup [--dry-run] [--verbose] [--quiet]
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

. "$PROJECT_ROOT/lib/common.sh"
. "$PROJECT_ROOT/lib/alert.sh"
. "$PROJECT_ROOT/lib/db.sh"

# ---- Config ----
_CONFIG_FILE="$SCRIPT_DIR/glpi.conf"
if [ -f "$_CONFIG_FILE" ]; then
    load_config "$_CONFIG_FILE"
fi

BACKUP_DEST="${BACKUP_DEST:-}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
BACKUP_VERIFY="${BACKUP_VERIFY:-false}"
BACKUP_KEEP_PARTIAL="${BACKUP_KEEP_PARTIAL:-true}"
BACKUP_VERIFY_MOUNT="${BACKUP_VERIFY_MOUNT:-true}"
GLPI_INSTALL_PATH="${GLPI_INSTALL_PATH:-/var/www/html/glpi}"

# ---- Parse flags ----
parse_common_flags "$@" || {
    cat >&2 << EOF
Usage: it glpi backup [--dry-run] [--verbose] [--quiet]

Creates a full backup:
  1. MariaDB database dump
  2. GLPI files directory
  3. Full webroot
  4. Applies retention policy
  5. Optional integrity verification
EOF
    exit 0
}

# ---- Pre-flight ----

require_arg "BACKUP_DEST" "$BACKUP_DEST"
require_arg "GLPI_INSTALL_PATH" "$GLPI_INSTALL_PATH"

# Verify mount point (design doc §16)
if [ "$BACKUP_VERIFY_MOUNT" = "true" ] && [ "$DRY_RUN" != "true" ]; then
    if ! mountpoint -q "$BACKUP_DEST" 2>/dev/null; then
        log_error "Backup destination is not a mount point: $BACKUP_DEST"
        send_alert "Backup FAILED" "Destination is not mounted: $BACKUP_DEST" "backup"
        exit "$EXIT_FILESYSTEM"
    fi
fi

# Lock (design doc §10)
_LOCK_FILE="${PROJECT_ROOT}/logs/glpi-backup.lock"
acquire_lock "$_LOCK_FILE"
trap 'release_lock "$_LOCK_FILE"' EXIT INT TERM

# ---- Backup ----

_TIMESTAMP=$(date '+%Y-%m-%d-%H%M%S')
_BACKUP_DIR="$BACKUP_DEST/glpi-backup-$_TIMESTAMP"
_PARTIAL=false

log_info "Starting GLPI backup to $_BACKUP_DIR"

if [ "$DRY_RUN" != "true" ]; then
    mkdir -p "$_BACKUP_DIR"
fi

# 1. Database dump
log_info "Step 1/3: Database dump"
db_load_credentials
_DB_DUMP="$_BACKUP_DIR/glpi-db-$_TIMESTAMP.sql"
if [ "$DRY_RUN" = "true" ]; then
    log_info "[dry-run] Would dump database $_DB_NAME to $_DB_DUMP"
else
    if retry_cmd db_dump "$_DB_DUMP" "--single-transaction --quick"; then
        log_info "Database dump complete: $_DB_DUMP"
        gzip "$_DB_DUMP"
        log_debug "Compressed: ${_DB_DUMP}.gz"
    else
        collect_error "Database dump failed"
        _PARTIAL=true
    fi
fi

# 2. Files directory
log_info "Step 2/3: GLPI files directory"
_FILES_TAR="$_BACKUP_DIR/glpi-files-$_TIMESTAMP.tar.gz"
_FILES_DIR="$GLPI_INSTALL_PATH/files"
if [ "$DRY_RUN" = "true" ]; then
    log_info "[dry-run] Would archive $GLPI_INSTALL_PATH/files/"
elif [ -d "$_FILES_DIR" ]; then
    if tar -czf "$_FILES_TAR" -C "$(dirname "$_FILES_DIR")" "$(basename "$_FILES_DIR")" 2>/dev/null; then
        log_info "Files archive complete: $_FILES_TAR"
    else
        collect_error "Files directory archive failed"
        _PARTIAL=true
    fi
else
    log_warn "Files directory not found: $_FILES_DIR"
    collect_error "Files directory not found: $_FILES_DIR"
    _PARTIAL=true
fi

# 3. Full webroot
log_info "Step 3/3: Full webroot"
_WEBROOT_TAR="$_BACKUP_DIR/glpi-webroot-$_TIMESTAMP.tar.gz"
if [ "$DRY_RUN" = "true" ]; then
    log_info "[dry-run] Would archive $GLPI_INSTALL_PATH"
elif [ -d "$GLPI_INSTALL_PATH" ]; then
    if tar -czf "$_WEBROOT_TAR" -C "$(dirname "$GLPI_INSTALL_PATH")" \
        "$(basename "$GLPI_INSTALL_PATH")" \
        --exclude='files' 2>/dev/null; then
        log_info "Webroot archive complete: $_WEBROOT_TAR"
    else
        collect_error "Webroot archive failed"
        _PARTIAL=true
    fi
else
    log_error "GLPI install path not found: $GLPI_INSTALL_PATH"
    collect_error "Webroot not found: $GLPI_INSTALL_PATH"
    _PARTIAL=true
fi

# ---- Partial backup handling (design doc §11) ----
if [ "$_PARTIAL" = "true" ] && [ "$DRY_RUN" != "true" ]; then
    if [ "$BACKUP_KEEP_PARTIAL" = "true" ]; then
        touch "$_BACKUP_DIR/.partial"
        log_warn "Backup is partial — marked with .partial flag"
    else
        log_warn "Cleaning up partial backup: $_BACKUP_DIR"
        rm -rf "$_BACKUP_DIR"
    fi
fi

# ---- Integrity verification (optional) ----
if [ "$BACKUP_VERIFY" = "true" ] && [ "$DRY_RUN" != "true" ] && [ -d "$_BACKUP_DIR" ]; then
    log_info "Verifying backup integrity"
    _verify_ok=true
    for _archive in "$_BACKUP_DIR"/*.tar.gz; do
        [ -f "$_archive" ] || continue
        if ! tar -tzf "$_archive" >/dev/null 2>&1; then
            collect_error "Archive verification failed: $_archive"
            _verify_ok=false
        fi
    done
    for _sqldump in "$_BACKUP_DIR"/*.sql.gz; do
        [ -f "$_sqldump" ] || continue
        if ! gzip -t "$_sqldump" 2>/dev/null; then
            collect_error "SQL dump verification failed: $_sqldump"
            _verify_ok=false
        fi
    done
    if [ "$_verify_ok" = "true" ]; then
        log_info "Backup integrity verified"
    fi
fi

# ---- Retention policy ----
if [ "$DRY_RUN" != "true" ]; then
    log_info "Applying retention policy: ${BACKUP_RETENTION_DAYS} days"
    find "$BACKUP_DEST" -maxdepth 1 -name "glpi-backup-*" -type d \
        -mtime +"$BACKUP_RETENTION_DAYS" | while read -r _old_backup; do
        log_info "Removing old backup: $_old_backup"
        rm -rf "$_old_backup"
    done
else
    log_info "[dry-run] Would remove backups older than $BACKUP_RETENTION_DAYS days"
fi

# ---- Report ----
if has_errors; then
    _summary="GLPI backup completed with errors"
    _details=$(get_errors)
    log_error "$_summary"
    send_alert "$_summary" "$_details" "backup"
    exit "$EXIT_PARTIAL"
else
    log_info "GLPI backup completed successfully: $_BACKUP_DIR"
    exit "$EXIT_OK"
fi
```

**Step 2: Make executable and commit**

```sh
chmod +x products/glpi/backup.sh
git add products/glpi/backup.sh
git commit -m "feat: add products/glpi/backup.sh with mount check, retention, verification"
```

---

## Task 12: products/glpi/purge.sh — Partial Purge

**Files:**
- Create: `products/glpi/purge.sh`

**Step 1: Write the implementation**

Create `products/glpi/purge.sh`:

```sh
#!/bin/sh
# description: Purge old data from GLPI (tickets, logs, notifications, trash)
# usage: it glpi purge [--dry-run] [--verbose] [--quiet]
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

. "$PROJECT_ROOT/lib/common.sh"
. "$PROJECT_ROOT/lib/alert.sh"
. "$PROJECT_ROOT/lib/db.sh"
. "$PROJECT_ROOT/lib/backup_check.sh"

# ---- Config ----
_CONFIG_FILE="$SCRIPT_DIR/glpi.conf"
if [ -f "$_CONFIG_FILE" ]; then
    load_config "$_CONFIG_FILE"
fi

PURGE_CLOSED_TICKETS_MONTHS="${PURGE_CLOSED_TICKETS_MONTHS:-0}"
PURGE_LOGS_MONTHS="${PURGE_LOGS_MONTHS:-0}"
PURGE_NOTIFICATIONS_MONTHS="${PURGE_NOTIFICATIONS_MONTHS:-0}"
PURGE_TRASH_MONTHS="${PURGE_TRASH_MONTHS:-0}"
MAINTENANCE_MODE_ENABLED="${MAINTENANCE_MODE_ENABLED:-false}"
GLPI_INSTALL_PATH="${GLPI_INSTALL_PATH:-/var/www/html/glpi}"

# ---- Parse flags ----
parse_common_flags "$@" || {
    cat >&2 << EOF
Usage: it glpi purge [--dry-run] [--verbose] [--quiet]

Purges old data from GLPI. Each target is configured by threshold in months
(0 = disabled):
  - Closed tickets:      PURGE_CLOSED_TICKETS_MONTHS
  - Event logs:          PURGE_LOGS_MONTHS
  - Notification queue:  PURGE_NOTIFICATIONS_MONTHS
  - Trashed items:       PURGE_TRASH_MONTHS

Requires a recent backup before proceeding (safety gate).
EOF
    exit 0
}

# ---- Pre-flight ----

# Safety gate (design doc §5)
check_recent_backup

# Lock (design doc §10)
_LOCK_FILE="${PROJECT_ROOT}/logs/glpi-purge.lock"
acquire_lock "$_LOCK_FILE"
trap 'release_lock "$_LOCK_FILE"' EXIT INT TERM

# Load DB credentials
db_load_credentials

# ---- Maintenance mode (design doc §17) ----

_maintenance_enabled=false

enable_maintenance() {
    if [ "$MAINTENANCE_MODE_ENABLED" = "true" ] && [ "$DRY_RUN" != "true" ]; then
        _maint_file="$GLPI_INSTALL_PATH/files/_cache/maintenance_mode"
        if [ -d "$(dirname "$_maint_file")" ]; then
            touch "$_maint_file"
            _maintenance_enabled=true
            log_info "GLPI maintenance mode enabled"
        fi
    fi
}

disable_maintenance() {
    if [ "$_maintenance_enabled" = "true" ]; then
        _maint_file="$GLPI_INSTALL_PATH/files/_cache/maintenance_mode"
        rm -f "$_maint_file"
        log_info "GLPI maintenance mode disabled"
    fi
}

# ---- Purge Functions ----

_total_purged=0

purge_closed_tickets() {
    _months="$PURGE_CLOSED_TICKETS_MONTHS"
    if [ "$_months" -eq 0 ]; then
        log_debug "Closed ticket purge disabled"
        return 0
    fi
    _cutoff_date=$(date -d "$_months months ago" '+%Y-%m-%d' 2>/dev/null || \
                   date -v-"${_months}m" '+%Y-%m-%d' 2>/dev/null)
    _where="status = 6 AND date_mod < '$_cutoff_date'"

    _count=$(db_count "glpi_tickets" "$_where" 2>/dev/null || echo "0")
    log_info "Closed tickets to purge: $_count (older than $_cutoff_date)"

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[dry-run] Would delete $_count closed tickets"
        return 0
    fi

    if [ "$_count" -gt 0 ]; then
        db_query "DELETE FROM glpi_tickets WHERE $_where" || {
            collect_error "Failed to purge closed tickets"
            return 1
        }
        _total_purged=$(( _total_purged + _count ))
        log_info "Purged $_count closed tickets"
    fi
}

purge_logs() {
    _months="$PURGE_LOGS_MONTHS"
    if [ "$_months" -eq 0 ]; then
        log_debug "Log purge disabled"
        return 0
    fi
    _cutoff_date=$(date -d "$_months months ago" '+%Y-%m-%d' 2>/dev/null || \
                   date -v-"${_months}m" '+%Y-%m-%d' 2>/dev/null)
    _where="date_mod < '$_cutoff_date'"

    _count=$(db_count "glpi_logs" "$_where" 2>/dev/null || echo "0")
    log_info "Event logs to purge: $_count (older than $_cutoff_date)"

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[dry-run] Would delete $_count event logs"
        return 0
    fi

    if [ "$_count" -gt 0 ]; then
        db_query "DELETE FROM glpi_logs WHERE $_where" || {
            collect_error "Failed to purge event logs"
            return 1
        }
        _total_purged=$(( _total_purged + _count ))
        log_info "Purged $_count event logs"
    fi
}

purge_notifications() {
    _months="$PURGE_NOTIFICATIONS_MONTHS"
    if [ "$_months" -eq 0 ]; then
        log_debug "Notification purge disabled"
        return 0
    fi
    _cutoff_date=$(date -d "$_months months ago" '+%Y-%m-%d' 2>/dev/null || \
                   date -v-"${_months}m" '+%Y-%m-%d' 2>/dev/null)
    _where="create_time < '$_cutoff_date'"

    _count=$(db_count "glpi_queuednotifications" "$_where" 2>/dev/null || echo "0")
    log_info "Notifications to purge: $_count (older than $_cutoff_date)"

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[dry-run] Would delete $_count notifications"
        return 0
    fi

    if [ "$_count" -gt 0 ]; then
        db_query "DELETE FROM glpi_queuednotifications WHERE $_where" || {
            collect_error "Failed to purge notifications"
            return 1
        }
        _total_purged=$(( _total_purged + _count ))
        log_info "Purged $_count notifications"
    fi
}

purge_trash() {
    _months="$PURGE_TRASH_MONTHS"
    if [ "$_months" -eq 0 ]; then
        log_debug "Trash purge disabled"
        return 0
    fi
    _cutoff_date=$(date -d "$_months months ago" '+%Y-%m-%d' 2>/dev/null || \
                   date -v-"${_months}m" '+%Y-%m-%d' 2>/dev/null)
    _where="is_deleted = 1 AND date_mod < '$_cutoff_date'"

    # Purge from main tables that support is_deleted
    for _table in glpi_tickets glpi_computers glpi_monitors glpi_printers \
                  glpi_phones glpi_peripherals glpi_networkequipments \
                  glpi_softwarelicenses; do
        _count=$(db_count "$_table" "$_where" 2>/dev/null || echo "0")
        if [ "$_count" -gt 0 ]; then
            log_info "Trash in $_table: $_count items"
            if [ "$DRY_RUN" = "true" ]; then
                log_info "[dry-run] Would delete $_count trashed items from $_table"
            else
                db_query "DELETE FROM $_table WHERE $_where" || {
                    collect_error "Failed to purge trash from $_table"
                    continue
                }
                _total_purged=$(( _total_purged + _count ))
                log_info "Purged $_count trashed items from $_table"
            fi
        fi
    done
}

# ---- Main ----

log_info "Starting GLPI purge"

enable_maintenance

purge_closed_tickets
purge_logs
purge_notifications
purge_trash

disable_maintenance

# Report
if has_errors; then
    _summary="GLPI purge completed with errors (purged: $_total_purged records)"
    _details=$(get_errors)
    log_error "$_summary"
    send_alert "$_summary" "$_details" "purge"
    exit "$EXIT_PARTIAL"
else
    log_info "GLPI purge completed successfully (purged: $_total_purged records)"
    exit "$EXIT_OK"
fi
```

**Step 2: Make executable and commit**

```sh
chmod +x products/glpi/purge.sh
git add products/glpi/purge.sh
git commit -m "feat: add products/glpi/purge.sh with safety gate, dry-run, maintenance mode"
```

---

## Task 13: products/glpi/archive.sh — Partial Archive

**Files:**
- Create: `products/glpi/archive.sh`

**Step 1: Write the implementation**

Create `products/glpi/archive.sh`:

```sh
#!/bin/sh
# description: Archive old GLPI data (export then delete from live DB)
# usage: it glpi archive [--dry-run] [--verbose] [--quiet] [--months N]
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

. "$PROJECT_ROOT/lib/common.sh"
. "$PROJECT_ROOT/lib/alert.sh"
. "$PROJECT_ROOT/lib/db.sh"
. "$PROJECT_ROOT/lib/backup_check.sh"

# ---- Config ----
_CONFIG_FILE="$SCRIPT_DIR/glpi.conf"
if [ -f "$_CONFIG_FILE" ]; then
    load_config "$_CONFIG_FILE"
fi

ARCHIVE_MODE="${ARCHIVE_MODE:-sqldump}"
ARCHIVE_DB_NAME="${ARCHIVE_DB_NAME:-glpi_archive}"
ARCHIVE_MONTHS="${ARCHIVE_MONTHS:-12}"
MAINTENANCE_MODE_ENABLED="${MAINTENANCE_MODE_ENABLED:-false}"
BACKUP_DEST="${BACKUP_DEST:-}"
GLPI_INSTALL_PATH="${GLPI_INSTALL_PATH:-/var/www/html/glpi}"

# ---- Parse flags ----
# Handle --months N before common flags
_ARGS=""
while [ $# -gt 0 ]; do
    case "$1" in
        --months)
            shift
            ARCHIVE_MONTHS="$1"
            ;;
        *)
            _ARGS="$_ARGS $1"
            ;;
    esac
    shift
done
# shellcheck disable=SC2086
parse_common_flags $_ARGS || {
    cat >&2 << EOF
Usage: it glpi archive [--dry-run] [--verbose] [--quiet] [--months N]

Archives old data from GLPI. Two modes:
  sqldump   — Export to SQL dump file, then delete from live DB
  archivedb — Move records to archive database, then delete from live DB

Options:
  --months N    Override archive threshold (default: $ARCHIVE_MONTHS)
  --dry-run     Preview what would be archived
EOF
    exit 0
}

# ---- Pre-flight ----

check_recent_backup

_LOCK_FILE="${PROJECT_ROOT}/logs/glpi-archive.lock"
acquire_lock "$_LOCK_FILE"
trap 'release_lock "$_LOCK_FILE"' EXIT INT TERM

db_load_credentials

_CUTOFF_DATE=$(date -d "$ARCHIVE_MONTHS months ago" '+%Y-%m-%d' 2>/dev/null || \
               date -v-"${ARCHIVE_MONTHS}m" '+%Y-%m-%d' 2>/dev/null)
_TIMESTAMP=$(date '+%Y-%m-%d-%H%M%S')
_ARCHIVE_DIR="$BACKUP_DEST/glpi-archive-$_TIMESTAMP"

log_info "Starting GLPI archive (mode: $ARCHIVE_MODE, cutoff: $_CUTOFF_DATE)"

# ---- Maintenance mode ----

_maintenance_enabled=false

enable_maintenance() {
    if [ "$MAINTENANCE_MODE_ENABLED" = "true" ] && [ "$DRY_RUN" != "true" ]; then
        _maint_file="$GLPI_INSTALL_PATH/files/_cache/maintenance_mode"
        if [ -d "$(dirname "$_maint_file")" ]; then
            touch "$_maint_file"
            _maintenance_enabled=true
            log_info "GLPI maintenance mode enabled"
        fi
    fi
}

disable_maintenance() {
    if [ "$_maintenance_enabled" = "true" ]; then
        _maint_file="$GLPI_INSTALL_PATH/files/_cache/maintenance_mode"
        rm -f "$_maint_file"
        log_info "GLPI maintenance mode disabled"
    fi
}

# ---- Archive: SQL Dump Mode ----

archive_sqldump() {
    _table="$1"
    _where="$2"
    _label="$3"

    _count=$(db_count "$_table" "$_where" 2>/dev/null || echo "0")
    log_info "$_label: $_count records to archive"

    if [ "$_count" -eq 0 ]; then
        return 0
    fi

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[dry-run] Would export $_count records from $_table and delete"
        return 0
    fi

    # Export
    _dump_file="$_ARCHIVE_DIR/${_table}-$_TIMESTAMP.sql"
    db_query "SELECT * FROM $_table WHERE $_where" > "$_dump_file" 2>/dev/null || {
        collect_error "Failed to export $_table for archiving"
        return 1
    }

    # Verify export is non-empty
    if [ ! -s "$_dump_file" ]; then
        collect_error "Archive export is empty: $_dump_file"
        return 1
    fi

    # Delete from live DB
    db_query "DELETE FROM $_table WHERE $_where" || {
        collect_error "Failed to delete archived records from $_table"
        return 1
    }

    gzip "$_dump_file"
    log_info "Archived $_count records from $_table"
}

# ---- Archive: Archive DB Mode ----

archive_to_db() {
    _table="$1"
    _where="$2"
    _label="$3"

    _count=$(db_count "$_table" "$_where" 2>/dev/null || echo "0")
    log_info "$_label: $_count records to archive"

    if [ "$_count" -eq 0 ]; then
        return 0
    fi

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[dry-run] Would move $_count records from $_table to $ARCHIVE_DB_NAME"
        return 0
    fi

    # Insert into archive DB
    db_query "INSERT INTO $ARCHIVE_DB_NAME.$_table SELECT * FROM $_table WHERE $_where" || {
        collect_error "Failed to insert $_table records into archive DB"
        return 1
    }

    # Verify count in archive DB
    _archive_count=$(MYSQL_PWD="$_DB_PASS" mysql -h "$_DB_HOST" -u "$_DB_USER" \
        "$ARCHIVE_DB_NAME" -N -B -e "SELECT COUNT(*) FROM $_table WHERE $_where" \
        2>/dev/null || echo "0")

    if [ "$_archive_count" -lt "$_count" ]; then
        collect_error "Archive verification failed for $_table (expected: $_count, got: $_archive_count)"
        return 1
    fi

    # Delete from live DB
    db_query "DELETE FROM $_table WHERE $_where" || {
        collect_error "Failed to delete archived records from $_table"
        return 1
    }

    log_info "Moved $_count records from $_table to archive DB"
}

# ---- Main ----

enable_maintenance

if [ "$DRY_RUN" != "true" ] && [ "$ARCHIVE_MODE" = "sqldump" ]; then
    mkdir -p "$_ARCHIVE_DIR"
fi

# Select archive function
case "$ARCHIVE_MODE" in
    sqldump)  _archive_fn="archive_sqldump" ;;
    archivedb) _archive_fn="archive_to_db" ;;
    *)
        log_error "Unknown ARCHIVE_MODE: $ARCHIVE_MODE"
        exit "$EXIT_CONFIG"
        ;;
esac

# Archive each data type
"$_archive_fn" "glpi_tickets" \
    "status = 6 AND date_mod < '$_CUTOFF_DATE'" \
    "Closed tickets"

"$_archive_fn" "glpi_logs" \
    "date_mod < '$_CUTOFF_DATE'" \
    "Event logs"

"$_archive_fn" "glpi_queuednotifications" \
    "create_time < '$_CUTOFF_DATE'" \
    "Notifications"

disable_maintenance

# Report
if has_errors; then
    _summary="GLPI archive completed with errors"
    _details=$(get_errors)
    log_error "$_summary"
    send_alert "$_summary" "$_details" "archive"
    exit "$EXIT_PARTIAL"
else
    log_info "GLPI archive completed successfully (cutoff: $_CUTOFF_DATE)"
    exit "$EXIT_OK"
fi
```

**Step 2: Make executable and commit**

```sh
chmod +x products/glpi/archive.sh
git add products/glpi/archive.sh
git commit -m "feat: add products/glpi/archive.sh with sqldump and archivedb modes"
```

---

## Task 14: cron/glpi.cron.example — Cron Templates

**Files:**
- Create: `cron/glpi.cron.example`

**Step 1: Create the file**

Create `cron/glpi.cron.example`:

```cron
# ============================================================
# GLPI cron jobs — it-tools
# Install: crontab -e  (paste these lines)
# ============================================================

# Health monitoring — every 5 minutes
*/5 * * * * /opt/it-tools/bin/it glpi monitor >> /opt/it-tools/logs/cron.log 2>&1

# Full backup — daily at 02:00
0 2 * * * /opt/it-tools/bin/it glpi backup >> /opt/it-tools/logs/cron.log 2>&1

# Purge old data — weekly on Sunday at 03:00
0 3 * * 0 /opt/it-tools/bin/it glpi purge >> /opt/it-tools/logs/cron.log 2>&1

# Archive old data — monthly on 1st at 04:00
0 4 1 * * /opt/it-tools/bin/it glpi archive >> /opt/it-tools/logs/cron.log 2>&1
```

**Step 2: Commit**

```sh
rm -f cron/.gitkeep
git add cron/glpi.cron.example
git commit -m "feat: add cron/glpi.cron.example with scheduling templates"
```

---

## Task 15: install.sh — Interactive + Non-Interactive Installer

**Files:**
- Create: `install.sh`

**Step 1: Write the implementation**

Create `install.sh` — this is the largest script, implementing design decisions 18-26.

The script should implement:
- Privilege auto-detection (§24)
- Dependency checking with user prompt (§26)
- Interactive config generation (§21) for GLPI settings
- PATH setup choice (§19): symlink vs profile
- Cron setup choice (§22)
- File permissions (§23)
- Post-install validation (§25)
- Non-interactive mode via flags (§20)

Full implementation in the script file (too long to inline here — see the code below).

```sh
#!/bin/sh
# install.sh — IT-Tools installer
# Supports interactive (default) and non-interactive (via flags) modes
# Design doc: §18-§26
set -eu

INSTALL_DIR="/opt/it-tools"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ---- Defaults (overridden by flags in non-interactive mode) ----
INSTALL_USER=""
INSTALL_PRODUCT="glpi"
INSTALL_PATH_METHOD=""  # symlink or profile
INSTALL_INTERACTIVE=true
INSTALL_CRON=""  # yes, no, or empty (ask)

# ---- Colors ----
_RED='\033[0;31m'
_GREEN='\033[0;32m'
_YELLOW='\033[0;33m'
_BLUE='\033[0;34m'
_NC='\033[0m'

_info()  { printf "${_BLUE}[INFO]${_NC} %s\n" "$*"; }
_ok()    { printf "${_GREEN}[OK]${_NC} %s\n" "$*"; }
_warn()  { printf "${_YELLOW}[WARN]${_NC} %s\n" "$*"; }
_error() { printf "${_RED}[ERROR]${_NC} %s\n" "$*" >&2; }

_ask() {
    printf "${_BLUE}?${_NC} %s " "$1"
    read -r _answer
    echo "$_answer"
}

_ask_yn() {
    printf "${_BLUE}?${_NC} %s [y/N] " "$1"
    read -r _answer
    case "$_answer" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

# ---- Parse flags (non-interactive mode) ----
while [ $# -gt 0 ]; do
    case "$1" in
        --user)       shift; INSTALL_USER="$1"; INSTALL_INTERACTIVE=false ;;
        --product)    shift; INSTALL_PRODUCT="$1"; INSTALL_INTERACTIVE=false ;;
        --path-method) shift; INSTALL_PATH_METHOD="$1"; INSTALL_INTERACTIVE=false ;;
        --cron)       INSTALL_CRON="yes"; INSTALL_INTERACTIVE=false ;;
        --no-cron)    INSTALL_CRON="no"; INSTALL_INTERACTIVE=false ;;
        --help|-h)
            cat << EOF
Usage: install.sh [options]

Interactive mode (default): walks you through each step.
Non-interactive mode: provide all options via flags.

Options:
  --user <name>        Service user (default: auto-detect)
  --product <name>     Product to configure (default: glpi)
  --path-method <m>    'symlink' or 'profile'
  --cron               Auto-install cron jobs
  --no-cron            Skip cron setup
  --help               Show this help
EOF
            exit 0
            ;;
        *) _error "Unknown option: $1"; exit 1 ;;
    esac
    shift
done

# ---- Privilege detection (§24) ----
_SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    _info "Running as $(whoami) — will use sudo when needed"
    _SUDO="sudo"
else
    _info "Running as root"
fi

# ---- Banner ----
printf "\n"
printf "${_BLUE}╔══════════════════════════════════════╗${_NC}\n"
printf "${_BLUE}║   it-tools installer                 ║${_NC}\n"
printf "${_BLUE}║   IT Administration Automation       ║${_NC}\n"
printf "${_BLUE}╚══════════════════════════════════════╝${_NC}\n"
printf "\n"

# ---- Step 1: Dependency checking (§26) ----
_info "Checking dependencies..."
_MISSING=""
for _cmd in curl tar gzip mysql mysqldump systemctl mountpoint; do
    if command -v "$_cmd" >/dev/null 2>&1; then
        _ok "  Found: $_cmd"
    else
        _warn "  Missing: $_cmd"
        _MISSING="$_MISSING $_cmd"
    fi
done

# Check for mail command
_has_mail=false
for _mail_cmd in mail msmtp sendmail; do
    if command -v "$_mail_cmd" >/dev/null 2>&1; then
        _ok "  Found mail: $_mail_cmd"
        _has_mail=true
        break
    fi
done
if [ "$_has_mail" = "false" ]; then
    _warn "  Missing: mail/msmtp/sendmail (email alerts won't work)"
fi

if [ -n "$_MISSING" ]; then
    _warn "Missing packages:$_MISSING"
    # Map commands to apt packages
    _APT_PKGS=""
    for _m in $_MISSING; do
        case "$_m" in
            mysql|mysqldump) _APT_PKGS="$_APT_PKGS mariadb-client" ;;
            curl)            _APT_PKGS="$_APT_PKGS curl" ;;
            gzip)            _APT_PKGS="$_APT_PKGS gzip" ;;
            *)               ;; # systemctl, mountpoint are in base system
        esac
    done
    if [ -n "$_APT_PKGS" ]; then
        _info "Install command: $_SUDO apt install -y$_APT_PKGS"
        if [ "$INSTALL_INTERACTIVE" = "true" ]; then
            if _ask_yn "Install missing packages now?"; then
                $_SUDO apt install -y $_APT_PKGS
            fi
        else
            _error "Missing dependencies in non-interactive mode. Install manually."
            exit 2
        fi
    fi
fi

# ---- Step 2: Detect service user (§20) ----
if [ -z "$INSTALL_USER" ]; then
    if [ "$INSTALL_INTERACTIVE" = "true" ]; then
        _default_user=$(whoami)
        INSTALL_USER=$(_ask "Service user [$_default_user]:")
        INSTALL_USER="${INSTALL_USER:-$_default_user}"
    else
        INSTALL_USER=$(whoami)
    fi
fi
_info "Service user: $INSTALL_USER"

# ---- Step 3: Create install directory (§18) ----
_info "Installing to: $INSTALL_DIR"
if [ ! -d "$INSTALL_DIR" ]; then
    $_SUDO mkdir -p "$INSTALL_DIR"
fi

# Copy files
$_SUDO cp -r "$SCRIPT_DIR/bin" "$INSTALL_DIR/"
$_SUDO cp -r "$SCRIPT_DIR/lib" "$INSTALL_DIR/"
$_SUDO cp -r "$SCRIPT_DIR/products" "$INSTALL_DIR/"
$_SUDO cp -r "$SCRIPT_DIR/cron" "$INSTALL_DIR/"
$_SUDO cp -r "$SCRIPT_DIR/tests" "$INSTALL_DIR/"
$_SUDO mkdir -p "$INSTALL_DIR/logs"

_ok "Files copied to $INSTALL_DIR"

# ---- Step 4: PATH setup (§19) ----
if [ -z "$INSTALL_PATH_METHOD" ] && [ "$INSTALL_INTERACTIVE" = "true" ]; then
    printf "\nHow should the 'it' command be available?\n"
    printf "  1) Symlink in /usr/local/bin (recommended)\n"
    printf "  2) Add to PATH in shell profile\n"
    _choice=$(_ask "Choice [1]:")
    case "$_choice" in
        2) INSTALL_PATH_METHOD="profile" ;;
        *) INSTALL_PATH_METHOD="symlink" ;;
    esac
fi
INSTALL_PATH_METHOD="${INSTALL_PATH_METHOD:-symlink}"

case "$INSTALL_PATH_METHOD" in
    symlink)
        $_SUDO ln -sf "$INSTALL_DIR/bin/it" /usr/local/bin/it
        _ok "Symlink created: /usr/local/bin/it -> $INSTALL_DIR/bin/it"
        ;;
    profile)
        _profile_file=""
        for _pf in "$HOME/.profile" "$HOME/.bashrc" "$HOME/.bash_profile"; do
            if [ -f "$_pf" ]; then
                _profile_file="$_pf"
                break
            fi
        done
        if [ -n "$_profile_file" ]; then
            if ! grep -q "$INSTALL_DIR/bin" "$_profile_file" 2>/dev/null; then
                echo "export PATH=\"\$PATH:$INSTALL_DIR/bin\"" >> "$_profile_file"
                _ok "Added $INSTALL_DIR/bin to PATH in $_profile_file"
            else
                _info "PATH already configured in $_profile_file"
            fi
        fi
        ;;
esac

# ---- Step 5: Config generation (§21) ----
_CONF_DIR="$INSTALL_DIR/products/$INSTALL_PRODUCT"
_CONF_FILE="$_CONF_DIR/${INSTALL_PRODUCT}.conf"
_CONF_EXAMPLE="$_CONF_DIR/${INSTALL_PRODUCT}.conf.example"

if [ ! -f "$_CONF_FILE" ] && [ -f "$_CONF_EXAMPLE" ]; then
    if [ "$INSTALL_INTERACTIVE" = "true" ]; then
        _info "Configuring $INSTALL_PRODUCT..."
        printf "\n"

        _glpi_url=$(_ask "GLPI URL [https://glpi.company.local]:")
        _glpi_url="${_glpi_url:-https://glpi.company.local}"

        _glpi_path=$(_ask "GLPI install path [/var/www/html/glpi]:")
        _glpi_path="${_glpi_path:-/var/www/html/glpi}"

        _db_auto=$(_ask "Auto-detect DB credentials from GLPI config? [y/N]:")
        case "$_db_auto" in
            [yY]*) _db_auto_detect="true" ;;
            *) _db_auto_detect="false" ;;
        esac

        _db_host="localhost"; _db_name="glpi"; _db_user="glpi"; _db_pass=""
        if [ "$_db_auto_detect" = "false" ]; then
            _db_host=$(_ask "DB host [localhost]:")
            _db_host="${_db_host:-localhost}"
            _db_name=$(_ask "DB name [glpi]:")
            _db_name="${_db_name:-glpi}"
            _db_user=$(_ask "DB user [glpi]:")
            _db_user="${_db_user:-glpi}"
            _db_pass=$(_ask "DB password:")
        fi

        _backup_dest=$(_ask "Backup destination (NAS path) [/mnt/nas/backups/glpi]:")
        _backup_dest="${_backup_dest:-/mnt/nas/backups/glpi}"

        _alert_email=$(_ask "Alert email address [admin@company.local]:")
        _alert_email="${_alert_email:-admin@company.local}"

        # Generate config
        $_SUDO sh -c "cat > '$_CONF_FILE'" << CONFEOF
# GLPI Configuration — it-tools
# Generated by install.sh on $(date '+%Y-%m-%d %H:%M:%S')

# -- GLPI Instance --
GLPI_URL="$_glpi_url"
GLPI_INSTALL_PATH="$_glpi_path"

# -- Database --
DB_AUTO_DETECT=$_db_auto_detect
DB_HOST="$_db_host"
DB_NAME="$_db_name"
DB_USER="$_db_user"
DB_PASS="$_db_pass"

# -- Backup --
BACKUP_DEST="$_backup_dest"
BACKUP_RETENTION_DAYS=30
BACKUP_VERIFY=false

# -- Monitoring --
MONITOR_DISK_WARN_PCT=80
MONITOR_DISK_CRIT_PCT=95

# -- Purge thresholds (months, 0 = disabled) --
PURGE_CLOSED_TICKETS_MONTHS=12
PURGE_LOGS_MONTHS=6
PURGE_NOTIFICATIONS_MONTHS=3
PURGE_TRASH_MONTHS=1

# -- Archive --
ARCHIVE_MODE="sqldump"
ARCHIVE_DB_NAME="glpi_archive"
ARCHIVE_MONTHS=12

# -- Safety --
REQUIRE_RECENT_BACKUP=true
BACKUP_MAX_AGE_HOURS=24
BACKUP_KEEP_PARTIAL=true
BACKUP_VERIFY_MOUNT=true

# -- Maintenance mode --
MAINTENANCE_MODE_ENABLED=false

# -- Lock files --
LOCK_TIMEOUT_MINUTES=120

# -- Retries --
RETRY_COUNT=3
RETRY_DELAY_SECONDS=10

# -- Alerts --
ALERT_CHANNELS="email,log"
ALERT_EMAIL_TO="$_alert_email"
ALERT_TEAMS_WEBHOOK=""
ALERT_SLACK_WEBHOOK=""
ALERT_COOLDOWN_MINUTES=60

# -- Logging --
LOG_DIR=""
LOG_LEVEL="info"

# -- Runtime --
RUN_USER="$INSTALL_USER"
CONFEOF
        _ok "Config generated: $_CONF_FILE"
    else
        $_SUDO cp "$_CONF_EXAMPLE" "$_CONF_FILE"
        _info "Config copied from example — edit $_CONF_FILE manually"
    fi
fi

# ---- Step 6: File permissions (§23) ----
_info "Setting permissions..."
$_SUDO chown -R "${INSTALL_USER}:${INSTALL_USER}" "$INSTALL_DIR"
$_SUDO chmod +x "$INSTALL_DIR"/bin/*
$_SUDO find "$INSTALL_DIR/products" -name "*.sh" -exec chmod +x {} \;
$_SUDO find "$INSTALL_DIR/products" -name "*.conf" -exec chmod 600 {} \;
$_SUDO find "$INSTALL_DIR/products" -name "*.conf.example" -exec chmod 644 {} \;
$_SUDO chmod 700 "$INSTALL_DIR/logs"
_ok "Permissions set"

# ---- Step 7: Cron setup (§22) ----
_CRON_EXAMPLE="$INSTALL_DIR/cron/${INSTALL_PRODUCT}.cron.example"
if [ -f "$_CRON_EXAMPLE" ]; then
    if [ -z "$INSTALL_CRON" ] && [ "$INSTALL_INTERACTIVE" = "true" ]; then
        printf "\nCron entries for %s:\n" "$INSTALL_PRODUCT"
        cat "$_CRON_EXAMPLE"
        printf "\n"
        if _ask_yn "Install these cron entries for user $INSTALL_USER?"; then
            INSTALL_CRON="yes"
        else
            INSTALL_CRON="no"
        fi
    fi
    if [ "$INSTALL_CRON" = "yes" ]; then
        _existing=$(crontab -u "$INSTALL_USER" -l 2>/dev/null || true)
        if echo "$_existing" | grep -q "it-tools"; then
            _info "Cron entries already exist, skipping"
        else
            ( echo "$_existing"; echo ""; cat "$_CRON_EXAMPLE" ) | \
                $_SUDO crontab -u "$INSTALL_USER" -
            _ok "Cron entries installed for $INSTALL_USER"
        fi
    else
        _info "Skipped cron setup. Install manually from: $_CRON_EXAMPLE"
    fi
fi

# ---- Step 8: Post-install validation (§25) ----
printf "\n"
_info "Running post-install validation..."

# Source config for validation
if [ -f "$_CONF_FILE" ]; then
    . "$_CONF_FILE"
fi

# Test DB connectivity
_val_db=false
if command -v mysqladmin >/dev/null 2>&1 && [ -n "${DB_HOST:-}" ]; then
    if [ "${DB_AUTO_DETECT:-false}" = "true" ]; then
        _ok "  DB: auto-detect mode (will be tested at runtime)"
        _val_db=true
    elif MYSQL_PWD="${DB_PASS:-}" mysqladmin ping \
        -h "${DB_HOST:-localhost}" -u "${DB_USER:-}" >/dev/null 2>&1; then
        _ok "  DB: MariaDB is reachable"
        _val_db=true
    else
        _warn "  DB: Cannot connect to MariaDB at ${DB_HOST:-localhost}"
    fi
else
    _warn "  DB: mysqladmin not available or DB_HOST not set"
fi

# Test HTTP
_val_http=false
if [ -n "${GLPI_URL:-}" ]; then
    _http_status=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 \
        "${GLPI_URL}" 2>/dev/null || echo "000")
    if [ "$_http_status" -ge 200 ] 2>/dev/null && [ "$_http_status" -lt 400 ] 2>/dev/null; then
        _ok "  HTTP: $GLPI_URL responds (status: $_http_status)"
        _val_http=true
    else
        _warn "  HTTP: $GLPI_URL returned status $_http_status"
    fi
else
    _warn "  HTTP: GLPI_URL not configured"
fi

# Test NAS mount
_val_nas=false
if [ -n "${BACKUP_DEST:-}" ]; then
    if mountpoint -q "$BACKUP_DEST" 2>/dev/null; then
        _ok "  NAS: $BACKUP_DEST is mounted"
        _val_nas=true
    else
        _warn "  NAS: $BACKUP_DEST is not a mount point"
    fi
else
    _warn "  NAS: BACKUP_DEST not configured"
fi

# ---- Done ----
printf "\n"
printf "${_GREEN}╔══════════════════════════════════════╗${_NC}\n"
printf "${_GREEN}║   Installation complete!             ║${_NC}\n"
printf "${_GREEN}╚══════════════════════════════════════╝${_NC}\n"
printf "\n"
_info "Install directory: $INSTALL_DIR"
_info "Config file: $_CONF_FILE"
_info "Try: it $INSTALL_PRODUCT list"
printf "\n"
```

**Step 2: Make executable and commit**

```sh
chmod +x install.sh
git add install.sh
git commit -m "feat: add install.sh with interactive/non-interactive modes and validation"
```

---

## Task 16: uninstall.sh — Clean Removal

**Files:**
- Create: `uninstall.sh`

**Step 1: Write the implementation**

Create `uninstall.sh`:

```sh
#!/bin/sh
# uninstall.sh — Clean removal of it-tools
# Design doc §27
set -eu

INSTALL_DIR="/opt/it-tools"

_RED='\033[0;31m'
_GREEN='\033[0;32m'
_YELLOW='\033[0;33m'
_BLUE='\033[0;34m'
_NC='\033[0m'

_info()  { printf "${_BLUE}[INFO]${_NC} %s\n" "$*"; }
_ok()    { printf "${_GREEN}[OK]${_NC} %s\n" "$*"; }
_warn()  { printf "${_YELLOW}[WARN]${_NC} %s\n" "$*"; }
_error() { printf "${_RED}[ERROR]${_NC} %s\n" "$*" >&2; }

_ask_yn() {
    printf "${_BLUE}?${_NC} %s [y/N] " "$1"
    read -r _answer
    case "$_answer" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

# ---- Parse flags ----
_KEEP_CONFIG=false
_PURGE_ALL=false
_INTERACTIVE=true

while [ $# -gt 0 ]; do
    case "$1" in
        --keep-config) _KEEP_CONFIG=true; _INTERACTIVE=false ;;
        --purge)       _PURGE_ALL=true; _INTERACTIVE=false ;;
        --help|-h)
            cat << EOF
Usage: uninstall.sh [--keep-config | --purge]

Options:
  --keep-config   Remove tools but preserve config files and logs
  --purge         Remove everything including configs and logs
  (default)       Interactive — asks what to keep
EOF
            exit 0
            ;;
        *) _error "Unknown option: $1"; exit 1 ;;
    esac
    shift
done

_SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    _SUDO="sudo"
fi

printf "\n"
printf "${_RED}╔══════════════════════════════════════╗${_NC}\n"
printf "${_RED}║   it-tools uninstaller               ║${_NC}\n"
printf "${_RED}╚══════════════════════════════════════╝${_NC}\n"
printf "\n"

if [ ! -d "$INSTALL_DIR" ]; then
    _error "it-tools not found at $INSTALL_DIR"
    exit 1
fi

# ---- Config preservation ----
if [ "$_INTERACTIVE" = "true" ]; then
    if _ask_yn "Keep config files and logs?"; then
        _KEEP_CONFIG=true
    fi
fi

# ---- Remove symlink ----
if [ -L "/usr/local/bin/it" ]; then
    $_SUDO rm -f /usr/local/bin/it
    _ok "Removed symlink: /usr/local/bin/it"
fi

# ---- Remove PATH entries ----
for _pf in "$HOME/.profile" "$HOME/.bashrc" "$HOME/.bash_profile"; do
    if [ -f "$_pf" ] && grep -q "$INSTALL_DIR/bin" "$_pf" 2>/dev/null; then
        _tmp=$(mktemp)
        grep -v "$INSTALL_DIR/bin" "$_pf" > "$_tmp"
        mv "$_tmp" "$_pf"
        _ok "Removed PATH entry from $_pf"
    fi
done

# ---- Remove cron entries ----
_cron_user=$(whoami)
_existing=$(crontab -u "$_cron_user" -l 2>/dev/null || true)
if echo "$_existing" | grep -q "it-tools\|$INSTALL_DIR"; then
    echo "$_existing" | grep -v "it-tools\|$INSTALL_DIR" | \
        crontab -u "$_cron_user" -
    _ok "Removed cron entries for $_cron_user"
fi

# ---- Backup configs if keeping ----
if [ "$_KEEP_CONFIG" = "true" ]; then
    _backup_dir="/tmp/it-tools-config-backup-$(date '+%Y%m%d%H%M%S')"
    mkdir -p "$_backup_dir"
    # Copy config files
    find "$INSTALL_DIR/products" -name "*.conf" -exec cp {} "$_backup_dir/" \; 2>/dev/null || true
    # Copy logs
    cp -r "$INSTALL_DIR/logs" "$_backup_dir/" 2>/dev/null || true
    _ok "Configs and logs backed up to: $_backup_dir"
fi

# ---- Remove install directory ----
if [ "$_INTERACTIVE" = "true" ]; then
    if _ask_yn "Remove $INSTALL_DIR?"; then
        $_SUDO rm -rf "$INSTALL_DIR"
        _ok "Removed: $INSTALL_DIR"
    else
        _info "Skipped removal of $INSTALL_DIR"
    fi
else
    $_SUDO rm -rf "$INSTALL_DIR"
    _ok "Removed: $INSTALL_DIR"
fi

printf "\n"
_ok "it-tools has been uninstalled"
if [ "$_KEEP_CONFIG" = "true" ]; then
    _info "Config backup: $_backup_dir"
fi
printf "\n"
```

**Step 2: Make executable and commit**

```sh
chmod +x uninstall.sh
git add uninstall.sh
git commit -m "feat: add uninstall.sh with config preservation option"
```

---

## Task 17: CLAUDE.md — Project Documentation

**Files:**
- Create: `CLAUDE.md`

**Step 1: Create CLAUDE.md**

```markdown
# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

it-tools is a POSIX sh CLI toolkit for automating IT administration tasks. The first product module is GLPI (open-source ITSM). The framework supports multiple products under `products/<name>/`.

## Shell Constraints

All scripts MUST be POSIX sh compliant (`#!/bin/sh`, `set -eu`). No bash-isms:
- No `[[ ]]` — use `[ ]`
- No arrays — use space-separated strings or positional parameters
- No `${var,,}` — use `tr '[:upper:]' '[:lower:]'`
- No `<<<` here-strings — use `echo ... | cmd`
- No `source` — use `.`

## Architecture

- `bin/it` — Dispatcher. Auto-discovers products in `products/` and tools within them
- `lib/common.sh` — Logging, exit codes, lock files, retries, error collection
- `lib/alert.sh` — Multi-channel alerts (email, Teams, Slack, log) with cooldown
- `lib/db.sh` — DB credential loading (direct or GLPI auto-detect), query/dump helpers
- `lib/backup_check.sh` — Safety gate: verify recent backup before destructive ops
- `products/<name>/<tool>.sh` — Product-specific tools. Each has `# description:` comment

## Exit Codes

0=OK, 1=Config, 2=Dependency, 3=Database, 4=Service, 5=Filesystem, 6=Lock, 7=Safety, 8=Partial

## Testing

Run: `sh tests/run_tests.sh`
Single test: `sh tests/test_common.sh`
Test helper provides: `assert_equals`, `assert_true`, `assert_contains`, `assert_file_exists`

## Adding a New Tool

1. Create `products/<product>/<tool>.sh` with `# description:` comment
2. Source `lib/common.sh` and any needed libraries
3. Call `parse_common_flags "$@"` for --dry-run, --verbose, --quiet
4. The dispatcher discovers it automatically

## Key Design Decisions

- Destructive ops (backup/purge/archive) use lock files; monitoring does not
- Purge/archive require a recent backup (safety gate)
- All destructive ops support --dry-run
- Scripts continue on partial failure and report all errors at the end
- Alert cooldown prevents repeated notifications for sustained outages
```

**Step 2: Commit**

```sh
git add CLAUDE.md
git commit -m "feat: add CLAUDE.md project documentation"
```

---

## Task 18: Clean Up .gitkeep Files

**Files:**
- Remove: `lib/.gitkeep`, `cron/.gitkeep`, remaining `.gitkeep` files

**Step 1: Remove .gitkeep files that are no longer needed**

```sh
rm -f lib/.gitkeep cron/.gitkeep bin/.gitkeep products/glpi/.gitkeep
git add -u
git commit -m "chore: remove .gitkeep files now that directories have content"
```

---

## Task 19: Final Integration Test

**Step 1: Run the full test suite**

```sh
sh tests/run_tests.sh
```

Expected: All test suites pass.

**Step 2: Verify dispatcher works**

```sh
bin/it help
bin/it list
bin/it glpi list
```

Expected: Help text, product list showing glpi, tool list showing monitor/backup/purge/archive.

**Step 3: Verify all scripts are POSIX compliant (if shellcheck is available)**

```sh
shellcheck -s sh lib/*.sh bin/it products/glpi/*.sh 2>/dev/null || echo "shellcheck not installed — manual review needed"
```

**Step 4: Commit any fixes**

If shellcheck or tests reveal issues, fix and commit.
