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

    # Find the most recent backup file by checking all candidates
    _crb_newest=""
    _crb_newest_age=999999999
    _crb_now=$(date +%s)

    for _crb_f in "$BACKUP_DEST"/*.tar.gz "$BACKUP_DEST"/*.sql.gz; do
        [ -f "$_crb_f" ] || continue
        _crb_file_mod=$(stat -c %Y "$_crb_f" 2>/dev/null || echo "0")
        _crb_age=$(( _crb_now - _crb_file_mod ))
        if [ "$_crb_age" -lt "$_crb_newest_age" ]; then
            _crb_newest="$_crb_f"
            _crb_newest_age="$_crb_age"
        fi
    done

    if [ -z "$_crb_newest" ]; then
        log_error "No backup files found in $BACKUP_DEST"
        return "$EXIT_SAFETY"
    fi

    _crb_max_age_seconds=$(( BACKUP_MAX_AGE_HOURS * 3600 ))
    if [ "$_crb_newest_age" -gt "$_crb_max_age_seconds" ]; then
        _crb_hours=$(( _crb_newest_age / 3600 ))
        log_error "Most recent backup is ${_crb_hours}h old (max: ${BACKUP_MAX_AGE_HOURS}h): $_crb_newest"
        return "$EXIT_SAFETY"
    fi

    log_info "Recent backup verified: $_crb_newest (age: $(( _crb_newest_age / 60 ))m)"
    return 0
}
