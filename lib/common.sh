#!/bin/sh
# common.sh — Shared library for it-tools
# POSIX sh compliant — no bash-isms
set -eu

# ============================================================
# Exit codes
# ============================================================
EXIT_OK=0
EXIT_CONFIG=1
EXIT_DEPENDENCY=2
EXIT_DATABASE=3
EXIT_SERVICE=4
EXIT_FILESYSTEM=5
EXIT_LOCK=6
EXIT_SAFETY=7
EXIT_PARTIAL=8

# ============================================================
# Global defaults
# ============================================================
LOG_LEVEL="${LOG_LEVEL:-info}"
LOG_DIR="${LOG_DIR:-}"
DRY_RUN="${DRY_RUN:-false}"
VERBOSE="${VERBOSE:-false}"
QUIET="${QUIET:-false}"
_ERRORS=""

LOCK_TIMEOUT_MINUTES="${LOCK_TIMEOUT_MINUTES:-120}"

RETRY_COUNT="${RETRY_COUNT:-3}"
RETRY_DELAY_SECONDS="${RETRY_DELAY_SECONDS:-10}"

# ============================================================
# Log level ordering
# ============================================================
_log_level_num() {
    _lln_level="$1"
    case "$_lln_level" in
        debug) echo 0 ;;
        info)  echo 1 ;;
        warn)  echo 2 ;;
        error) echo 3 ;;
        *)     echo 1 ;;
    esac
}

# ============================================================
# Logging
# ============================================================
_log() {
    _log_level="$1"
    shift
    _log_msg="$*"

    _log_current=$(_log_level_num "$LOG_LEVEL")
    _log_this=$(_log_level_num "$_log_level")

    # Suppress messages below configured level
    if [ "$_log_this" -lt "$_log_current" ]; then
        return 0
    fi

    _log_upper=$(echo "$_log_level" | tr '[:lower:]' '[:upper:]')
    _log_timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    _log_line="[${_log_timestamp}] ${_log_upper}: ${_log_msg}"

    echo "$_log_line" >&2

    # Write to log file if LOG_DIR is set and directory exists
    if [ -n "$LOG_DIR" ] && [ -d "$LOG_DIR" ]; then
        echo "$_log_line" >> "${LOG_DIR}/it-tools.log"
    fi
}

log_debug() {
    _log debug "$@"
}

log_info() {
    _log info "$@"
}

log_warn() {
    _log warn "$@"
}

log_error() {
    _log error "$@"
}

# ============================================================
# Error collection
# ============================================================
collect_error() {
    _ce_msg="$1"
    if [ -z "$_ERRORS" ]; then
        _ERRORS="$_ce_msg"
    else
        _ERRORS="${_ERRORS}
${_ce_msg}"
    fi
}

has_errors() {
    if [ -n "$_ERRORS" ]; then
        return 0
    else
        return 1
    fi
}

get_errors() {
    echo "$_ERRORS"
}

clear_errors() {
    _ERRORS=""
}

# ============================================================
# Arg helpers
# ============================================================
require_arg() {
    _ra_name="$1"
    _ra_value="$2"
    if [ -z "$_ra_value" ]; then
        log_error "Required argument missing: ${_ra_name}"
        exit "$EXIT_CONFIG"
    fi
}

confirm() {
    _cf_prompt="$1"
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would prompt: ${_cf_prompt} — auto-declining"
        return 1
    fi
    printf "%s [y/N] " "$_cf_prompt" >&2
    read _cf_answer
    case "$_cf_answer" in
        y|Y|yes|YES|Yes) return 0 ;;
        *) return 1 ;;
    esac
}

# ============================================================
# Common flag parsing
# ============================================================
parse_common_flags() {
    for _pcf_arg in "$@"; do
        case "$_pcf_arg" in
            --dry-run)
                DRY_RUN="true"
                ;;
            --verbose)
                VERBOSE="true"
                LOG_LEVEL="debug"
                ;;
            --quiet)
                QUIET="true"
                LOG_LEVEL="error"
                ;;
            --help)
                return 2
                ;;
        esac
    done
    return 0
}

# ============================================================
# Config loading
# ============================================================
load_config() {
    _lc_file="$1"
    if [ ! -f "$_lc_file" ]; then
        log_error "Config file not found: ${_lc_file}"
        exit "$EXIT_CONFIG"
    fi
    . "$_lc_file"
}

# ============================================================
# Project root resolver
# ============================================================
resolve_project_root() {
    _rpr_script_path="$1"
    _rpr_dir="$(cd "$(dirname "$_rpr_script_path")" && pwd)"
    while [ "$_rpr_dir" != "/" ]; do
        if [ -f "${_rpr_dir}/lib/common.sh" ]; then
            echo "$_rpr_dir"
            return 0
        fi
        _rpr_dir="$(dirname "$_rpr_dir")"
    done
    log_error "Could not resolve project root from: ${_rpr_script_path}"
    return 1
}

# ============================================================
# Lock file management
# ============================================================
acquire_lock() {
    _al_lock_file="$1"
    if [ -f "$_al_lock_file" ]; then
        # Check if stale
        _al_now=$(date +%s)
        _al_file_mod=$(stat -c %Y "$_al_lock_file" 2>/dev/null || echo "0")
        _al_age_seconds=$(( _al_now - _al_file_mod ))
        _al_timeout_seconds=$(( LOCK_TIMEOUT_MINUTES * 60 ))

        if [ "$_al_age_seconds" -ge "$_al_timeout_seconds" ]; then
            log_warn "Stale lock detected (age: ${_al_age_seconds}s), removing: ${_al_lock_file}"
            rm -f "$_al_lock_file"
        else
            log_error "Lock file exists and is not stale: ${_al_lock_file}"
            return "$EXIT_LOCK"
        fi
    fi
    echo "$$" > "$_al_lock_file"
    return 0
}

release_lock() {
    _rl_lock_file="$1"
    if [ -f "$_rl_lock_file" ]; then
        rm -f "$_rl_lock_file"
    fi
}

# ============================================================
# Retry logic
# ============================================================
retry_cmd() {
    _rc_attempt=1
    while [ "$_rc_attempt" -le "$RETRY_COUNT" ]; do
        if "$@"; then
            return 0
        fi
        log_warn "Attempt ${_rc_attempt}/${RETRY_COUNT} failed: $*"
        if [ "$_rc_attempt" -lt "$RETRY_COUNT" ]; then
            sleep "$RETRY_DELAY_SECONDS"
        fi
        _rc_attempt=$(( _rc_attempt + 1 ))
    done
    log_error "All ${RETRY_COUNT} attempts exhausted: $*"
    return 1
}
