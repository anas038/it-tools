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
        _em_maint_file="$GLPI_INSTALL_PATH/files/_cache/maintenance_mode"
        if [ -d "$(dirname "$_em_maint_file")" ]; then
            touch "$_em_maint_file"
            _maintenance_enabled=true
            log_info "GLPI maintenance mode enabled"
        fi
    fi
}

disable_maintenance() {
    if [ "$_maintenance_enabled" = "true" ]; then
        _dm_maint_file="$GLPI_INSTALL_PATH/files/_cache/maintenance_mode"
        rm -f "$_dm_maint_file"
        log_info "GLPI maintenance mode disabled"
    fi
}

# ---- Purge Functions ----

_total_purged=0

purge_closed_tickets() {
    _pct_months="$PURGE_CLOSED_TICKETS_MONTHS"
    if [ "$_pct_months" -eq 0 ]; then
        log_debug "Closed ticket purge disabled"
        return 0
    fi
    _pct_cutoff=$(date -d "$_pct_months months ago" '+%Y-%m-%d' 2>/dev/null || \
                  date -v-"${_pct_months}m" '+%Y-%m-%d' 2>/dev/null)
    _pct_where="status = 6 AND date_mod < '$_pct_cutoff'"

    _pct_count=$(db_count "glpi_tickets" "$_pct_where" 2>/dev/null || echo "0")
    log_info "Closed tickets to purge: $_pct_count (older than $_pct_cutoff)"

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[dry-run] Would delete $_pct_count closed tickets"
        return 0
    fi

    if [ "$_pct_count" -gt 0 ]; then
        db_query "DELETE FROM glpi_tickets WHERE $_pct_where" || {
            collect_error "Failed to purge closed tickets"
            return 1
        }
        _total_purged=$(( _total_purged + _pct_count ))
        log_info "Purged $_pct_count closed tickets"
    fi
}

purge_logs() {
    _pl_months="$PURGE_LOGS_MONTHS"
    if [ "$_pl_months" -eq 0 ]; then
        log_debug "Log purge disabled"
        return 0
    fi
    _pl_cutoff=$(date -d "$_pl_months months ago" '+%Y-%m-%d' 2>/dev/null || \
                 date -v-"${_pl_months}m" '+%Y-%m-%d' 2>/dev/null)
    _pl_where="date_mod < '$_pl_cutoff'"

    _pl_count=$(db_count "glpi_logs" "$_pl_where" 2>/dev/null || echo "0")
    log_info "Event logs to purge: $_pl_count (older than $_pl_cutoff)"

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[dry-run] Would delete $_pl_count event logs"
        return 0
    fi

    if [ "$_pl_count" -gt 0 ]; then
        db_query "DELETE FROM glpi_logs WHERE $_pl_where" || {
            collect_error "Failed to purge event logs"
            return 1
        }
        _total_purged=$(( _total_purged + _pl_count ))
        log_info "Purged $_pl_count event logs"
    fi
}

purge_notifications() {
    _pn_months="$PURGE_NOTIFICATIONS_MONTHS"
    if [ "$_pn_months" -eq 0 ]; then
        log_debug "Notification purge disabled"
        return 0
    fi
    _pn_cutoff=$(date -d "$_pn_months months ago" '+%Y-%m-%d' 2>/dev/null || \
                 date -v-"${_pn_months}m" '+%Y-%m-%d' 2>/dev/null)
    _pn_where="create_time < '$_pn_cutoff'"

    _pn_count=$(db_count "glpi_queuednotifications" "$_pn_where" 2>/dev/null || echo "0")
    log_info "Notifications to purge: $_pn_count (older than $_pn_cutoff)"

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[dry-run] Would delete $_pn_count notifications"
        return 0
    fi

    if [ "$_pn_count" -gt 0 ]; then
        db_query "DELETE FROM glpi_queuednotifications WHERE $_pn_where" || {
            collect_error "Failed to purge notifications"
            return 1
        }
        _total_purged=$(( _total_purged + _pn_count ))
        log_info "Purged $_pn_count notifications"
    fi
}

purge_trash() {
    _pt_months="$PURGE_TRASH_MONTHS"
    if [ "$_pt_months" -eq 0 ]; then
        log_debug "Trash purge disabled"
        return 0
    fi
    _pt_cutoff=$(date -d "$_pt_months months ago" '+%Y-%m-%d' 2>/dev/null || \
                 date -v-"${_pt_months}m" '+%Y-%m-%d' 2>/dev/null)
    _pt_where="is_deleted = 1 AND date_mod < '$_pt_cutoff'"

    # Purge from main tables that support is_deleted
    for _pt_table in glpi_tickets glpi_computers glpi_monitors glpi_printers \
                     glpi_phones glpi_peripherals glpi_networkequipments \
                     glpi_softwarelicenses; do
        _pt_count=$(db_count "$_pt_table" "$_pt_where" 2>/dev/null || echo "0")
        if [ "$_pt_count" -gt 0 ]; then
            log_info "Trash in $_pt_table: $_pt_count items"
            if [ "$DRY_RUN" = "true" ]; then
                log_info "[dry-run] Would delete $_pt_count trashed items from $_pt_table"
            else
                db_query "DELETE FROM $_pt_table WHERE $_pt_where" || {
                    collect_error "Failed to purge trash from $_pt_table"
                    continue
                }
                _total_purged=$(( _total_purged + _pt_count ))
                log_info "Purged $_pt_count trashed items from $_pt_table"
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
    _purge_summary="GLPI purge completed with errors (purged: $_total_purged records)"
    _purge_details=$(get_errors)
    log_error "$_purge_summary"
    send_alert "$_purge_summary" "$_purge_details" "purge"
    exit "$EXIT_PARTIAL"
else
    log_info "GLPI purge completed successfully (purged: $_total_purged records)"
    exit "$EXIT_OK"
fi
