#!/bin/sh
# description: Show GLPI instance status overview
# usage: it glpi status [--verbose] [--quiet]
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

. "$PROJECT_ROOT/lib/common.sh"
. "$PROJECT_ROOT/lib/db.sh"

# ---- Config ----
_CONFIG_FILE="$SCRIPT_DIR/glpi.conf"
if [ -f "$_CONFIG_FILE" ]; then
    load_config "$_CONFIG_FILE"
fi

GLPI_URL="${GLPI_URL:-}"
GLPI_INSTALL_PATH="${GLPI_INSTALL_PATH:-/var/www/html/glpi}"
BACKUP_DEST="${BACKUP_DEST:-}"

# ---- Parse flags ----
parse_common_flags "$@" || {
    cat >&2 << EOF
Usage: it glpi status [--verbose] [--quiet]

Shows GLPI instance status overview:
  - Instance: URL, install path, path check
  - System: PHP version, disk usage
  - Database: MariaDB version, DB size, ticket/asset counts
  - Backup: latest backup age, size, completeness
EOF
    exit 0
}

# ============================================================
# Section 1 — Instance
# ============================================================

log_info "=== Instance ==="

if [ -n "$GLPI_URL" ]; then
    log_info "  URL:          $GLPI_URL"
else
    log_info "  URL:          not configured"
fi

log_info "  Install path: $GLPI_INSTALL_PATH"
if [ -d "$GLPI_INSTALL_PATH" ]; then
    log_info "  Path exists:  yes"
else
    log_info "  Path exists:  no"
fi

# ============================================================
# Section 2 — System
# ============================================================

log_info "=== System ==="

if command -v php >/dev/null 2>&1; then
    _st_php_ver=$(php -r 'echo PHP_VERSION;' 2>/dev/null) || _st_php_ver="unavailable"
    log_info "  PHP version:  $_st_php_ver"
else
    log_info "  PHP version:  not installed"
fi

if [ -d "$GLPI_INSTALL_PATH" ]; then
    _st_disk=$(df -h "$GLPI_INSTALL_PATH" 2>/dev/null | tail -1 | awk '{printf "%s used of %s (%s)", $3, $2, $5}') || _st_disk="unavailable"
    log_info "  Disk usage:   $_st_disk"
else
    log_info "  Disk usage:   path not found"
fi

# ============================================================
# Section 3 — Database
# ============================================================

log_info "=== Database ==="

_st_db_ok=false
if db_load_credentials 2>/dev/null; then
    _st_db_ok=true
fi

if [ "$_st_db_ok" = "true" ]; then
    _st_db_ver=$(db_query "SELECT VERSION()" 2>/dev/null) || _st_db_ver="unavailable"
    log_info "  MariaDB:      $_st_db_ver"

    _st_db_size=$(db_query "SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 1) FROM information_schema.tables WHERE table_schema = '$_DB_NAME'" 2>/dev/null) || _st_db_size="unavailable"
    if [ -n "$_st_db_size" ] && [ "$_st_db_size" != "unavailable" ]; then
        log_info "  DB size:      ${_st_db_size} MB"
    else
        log_info "  DB size:      unavailable"
    fi

    _st_open_tickets=$(db_query "SELECT COUNT(*) FROM glpi_tickets WHERE status NOT IN (5, 6)" 2>/dev/null) || _st_open_tickets="unavailable"
    log_info "  Open tickets: $_st_open_tickets"

    _st_total_tickets=$(db_query "SELECT COUNT(*) FROM glpi_tickets" 2>/dev/null) || _st_total_tickets="unavailable"
    log_info "  Total tickets: $_st_total_tickets"

    _st_computers=$(db_query "SELECT COUNT(*) FROM glpi_computers" 2>/dev/null) || _st_computers="unavailable"
    log_info "  Computers:    $_st_computers"

    _st_users=$(db_query "SELECT COUNT(*) FROM glpi_users WHERE is_active = 1" 2>/dev/null) || _st_users="unavailable"
    log_info "  Active users: $_st_users"
else
    log_info "  (skipped — DB credentials not available)"
fi

# ============================================================
# Section 4 — Backup
# ============================================================

log_info "=== Backup ==="

if [ -z "$BACKUP_DEST" ]; then
    log_info "  (skipped — BACKUP_DEST not configured)"
elif [ ! -d "$BACKUP_DEST" ]; then
    log_info "  (skipped — BACKUP_DEST does not exist: $BACKUP_DEST)"
else
    # Find newest glpi-backup-* directory
    _st_latest=$(ls -dt "$BACKUP_DEST"/glpi-backup-* 2>/dev/null | head -1) || true
    if [ -z "$_st_latest" ]; then
        log_info "  No backups found in $BACKUP_DEST"
    else
        _st_bk_name=$(basename "$_st_latest")
        _st_bk_ts=$(echo "$_st_bk_name" | sed 's/glpi-backup-//')
        log_info "  Latest:       $_st_bk_ts"

        # Calculate age
        _st_bk_epoch=$(stat -c %Y "$_st_latest" 2>/dev/null) || _st_bk_epoch=""
        if [ -n "$_st_bk_epoch" ]; then
            _st_now=$(date +%s)
            _st_age_h=$(( (_st_now - _st_bk_epoch) / 3600 ))
            log_info "  Age:          ${_st_age_h}h"
        fi

        # Check partial flag
        if [ -f "$_st_latest/.partial" ]; then
            log_info "  Status:       PARTIAL (incomplete)"
        else
            log_info "  Status:       complete"
        fi

        # Total size
        _st_bk_size=$(du -sh "$_st_latest" 2>/dev/null | cut -f1) || _st_bk_size="unavailable"
        log_info "  Size:         $_st_bk_size"
    fi
fi

exit "$EXIT_OK"
