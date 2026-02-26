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

# ---- Archive: SQL Dump Mode ----

archive_sqldump() {
    _asd_table="$1"
    _asd_where="$2"
    _asd_label="$3"

    _asd_count=$(db_count "$_asd_table" "$_asd_where" 2>/dev/null || echo "0")
    log_info "$_asd_label: $_asd_count records to archive"

    if [ "$_asd_count" -eq 0 ]; then
        return 0
    fi

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[dry-run] Would export $_asd_count records from $_asd_table and delete"
        return 0
    fi

    # Export
    _asd_dump_file="$_ARCHIVE_DIR/${_asd_table}-$_TIMESTAMP.sql"
    db_query "SELECT * FROM $_asd_table WHERE $_asd_where" > "$_asd_dump_file" 2>/dev/null || {
        collect_error "Failed to export $_asd_table for archiving"
        return 1
    }

    # Verify export is non-empty
    if [ ! -s "$_asd_dump_file" ]; then
        collect_error "Archive export is empty: $_asd_dump_file"
        return 1
    fi

    # Delete from live DB
    db_query "DELETE FROM $_asd_table WHERE $_asd_where" || {
        collect_error "Failed to delete archived records from $_asd_table"
        return 1
    }

    gzip "$_asd_dump_file"
    log_info "Archived $_asd_count records from $_asd_table"
}

# ---- Archive: Archive DB Mode ----

archive_to_db() {
    _atd_table="$1"
    _atd_where="$2"
    _atd_label="$3"

    _atd_count=$(db_count "$_atd_table" "$_atd_where" 2>/dev/null || echo "0")
    log_info "$_atd_label: $_atd_count records to archive"

    if [ "$_atd_count" -eq 0 ]; then
        return 0
    fi

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[dry-run] Would move $_atd_count records from $_atd_table to $ARCHIVE_DB_NAME"
        return 0
    fi

    # Insert into archive DB
    db_query "INSERT INTO $ARCHIVE_DB_NAME.$_atd_table SELECT * FROM $_atd_table WHERE $_atd_where" || {
        collect_error "Failed to insert $_atd_table records into archive DB"
        return 1
    }

    # Verify count in archive DB
    _atd_archive_count=$(MYSQL_PWD="$_DB_PASS" mysql -h "$_DB_HOST" -u "$_DB_USER" \
        "$ARCHIVE_DB_NAME" -N -B -e "SELECT COUNT(*) FROM $_atd_table WHERE $_atd_where" \
        2>/dev/null || echo "0")

    if [ "$_atd_archive_count" -lt "$_atd_count" ]; then
        collect_error "Archive verification failed for $_atd_table (expected: $_atd_count, got: $_atd_archive_count)"
        return 1
    fi

    # Delete from live DB
    db_query "DELETE FROM $_atd_table WHERE $_atd_where" || {
        collect_error "Failed to delete archived records from $_atd_table"
        return 1
    }

    log_info "Moved $_atd_count records from $_atd_table to archive DB"
}

# ---- Main ----

enable_maintenance

if [ "$DRY_RUN" != "true" ] && [ "$ARCHIVE_MODE" = "sqldump" ]; then
    mkdir -p "$_ARCHIVE_DIR"
fi

# Select archive function
case "$ARCHIVE_MODE" in
    sqldump)   _archive_fn="archive_sqldump" ;;
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
    _arch_summary="GLPI archive completed with errors"
    _arch_details=$(get_errors)
    log_error "$_arch_summary"
    send_alert "$_arch_summary" "$_arch_details" "archive"
    exit "$EXIT_PARTIAL"
else
    log_info "GLPI archive completed successfully (cutoff: $_CUTOFF_DATE)"
    exit "$EXIT_OK"
fi
