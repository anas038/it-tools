#!/bin/sh
# description: Validate configuration, dependencies, and connectivity
# usage: it glpi check [--verbose] [--quiet]
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

. "$PROJECT_ROOT/lib/common.sh"
. "$PROJECT_ROOT/lib/db.sh"

# ---- Config ----
_ck_conf="$SCRIPT_DIR/glpi.conf"
_ck_conf_loaded=false
if [ -f "$_ck_conf" ] && [ -r "$_ck_conf" ] && sh -n "$_ck_conf" 2>/dev/null; then
    load_config "$_ck_conf"
    _ck_conf_loaded=true
fi

# Defaults for all checked parameters
GLPI_INSTALL_PATH="${GLPI_INSTALL_PATH:-/var/www/html/glpi}"
GLPI_URL="${GLPI_URL:-}"
BACKUP_DEST="${BACKUP_DEST:-}"
BACKUP_VERIFY_MOUNT="${BACKUP_VERIFY_MOUNT:-false}"
REPORT_OUTPUT_DIR="${REPORT_OUTPUT_DIR:-/tmp}"
ARCHIVE_MODE="${ARCHIVE_MODE:-sqldump}"
ALERT_CHANNELS="${ALERT_CHANNELS:-log}"
ALERT_EMAIL_TO="${ALERT_EMAIL_TO:-}"
ALERT_TEAMS_WEBHOOK="${ALERT_TEAMS_WEBHOOK:-}"
ALERT_SLACK_WEBHOOK="${ALERT_SLACK_WEBHOOK:-}"
RUN_USER="${RUN_USER:-}"
MONITOR_DISK_WARN_PCT="${MONITOR_DISK_WARN_PCT:-80}"
MONITOR_DISK_CRIT_PCT="${MONITOR_DISK_CRIT_PCT:-90}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
BACKUP_MAX_AGE_HOURS="${BACKUP_MAX_AGE_HOURS:-26}"

# ---- Parse flags ----
parse_common_flags "$@" || {
    cat >&2 << EOF
Usage: it glpi check [--verbose] [--quiet]

Validates GLPI configuration and environment:
  1. Config File   — exists, readable, valid syntax
  2. Dependencies  — required and optional commands
  3. Paths         — install path, backup dest, report dir
  4. Database      — credentials and connectivity
  5. Config Values — valid parameter values
EOF
    exit 0
}

# ============================================================
# Result helpers
# ============================================================
_ck_pass=0
_ck_warn=0
_ck_fail=0
_ck_config_fail=0
_ck_dep_fail_count=0

_ck_ok() {
    _ck_pass=$(( _ck_pass + 1 ))
    log_info "  [OK]   $1"
}

_ck_warning() {
    _ck_warn=$(( _ck_warn + 1 ))
    log_warn "  [WARN] $1"
}

_ck_failure() {
    _ck_fail=$(( _ck_fail + 1 ))
    log_error "  [FAIL] $1"
}

_ck_config_failure() {
    _ck_config_fail=$(( _ck_config_fail + 1 ))
    _ck_failure "$1"
}

_ck_dep_failure() {
    _ck_dep_fail_count=$(( _ck_dep_fail_count + 1 ))
    _ck_failure "$1"
}

# ============================================================
# Category 1 — Config File
# ============================================================
_ck_check_config() {
    log_info "=== Config File ==="
    if [ ! -f "$_ck_conf" ]; then
        _ck_config_failure "Config file not found: $_ck_conf"
        return 0
    fi
    _ck_ok "Config file exists: $_ck_conf"

    if [ ! -r "$_ck_conf" ]; then
        _ck_config_failure "Config file not readable: $_ck_conf"
        return 0
    fi
    _ck_ok "Config file is readable"

    if sh -n "$_ck_conf" 2>/dev/null; then
        _ck_ok "Config file has valid syntax"
    else
        _ck_config_failure "Config file has syntax errors: $_ck_conf"
    fi
}

# ============================================================
# Category 2 — Dependencies
# ============================================================
_ck_check_dependencies() {
    log_info "=== Dependencies ==="

    for _ck_cmd in curl tar gzip mysql mysqldump systemctl mountpoint pdfinfo; do
        if command -v "$_ck_cmd" >/dev/null 2>&1; then
            _ck_ok "Found: $_ck_cmd"
        else
            _ck_dep_failure "Missing required command: $_ck_cmd"
        fi
    done

    # Optional: mail command
    _ck_has_mail=false
    for _ck_mail_cmd in mail msmtp sendmail; do
        if command -v "$_ck_mail_cmd" >/dev/null 2>&1; then
            _ck_ok "Found mail command: $_ck_mail_cmd"
            _ck_has_mail=true
            break
        fi
    done
    if [ "$_ck_has_mail" = "false" ]; then
        _ck_warning "No mail command found (mail, msmtp, sendmail)"
    fi

    # Optional: PHP
    if command -v php >/dev/null 2>&1; then
        _ck_ok "Found: php"
    else
        _ck_warning "PHP not found (needed for GLPI)"
    fi
}

# ============================================================
# Category 3 — Paths
# ============================================================
_ck_check_paths() {
    log_info "=== Paths ==="

    # GLPI install path
    if [ -d "$GLPI_INSTALL_PATH" ]; then
        _ck_ok "GLPI_INSTALL_PATH exists: $GLPI_INSTALL_PATH"
    else
        _ck_config_failure "GLPI_INSTALL_PATH does not exist: $GLPI_INSTALL_PATH"
    fi

    # Backup destination
    if [ -z "$BACKUP_DEST" ]; then
        _ck_warning "BACKUP_DEST is not configured"
    elif [ ! -d "$BACKUP_DEST" ]; then
        _ck_config_failure "BACKUP_DEST is not a directory: $BACKUP_DEST"
    else
        _ck_ok "BACKUP_DEST exists: $BACKUP_DEST"
        if [ "$BACKUP_VERIFY_MOUNT" = "true" ]; then
            if command -v mountpoint >/dev/null 2>&1; then
                if mountpoint -q "$BACKUP_DEST" 2>/dev/null; then
                    _ck_ok "BACKUP_DEST is a mountpoint"
                else
                    _ck_warning "BACKUP_DEST is not a mountpoint (BACKUP_VERIFY_MOUNT=true)"
                fi
            fi
        fi
    fi

    # Report output dir
    if [ ! -d "$REPORT_OUTPUT_DIR" ]; then
        _ck_config_failure "REPORT_OUTPUT_DIR does not exist: $REPORT_OUTPUT_DIR"
    elif [ ! -w "$REPORT_OUTPUT_DIR" ]; then
        _ck_config_failure "REPORT_OUTPUT_DIR is not writable: $REPORT_OUTPUT_DIR"
    else
        _ck_ok "REPORT_OUTPUT_DIR exists and is writable: $REPORT_OUTPUT_DIR"
    fi
}

# ============================================================
# Category 4 — Database
# ============================================================
_ck_check_database() {
    log_info "=== Database ==="

    if [ "$DB_AUTO_DETECT" = "true" ]; then
        _ck_db_conf="$GLPI_INSTALL_PATH/config/config_db.php"
        if [ -f "$_ck_db_conf" ]; then
            _ck_ok "config_db.php found: $_ck_db_conf"
        else
            _ck_config_failure "config_db.php not found: $_ck_db_conf (DB_AUTO_DETECT=true)"
        fi
    else
        if [ -n "$DB_NAME" ]; then
            _ck_ok "DB_NAME is configured: $DB_NAME"
        else
            _ck_config_failure "DB_NAME is empty (required when DB_AUTO_DETECT=false)"
        fi
    fi

    # Try loading credentials
    if db_load_credentials 2>/dev/null; then
        _ck_ok "Database credentials loaded successfully"

        # Try pinging database
        if command -v mysqladmin >/dev/null 2>&1; then
            if MYSQL_PWD="$_DB_PASS" mysqladmin -h "$_DB_HOST" -u "$_DB_USER" ping >/dev/null 2>&1; then
                _ck_ok "Database connection successful"
            else
                _ck_config_failure "Database connection failed (mysqladmin ping)"
            fi
        else
            _ck_warning "mysqladmin not found, skipping connection test"
        fi
    else
        _ck_config_failure "Failed to load database credentials"
    fi
}

# ============================================================
# Category 5 — Config Values
# ============================================================
_ck_check_values() {
    log_info "=== Config Values ==="

    # ARCHIVE_MODE
    case "$ARCHIVE_MODE" in
        sqldump|archivedb)
            _ck_ok "ARCHIVE_MODE is valid: $ARCHIVE_MODE"
            ;;
        *)
            _ck_config_failure "ARCHIVE_MODE is invalid: '$ARCHIVE_MODE' (expected: sqldump, archivedb)"
            ;;
    esac

    # LOG_LEVEL
    case "$LOG_LEVEL" in
        debug|info|warn|error)
            _ck_ok "LOG_LEVEL is valid: $LOG_LEVEL"
            ;;
        *)
            _ck_config_failure "LOG_LEVEL is invalid: '$LOG_LEVEL' (expected: debug, info, warn, error)"
            ;;
    esac

    # ALERT_CHANNELS
    _ck_saved_ifs="$IFS"
    IFS=','
    for _ck_channel in $ALERT_CHANNELS; do
        case "$_ck_channel" in
            email|teams|slack|log)
                _ck_ok "ALERT_CHANNELS entry valid: $_ck_channel"
                ;;
            *)
                _ck_config_failure "ALERT_CHANNELS entry invalid: '$_ck_channel' (expected: email, teams, slack, log)"
                ;;
        esac
    done
    IFS="$_ck_saved_ifs"

    # Check channel-specific config
    case "$ALERT_CHANNELS" in
        *email*)
            if [ -z "$ALERT_EMAIL_TO" ]; then
                _ck_warning "ALERT_CHANNELS includes 'email' but ALERT_EMAIL_TO is empty"
            fi
            ;;
    esac
    case "$ALERT_CHANNELS" in
        *teams*)
            if [ -z "$ALERT_TEAMS_WEBHOOK" ]; then
                _ck_warning "ALERT_CHANNELS includes 'teams' but ALERT_TEAMS_WEBHOOK is empty"
            fi
            ;;
    esac
    case "$ALERT_CHANNELS" in
        *slack*)
            if [ -z "$ALERT_SLACK_WEBHOOK" ]; then
                _ck_warning "ALERT_CHANNELS includes 'slack' but ALERT_SLACK_WEBHOOK is empty"
            fi
            ;;
    esac

    # Integer validation
    for _ck_int_pair in \
        "LOCK_TIMEOUT_MINUTES:$LOCK_TIMEOUT_MINUTES" \
        "RETRY_COUNT:$RETRY_COUNT" \
        "RETRY_DELAY_SECONDS:$RETRY_DELAY_SECONDS" \
        "MONITOR_DISK_WARN_PCT:$MONITOR_DISK_WARN_PCT" \
        "MONITOR_DISK_CRIT_PCT:$MONITOR_DISK_CRIT_PCT" \
        "BACKUP_RETENTION_DAYS:$BACKUP_RETENTION_DAYS" \
        "BACKUP_MAX_AGE_HOURS:$BACKUP_MAX_AGE_HOURS"; do
        _ck_int_name="${_ck_int_pair%%:*}"
        _ck_int_val="${_ck_int_pair#*:}"
        case "$_ck_int_val" in
            *[!0-9]*)
                _ck_config_failure "$_ck_int_name is not a valid integer: '$_ck_int_val'"
                ;;
            *)
                _ck_ok "$_ck_int_name is a valid integer: $_ck_int_val"
                ;;
        esac
    done

    # RUN_USER
    if [ -n "$RUN_USER" ]; then
        if id "$RUN_USER" >/dev/null 2>&1; then
            _ck_ok "RUN_USER exists: $RUN_USER"
        else
            _ck_warning "RUN_USER does not exist: $RUN_USER"
        fi
    fi

    # GLPI_URL
    if [ -n "$GLPI_URL" ]; then
        if command -v curl >/dev/null 2>&1; then
            _ck_http_code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$GLPI_URL" 2>/dev/null) || _ck_http_code="000"
            if [ "$_ck_http_code" -ge 200 ] 2>/dev/null && [ "$_ck_http_code" -lt 400 ] 2>/dev/null; then
                _ck_ok "GLPI_URL is reachable: $GLPI_URL (HTTP $_ck_http_code)"
            else
                _ck_warning "GLPI_URL returned HTTP $_ck_http_code: $GLPI_URL"
            fi
        fi
    fi
}

# ============================================================
# Run all checks
# ============================================================
_ck_check_config
_ck_check_dependencies
_ck_check_paths
_ck_check_database
_ck_check_values

# ============================================================
# Summary and exit
# ============================================================
log_info ""
log_info "Summary: $_ck_pass passed, $_ck_warn warnings, $_ck_fail failed"

if [ "$_ck_config_fail" -gt 0 ]; then
    exit "$EXIT_CONFIG"
elif [ "$_ck_dep_fail_count" -gt 0 ]; then
    exit "$EXIT_DEPENDENCY"
fi
exit "$EXIT_OK"
