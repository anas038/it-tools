#!/bin/sh
# description: Restore GLPI from a backup image
# usage: it glpi restore [--backup <path>] [--db] [--files] [--webroot] [--dry-run] [--verbose] [--quiet]
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
GLPI_INSTALL_PATH="${GLPI_INSTALL_PATH:-/var/www/html/glpi}"
RUN_USER="${RUN_USER:-}"

# ---- Parse flags ----
# Handle custom flags before common flags (same pattern as archive.sh)
_RST_BACKUP_DIR=""
_RST_DO_DB=false
_RST_DO_FILES=false
_RST_DO_WEBROOT=false
_RST_SELECTIVE=false
_ARGS=""
while [ $# -gt 0 ]; do
    case "$1" in
        --backup)
            shift
            _RST_BACKUP_DIR="$1"
            ;;
        --db)
            _RST_DO_DB=true
            _RST_SELECTIVE=true
            ;;
        --files)
            _RST_DO_FILES=true
            _RST_SELECTIVE=true
            ;;
        --webroot)
            _RST_DO_WEBROOT=true
            _RST_SELECTIVE=true
            ;;
        *)
            _ARGS="$_ARGS $1"
            ;;
    esac
    shift
done

# If no selective flag, restore all components
if [ "$_RST_SELECTIVE" = "false" ]; then
    _RST_DO_DB=true
    _RST_DO_FILES=true
    _RST_DO_WEBROOT=true
fi

# shellcheck disable=SC2086
parse_common_flags $_ARGS || {
    cat >&2 << EOF
Usage: it glpi restore [--backup <path>] [--db] [--files] [--webroot] [--dry-run] [--verbose] [--quiet]

Restores GLPI from a backup image.

Components (default: all):
  --db          Restore database from SQL dump
  --files       Restore files/ directory
  --webroot     Restore webroot (excluding files/)

Options:
  --backup P    Path to backup directory (interactive selection if omitted)
  --dry-run     Preview without restoring
  --verbose     Enable debug logging
  --quiet       Suppress non-error output
  --help        Show this help
EOF
    exit 0
}

# ============================================================
# Interactive backup selection
# ============================================================

_rst_select_backup() {
    require_arg "BACKUP_DEST" "$BACKUP_DEST"
    if [ ! -d "$BACKUP_DEST" ]; then
        log_error "Backup directory does not exist: $BACKUP_DEST"
        exit "$EXIT_FILESYSTEM"
    fi

    # List backup directories sorted newest first
    _rsb_list=""
    _rsb_count=0
    for _rsb_dir in $(ls -dt "$BACKUP_DEST"/glpi-backup-* 2>/dev/null); do
        [ -d "$_rsb_dir" ] || continue
        _rsb_count=$(( _rsb_count + 1 ))
        _rsb_name=$(basename "$_rsb_dir")
        _rsb_ts=$(echo "$_rsb_name" | sed 's/glpi-backup-//')

        # Check for partial
        _rsb_partial=""
        if [ -f "$_rsb_dir/.partial" ]; then
            _rsb_partial=" [PARTIAL]"
        fi

        # Get sizes of components
        _rsb_sizes=""
        for _rsb_f in "$_rsb_dir"/glpi-db-*.sql.gz; do
            [ -f "$_rsb_f" ] && _rsb_sizes="DB: $(du -h "$_rsb_f" | cut -f1)"
        done
        for _rsb_f in "$_rsb_dir"/glpi-files-*.tar.gz; do
            if [ -f "$_rsb_f" ]; then
                if [ -n "$_rsb_sizes" ]; then
                    _rsb_sizes="$_rsb_sizes, Files: $(du -h "$_rsb_f" | cut -f1)"
                else
                    _rsb_sizes="Files: $(du -h "$_rsb_f" | cut -f1)"
                fi
            fi
        done
        for _rsb_f in "$_rsb_dir"/glpi-webroot-*.tar.gz; do
            if [ -f "$_rsb_f" ]; then
                if [ -n "$_rsb_sizes" ]; then
                    _rsb_sizes="$_rsb_sizes, Webroot: $(du -h "$_rsb_f" | cut -f1)"
                else
                    _rsb_sizes="Webroot: $(du -h "$_rsb_f" | cut -f1)"
                fi
            fi
        done

        _rsb_list="$_rsb_list
$_rsb_count) $_rsb_ts  ($_rsb_sizes)$_rsb_partial"
    done

    if [ "$_rsb_count" -eq 0 ]; then
        log_error "No backups found in $BACKUP_DEST"
        exit "$EXIT_FILESYSTEM"
    fi

    printf "\nAvailable backups in %s:\n%s\n\n" "$BACKUP_DEST" "$_rsb_list" >&2
    printf "Select backup [1]: " >&2
    read -r _rsb_choice
    _rsb_choice="${_rsb_choice:-1}"

    # Validate choice and resolve to path
    _rsb_idx=0
    for _rsb_dir in $(ls -dt "$BACKUP_DEST"/glpi-backup-* 2>/dev/null); do
        [ -d "$_rsb_dir" ] || continue
        _rsb_idx=$(( _rsb_idx + 1 ))
        if [ "$_rsb_idx" -eq "$_rsb_choice" ]; then
            echo "$_rsb_dir"
            return 0
        fi
    done

    log_error "Invalid selection: $_rsb_choice"
    return 1
}

# ============================================================
# Backup validation
# ============================================================

_rst_validate_backup() {
    _rvb_dir="$1"
    if [ ! -d "$_rvb_dir" ]; then
        log_error "Backup directory not found: $_rvb_dir"
        exit "$EXIT_FILESYSTEM"
    fi
    if [ -f "$_rvb_dir/.partial" ]; then
        log_error "Backup is marked as partial (incomplete): $_rvb_dir"
        log_error "Restoring from a partial backup is not supported"
        exit "$EXIT_SAFETY"
    fi
    # Check at least one archive exists
    _rvb_has_files=false
    for _rvb_f in "$_rvb_dir"/glpi-db-*.sql.gz "$_rvb_dir"/glpi-files-*.tar.gz "$_rvb_dir"/glpi-webroot-*.tar.gz; do
        if [ -f "$_rvb_f" ]; then
            _rvb_has_files=true
            break
        fi
    done
    if [ "$_rvb_has_files" = "false" ]; then
        log_error "No backup archives found in: $_rvb_dir"
        exit "$EXIT_FILESYSTEM"
    fi
}

# ============================================================
# Service management
# ============================================================

_RST_SERVICES_STOPPED=false
_RST_PHP_FPM_SERVICE=""

_rst_stop_services() {
    log_info "Stopping web services..."
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[dry-run] Would stop apache2 and PHP-FPM"
        return 0
    fi
    # Detect PHP-FPM service name
    _RST_PHP_FPM_SERVICE=$(systemctl list-units --type=service --state=active 2>/dev/null | \
        grep -o 'php[0-9.]*-fpm\.service' | head -1) || true

    systemctl stop apache2 2>/dev/null || log_warn "Could not stop apache2"
    if [ -n "$_RST_PHP_FPM_SERVICE" ]; then
        systemctl stop "$_RST_PHP_FPM_SERVICE" 2>/dev/null || log_warn "Could not stop $_RST_PHP_FPM_SERVICE"
    fi
    _RST_SERVICES_STOPPED=true
    log_info "Web services stopped"
}

_rst_start_services() {
    if [ "$_RST_SERVICES_STOPPED" != "true" ]; then return 0; fi
    log_info "Starting web services..."
    if [ -n "$_RST_PHP_FPM_SERVICE" ]; then
        systemctl start "$_RST_PHP_FPM_SERVICE" 2>/dev/null || log_warn "Could not start $_RST_PHP_FPM_SERVICE"
    fi
    systemctl start apache2 2>/dev/null || log_warn "Could not start apache2"
    _RST_SERVICES_STOPPED=false
    log_info "Web services started"
}

# ============================================================
# Maintenance mode
# ============================================================

_rst_enable_maintenance() {
    _rem_flag="$GLPI_INSTALL_PATH/files/_cache/maintenance_mode"
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[dry-run] Would enable maintenance mode"
        return 0
    fi
    mkdir -p "$(dirname "$_rem_flag")"
    touch "$_rem_flag"
    log_info "Maintenance mode enabled"
}

_rst_disable_maintenance() {
    _rdm_flag="$GLPI_INSTALL_PATH/files/_cache/maintenance_mode"
    if [ -f "$_rdm_flag" ]; then
        rm -f "$_rdm_flag"
        log_info "Maintenance mode disabled"
    fi
}

# ============================================================
# Restore components
# ============================================================

_rst_restore_db() {
    _rrd_dir="$1"
    _rrd_dump=""
    for _rrd_f in "$_rrd_dir"/glpi-db-*.sql.gz; do
        if [ -f "$_rrd_f" ]; then
            _rrd_dump="$_rrd_f"
            break
        fi
    done
    if [ -z "$_rrd_dump" ]; then
        collect_error "No database dump found in backup"
        return 1
    fi

    log_info "Restoring database from: $(basename "$_rrd_dump")"
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[dry-run] Would import $(basename "$_rrd_dump") into $_DB_NAME"
        return 0
    fi

    if gunzip -c "$_rrd_dump" | MYSQL_PWD="$_DB_PASS" mysql -h "$_DB_HOST" -u "$_DB_USER" "$_DB_NAME" 2>/dev/null; then
        log_info "Database restored successfully"
    else
        collect_error "Database restore failed"
        return 1
    fi
}

_rst_restore_files() {
    _rrf_dir="$1"
    _rrf_tar=""
    for _rrf_f in "$_rrf_dir"/glpi-files-*.tar.gz; do
        if [ -f "$_rrf_f" ]; then
            _rrf_tar="$_rrf_f"
            break
        fi
    done
    if [ -z "$_rrf_tar" ]; then
        collect_error "No files archive found in backup"
        return 1
    fi

    log_info "Restoring files from: $(basename "$_rrf_tar")"
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[dry-run] Would extract $(basename "$_rrf_tar") to $GLPI_INSTALL_PATH/"
        return 0
    fi

    if tar -xzf "$_rrf_tar" -C "$GLPI_INSTALL_PATH/" 2>/dev/null; then
        log_info "Files restored successfully"
    else
        collect_error "Files restore failed"
        return 1
    fi
}

_rst_restore_webroot() {
    _rrw_dir="$1"
    _rrw_tar=""
    for _rrw_f in "$_rrw_dir"/glpi-webroot-*.tar.gz; do
        if [ -f "$_rrw_f" ]; then
            _rrw_tar="$_rrw_f"
            break
        fi
    done
    if [ -z "$_rrw_tar" ]; then
        collect_error "No webroot archive found in backup"
        return 1
    fi

    log_info "Restoring webroot from: $(basename "$_rrw_tar")"
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[dry-run] Would extract $(basename "$_rrw_tar") to $(dirname "$GLPI_INSTALL_PATH")/"
        return 0
    fi

    if tar -xzf "$_rrw_tar" -C "$(dirname "$GLPI_INSTALL_PATH")" 2>/dev/null; then
        log_info "Webroot restored successfully"
    else
        collect_error "Webroot restore failed"
        return 1
    fi
}

# ============================================================
# Fix permissions
# ============================================================

_rst_fix_permissions() {
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[dry-run] Would fix permissions on $GLPI_INSTALL_PATH"
        return 0
    fi
    # Determine web user: use RUN_USER if set, otherwise try www-data
    _rfp_user="${RUN_USER:-www-data}"
    if id "$_rfp_user" >/dev/null 2>&1; then
        chown -R "$_rfp_user:$_rfp_user" "$GLPI_INSTALL_PATH" 2>/dev/null || \
            log_warn "Could not set ownership to $_rfp_user"
    else
        log_warn "User $_rfp_user does not exist — skipping permission fix"
    fi
}

# ============================================================
# Main
# ============================================================

# Lock
_RST_LOCK_FILE="$PROJECT_ROOT/logs/glpi-restore.lock"
acquire_lock "$_RST_LOCK_FILE" || exit "$EXIT_LOCK"
trap '_rst_start_services; _rst_disable_maintenance; release_lock "$_RST_LOCK_FILE"' EXIT INT TERM

# Select or validate backup directory
if [ -n "$_RST_BACKUP_DIR" ]; then
    log_debug "Using specified backup: $_RST_BACKUP_DIR"
else
    _RST_BACKUP_DIR=$(_rst_select_backup) || exit "$EXIT_CONFIG"
fi

_rst_validate_backup "$_RST_BACKUP_DIR"

# Summary
_rst_components=""
if [ "$_RST_DO_DB" = "true" ]; then _rst_components="database"; fi
if [ "$_RST_DO_FILES" = "true" ]; then
    if [ -n "$_rst_components" ]; then _rst_components="$_rst_components, files"; else _rst_components="files"; fi
fi
if [ "$_RST_DO_WEBROOT" = "true" ]; then
    if [ -n "$_rst_components" ]; then _rst_components="$_rst_components, webroot"; else _rst_components="webroot"; fi
fi

log_info "Restore plan:"
log_info "  Backup: $_RST_BACKUP_DIR"
log_info "  Components: $_rst_components"

confirm "Proceed with restore?" || { log_info "Restore cancelled"; exit "$EXIT_OK"; }

# Load DB credentials (if restoring DB)
if [ "$_RST_DO_DB" = "true" ]; then
    db_load_credentials || { log_error "Failed to load database credentials"; exit "$EXIT_CONFIG"; }
fi

# Maintenance mode
_rst_enable_maintenance

# Stop services (if restoring files or webroot)
if [ "$_RST_DO_FILES" = "true" ] || [ "$_RST_DO_WEBROOT" = "true" ]; then
    _rst_stop_services
fi

# Restore components
if [ "$_RST_DO_DB" = "true" ]; then
    _rst_restore_db "$_RST_BACKUP_DIR" || true
fi
if [ "$_RST_DO_FILES" = "true" ]; then
    _rst_restore_files "$_RST_BACKUP_DIR" || true
fi
if [ "$_RST_DO_WEBROOT" = "true" ]; then
    _rst_restore_webroot "$_RST_BACKUP_DIR" || true
fi

# Fix permissions (if files or webroot were restored)
if [ "$_RST_DO_FILES" = "true" ] || [ "$_RST_DO_WEBROOT" = "true" ]; then
    _rst_fix_permissions
fi

# Services restart + maintenance disable happen via trap

# Report
if has_errors; then
    _rst_summary="GLPI restore completed with errors"
    _rst_details=$(get_errors)
    log_error "$_rst_summary"
    send_alert "$_rst_summary" "$_rst_details" "restore"
    exit "$EXIT_PARTIAL"
else
    log_info "GLPI restore completed successfully from: $(basename "$_RST_BACKUP_DIR")"
    exit "$EXIT_OK"
fi
