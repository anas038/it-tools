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
MONITOR_CERT_WARN_DAYS="${MONITOR_CERT_WARN_DAYS:-30}"
MONITOR_CERT_CRIT_DAYS="${MONITOR_CERT_CRIT_DAYS:-7}"

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
  - SSL certificate expiry
EOF
    exit 0
}

# ---- Checks ----

_failed_checks=""

_record_failure() {
    _rf_check="$1"
    _rf_detail="$2"
    collect_error "$_rf_check: $_rf_detail"
    if [ -z "$_failed_checks" ]; then
        _failed_checks="$_rf_check"
    else
        _failed_checks="$_failed_checks, $_rf_check"
    fi
}

check_dns() {
    if [ -z "$GLPI_URL" ]; then
        log_warn "GLPI_URL not configured, skipping DNS check"
        return 0
    fi
    _cd_hostname=$(echo "$GLPI_URL" | sed 's|https\?://||' | sed 's|/.*||' | sed 's|:.*||')
    log_debug "Checking DNS resolution: $_cd_hostname"
    if retry_cmd nslookup "$_cd_hostname" >/dev/null 2>&1; then
        log_info "DNS OK: $_cd_hostname"
    else
        _record_failure "DNS" "Cannot resolve $_cd_hostname"
    fi
}

check_http() {
    if [ -z "$GLPI_URL" ]; then
        log_warn "GLPI_URL not configured, skipping HTTP check"
        return 0
    fi
    log_debug "Checking HTTP response: $GLPI_URL"
    _ch_status=$(retry_cmd curl -s -o /dev/null -w '%{http_code}' \
        --max-time 10 "$GLPI_URL" 2>/dev/null) || _ch_status="000"
    if [ "$_ch_status" -ge 200 ] 2>/dev/null && [ "$_ch_status" -lt 400 ] 2>/dev/null; then
        log_info "HTTP OK: $GLPI_URL (status: $_ch_status)"
    else
        _record_failure "HTTP" "$GLPI_URL returned status $_ch_status"
    fi
}

check_service() {
    _cs_svc_name="$1"
    log_debug "Checking service: $_cs_svc_name"
    if systemctl is-active "$_cs_svc_name" >/dev/null 2>&1; then
        log_info "Service OK: $_cs_svc_name"
    else
        _record_failure "Service" "$_cs_svc_name is not running"
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
        _cp_php_version=$(php -v 2>/dev/null | head -1)
        log_info "PHP OK: $_cp_php_version"
    else
        _record_failure "PHP" "php command not found"
        return
    fi
    # Check if PHP-FPM is running (if applicable)
    if systemctl list-units --type=service 2>/dev/null | grep -q "php.*fpm"; then
        _cp_fpm_svc=$(systemctl list-units --type=service 2>/dev/null \
            | grep "php.*fpm" | awk '{print $1}' | head -1)
        if systemctl is-active "$_cp_fpm_svc" >/dev/null 2>&1; then
            log_info "PHP-FPM OK: $_cp_fpm_svc"
        else
            _record_failure "PHP-FPM" "$_cp_fpm_svc is not running"
        fi
    fi
}

check_disk() {
    log_debug "Checking disk space for: $GLPI_INSTALL_PATH"
    _ckd_usage=$(df "$GLPI_INSTALL_PATH" 2>/dev/null | tail -1 | awk '{print $5}' \
        | tr -d '%')
    if [ -z "$_ckd_usage" ]; then
        _record_failure "Disk" "Cannot determine disk usage for $GLPI_INSTALL_PATH"
        return
    fi
    if [ "$_ckd_usage" -ge "$MONITOR_DISK_CRIT_PCT" ]; then
        _record_failure "Disk" "CRITICAL: ${_ckd_usage}% used (threshold: ${MONITOR_DISK_CRIT_PCT}%)"
    elif [ "$_ckd_usage" -ge "$MONITOR_DISK_WARN_PCT" ]; then
        log_warn "Disk WARNING: ${_ckd_usage}% used (threshold: ${MONITOR_DISK_WARN_PCT}%)"
    else
        log_info "Disk OK: ${_ckd_usage}% used"
    fi
}

check_ssl_cert() {
    if [ -z "$GLPI_URL" ]; then
        log_warn "GLPI_URL not configured, skipping SSL check"
        return 0
    fi
    case "$GLPI_URL" in
        https://*) ;;
        *) log_debug "GLPI_URL is not HTTPS, skipping SSL check"; return 0 ;;
    esac

    _csc_host=$(echo "$GLPI_URL" | sed 's|https://||' | sed 's|/.*||' | sed 's|:.*||')
    _csc_port=$(echo "$GLPI_URL" | sed 's|https://||' | sed 's|/.*||' | grep ':' | sed 's|.*:||')
    _csc_port="${_csc_port:-443}"
    log_debug "Checking SSL certificate: $_csc_host:$_csc_port"

    if ! command -v openssl >/dev/null 2>&1; then
        log_warn "openssl not found, skipping SSL certificate check"
        return 0
    fi

    _csc_expiry=$(echo | openssl s_client -servername "$_csc_host" \
        -connect "$_csc_host:$_csc_port" 2>/dev/null \
        | openssl x509 -noout -enddate 2>/dev/null \
        | sed 's/notAfter=//') || true

    if [ -z "$_csc_expiry" ]; then
        _record_failure "SSL" "Cannot retrieve certificate from $_csc_host:$_csc_port"
        return 0
    fi

    _csc_expiry_epoch=$(date -d "$_csc_expiry" +%s 2>/dev/null) || {
        log_warn "Cannot parse certificate expiry date: $_csc_expiry"
        return 0
    }
    _csc_now=$(date +%s)
    _csc_days_left=$(( (_csc_expiry_epoch - _csc_now) / 86400 ))

    if [ "$_csc_days_left" -le 0 ]; then
        _record_failure "SSL" "Certificate EXPIRED ($_csc_days_left days ago): $_csc_host"
    elif [ "$_csc_days_left" -le "$MONITOR_CERT_CRIT_DAYS" ]; then
        _record_failure "SSL" "Certificate expires in $_csc_days_left days (critical threshold: ${MONITOR_CERT_CRIT_DAYS}d): $_csc_host"
    elif [ "$_csc_days_left" -le "$MONITOR_CERT_WARN_DAYS" ]; then
        log_warn "SSL WARNING: Certificate expires in $_csc_days_left days (threshold: ${MONITOR_CERT_WARN_DAYS}d): $_csc_host"
    else
        log_info "SSL OK: Certificate expires in $_csc_days_left days: $_csc_host"
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
check_ssl_cert

# Report results
if has_errors; then
    _mon_summary="GLPI health check FAILED: $_failed_checks"
    _mon_details=$(get_errors)
    log_error "$_mon_summary"
    send_alert "$_mon_summary" "$_mon_details" "monitor"
    exit "$EXIT_SERVICE"
else
    log_info "GLPI health check PASSED — all checks OK"
    exit "$EXIT_OK"
fi
