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
    _bv_verify_ok=true
    for _bv_archive in "$_BACKUP_DIR"/*.tar.gz; do
        [ -f "$_bv_archive" ] || continue
        if ! tar -tzf "$_bv_archive" >/dev/null 2>&1; then
            collect_error "Archive verification failed: $_bv_archive"
            _bv_verify_ok=false
        fi
    done
    for _bv_sqldump in "$_BACKUP_DIR"/*.sql.gz; do
        [ -f "$_bv_sqldump" ] || continue
        if ! gzip -t "$_bv_sqldump" 2>/dev/null; then
            collect_error "SQL dump verification failed: $_bv_sqldump"
            _bv_verify_ok=false
        fi
    done
    if [ "$_bv_verify_ok" = "true" ]; then
        log_info "Backup integrity verified"
    fi
fi

# ---- Retention policy ----
if [ "$DRY_RUN" != "true" ]; then
    log_info "Applying retention policy: ${BACKUP_RETENTION_DAYS} days"
    find "$BACKUP_DEST" -maxdepth 1 -name "glpi-backup-*" -type d \
        -mtime +"$BACKUP_RETENTION_DAYS" | while read -r _ret_old_backup; do
        log_info "Removing old backup: $_ret_old_backup"
        rm -rf "$_ret_old_backup"
    done
else
    log_info "[dry-run] Would remove backups older than $BACKUP_RETENTION_DAYS days"
fi

# ---- Report ----
if has_errors; then
    _bak_summary="GLPI backup completed with errors"
    _bak_details=$(get_errors)
    log_error "$_bak_summary"
    send_alert "$_bak_summary" "$_bak_details" "backup"
    exit "$EXIT_PARTIAL"
else
    log_info "GLPI backup completed successfully: $_BACKUP_DIR"
    exit "$EXIT_OK"
fi
