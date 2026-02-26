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

# ============================================================
# Credential Loading
# ============================================================

_parse_glpi_config_db() {
    _pgc_config_file="$GLPI_INSTALL_PATH/config/config_db.php"
    if [ ! -f "$_pgc_config_file" ]; then
        log_error "GLPI config_db.php not found: $_pgc_config_file"
        return "$EXIT_CONFIG"
    fi

    _DB_HOST=$(grep "dbhost" "$_pgc_config_file" | sed "s/.*= *'//;s/'.*//" | head -1)
    _DB_USER=$(grep "dbuser" "$_pgc_config_file" | sed "s/.*= *'//;s/'.*//" | head -1)
    _DB_PASS=$(grep "dbpassword" "$_pgc_config_file" | sed "s/.*= *'//;s/'.*//" | head -1)
    _DB_NAME=$(grep "dbdefault" "$_pgc_config_file" | sed "s/.*= *'//;s/'.*//" | head -1)

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

# ============================================================
# Query Helpers
# ============================================================

db_build_dump_args() {
    printf '%s' "-h $_DB_HOST -u $_DB_USER $_DB_NAME"
}

db_query() {
    _dq_sql="$1"
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[dry-run] Would execute SQL: $_dq_sql"
        return 0
    fi
    MYSQL_PWD="$_DB_PASS" mysql -h "$_DB_HOST" -u "$_DB_USER" "$_DB_NAME" \
        -N -B -e "$_dq_sql" 2>/dev/null
}

db_dump() {
    _dd_output_file="$1"
    shift
    _dd_extra_args="$*"
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[dry-run] Would dump database $_DB_NAME to $_dd_output_file"
        return 0
    fi
    MYSQL_PWD="$_DB_PASS" mysqldump -h "$_DB_HOST" -u "$_DB_USER" \
        $_dd_extra_args "$_DB_NAME" > "$_dd_output_file" 2>/dev/null
}

db_dump_tables() {
    _ddt_output_file="$1"
    shift
    # Remaining args are table names
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[dry-run] Would dump tables ($*) to $_ddt_output_file"
        return 0
    fi
    MYSQL_PWD="$_DB_PASS" mysqldump -h "$_DB_HOST" -u "$_DB_USER" \
        "$_DB_NAME" "$@" > "$_ddt_output_file" 2>/dev/null
}

db_count() {
    _dc_table="$1"
    _dc_where="${2:-1=1}"
    db_query "SELECT COUNT(*) FROM $_dc_table WHERE $_dc_where"
}
