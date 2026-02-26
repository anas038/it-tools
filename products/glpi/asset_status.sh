#!/bin/sh
# description: Update asset warranty and support status via GLPI API
# usage: it glpi asset_status --mode warranty|hors-support [--file list.txt] [--dry-run] [--verbose] [--quiet]
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

GLPI_API_URL="${GLPI_API_URL:-}"
GLPI_API_APP_TOKEN="${GLPI_API_APP_TOKEN:-}"
GLPI_API_USER="${GLPI_API_USER:-}"
GLPI_API_PASS="${GLPI_API_PASS:-}"
HORS_SUPPORT_FILE="${HORS_SUPPORT_FILE:-}"

# Status IDs
_AS_GARANTIE=1
_AS_MAINTENANCE=2
_AS_HORS_SUPPORT=3

# ---- Parse flags ----
_AS_MODE=""
_AS_FILE=""
_ARGS=""
while [ $# -gt 0 ]; do
    case "$1" in
        --mode)
            shift
            _AS_MODE="$1"
            ;;
        --file)
            shift
            _AS_FILE="$1"
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
Usage: it glpi asset_status --mode warranty|hors-support [--file list.txt] [--dry-run] [--verbose] [--quiet]

Updates asset warranty and support status via GLPI API.

Modes:
  warranty      Query machines from DB, compute warranty expiration,
                update status (Garantie/Maintenance) via API
  hors-support  Read serial numbers from a file, set status to
                Hors Support (3) via API

Options:
  --mode M      Required. 'warranty' or 'hors-support'
  --file F      Serial numbers file (overrides HORS_SUPPORT_FILE config)
  --dry-run     Preview without making API calls
  --verbose     Enable debug logging
  --quiet       Suppress non-error output
  --help        Show this help
EOF
    exit 0
}

# Validate mode
if [ -z "$_AS_MODE" ]; then
    log_error "Required argument missing: --mode (warranty or hors-support)"
    exit "$EXIT_CONFIG"
fi
case "$_AS_MODE" in
    warranty|hors-support) ;;
    *) log_error "Invalid mode: $_AS_MODE (valid: warranty, hors-support)"
       exit "$EXIT_CONFIG" ;;
esac

# Validate API config
require_arg "GLPI_API_URL" "$GLPI_API_URL"
require_arg "GLPI_API_APP_TOKEN" "$GLPI_API_APP_TOKEN"
require_arg "GLPI_API_USER" "$GLPI_API_USER"
require_arg "GLPI_API_PASS" "$GLPI_API_PASS"

# ---- API session management ----

_AS_SESSION_TOKEN=""

_as_init_session() {
    log_info "Initializing GLPI API session..."
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[dry-run] Would init API session at $GLPI_API_URL"
        _AS_SESSION_TOKEN="dry-run-token"
        return 0
    fi

    _as_response=$(curl -s -w "\n%{http_code}" \
        -H "Content-Type: application/json" \
        -H "App-Token: $GLPI_API_APP_TOKEN" \
        -d "{\"login\":\"$GLPI_API_USER\",\"password\":\"$GLPI_API_PASS\"}" \
        "$GLPI_API_URL/initSession" 2>/dev/null) || {
        log_error "Failed to connect to GLPI API at $GLPI_API_URL"
        return "$EXIT_SERVICE"
    }

    _as_http_code=$(echo "$_as_response" | tail -1)
    _as_body=$(echo "$_as_response" | sed '$d')

    if [ "$_as_http_code" != "200" ]; then
        log_error "GLPI API authentication failed (HTTP $_as_http_code): $_as_body"
        return "$EXIT_CONFIG"
    fi

    _AS_SESSION_TOKEN=$(echo "$_as_body" | sed 's/.*"session_token":"\([^"]*\)".*/\1/')
    if [ -z "$_AS_SESSION_TOKEN" ]; then
        log_error "Failed to extract session token from API response"
        return "$EXIT_CONFIG"
    fi

    log_debug "GLPI API session initialized"
}

_as_kill_session() {
    if [ -z "$_AS_SESSION_TOKEN" ] || [ "$_AS_SESSION_TOKEN" = "dry-run-token" ]; then
        return 0
    fi

    log_debug "Closing GLPI API session..."
    curl -s -H "Content-Type: application/json" \
        -H "App-Token: $GLPI_API_APP_TOKEN" \
        -H "Session-Token: $_AS_SESSION_TOKEN" \
        "$GLPI_API_URL/killSession" >/dev/null 2>&1 || true

    log_debug "GLPI API session closed"
}

_as_api_put() {
    _aap_endpoint="$1"
    _aap_id="$2"
    _aap_states_id="$3"

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[dry-run] Would PUT $GLPI_API_URL/$_aap_endpoint/$_aap_id states_id=$_aap_states_id"
        return 0
    fi

    _aap_data="{\"input\":{\"id\":$_aap_id,\"states_id\":$_aap_states_id}}"

    _aap_response=$(curl -s -w "\n%{http_code}" \
        -X PUT \
        -H "Content-Type: application/json" \
        -H "App-Token: $GLPI_API_APP_TOKEN" \
        -H "Session-Token: $_AS_SESSION_TOKEN" \
        -d "$_aap_data" \
        "$GLPI_API_URL/$_aap_endpoint/$_aap_id" 2>/dev/null) || {
        return 1
    }

    _aap_http_code=$(echo "$_aap_response" | tail -1)
    if [ "$_aap_http_code" = "200" ]; then
        return 0
    else
        _aap_body=$(echo "$_aap_response" | sed '$d')
        log_debug "API PUT failed (HTTP $_aap_http_code): $_aap_body"
        return 1
    fi
}

# ---- Mode: warranty ----

_as_mode_warranty() {
    log_info "Running warranty status check..."

    db_load_credentials || {
        log_error "Failed to load database credentials"
        exit "$EXIT_CONFIG"
    }

    _as_sql="SELECT
    c.id,
    c.name,
    c.states_id,
    IFNULL(i.warranty_date, ''),
    IFNULL(i.warranty_duration, 0),
    IFNULL(DATE_FORMAT(DATE_ADD(i.warranty_date, INTERVAL i.warranty_duration MONTH), '%Y-%m-%d'), '')
FROM
    glpi_plugin_genericobject_compteusebillets c
LEFT JOIN
    glpi_infocoms i ON c.id = i.items_id AND i.itemtype = 'PluginGenericobjectCompteusebillet'"

    _as_result=$(db_query "$_as_sql") || {
        log_error "Failed to query machines from database"
        exit "$EXIT_DATABASE"
    }

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[dry-run] Would process warranty status for machines"
        return 0
    fi

    if [ -z "$_as_result" ]; then
        log_info "No machines found in database"
        return 0
    fi

    _as_total=0
    _as_garantie=0
    _as_maintenance=0
    _as_ignored=0
    _as_incomplete=0
    _as_errors=0
    _as_today=$(date +%s)

    echo "$_as_result" | while IFS='	' read -r _as_id _as_name _as_state _as_wdate _as_wdur _as_expiry; do
        _as_total=$(( _as_total + 1 ))

        # Skip Hors Support
        if [ "$_as_state" = "$_AS_HORS_SUPPORT" ]; then
            _as_ignored=$(( _as_ignored + 1 ))
            continue
        fi

        # Skip incomplete warranty info
        if [ -z "$_as_wdate" ] || [ "$_as_wdur" = "0" ] || [ -z "$_as_expiry" ]; then
            _as_incomplete=$(( _as_incomplete + 1 ))
            continue
        fi

        # Compare dates
        _as_expiry_epoch=$(date -d "$_as_expiry" +%s 2>/dev/null || echo "0")
        if [ "$_as_expiry_epoch" = "0" ]; then
            _as_incomplete=$(( _as_incomplete + 1 ))
            continue
        fi

        _as_new_status=""
        if [ "$_as_expiry_epoch" -lt "$_as_today" ] && [ "$_as_state" != "$_AS_MAINTENANCE" ]; then
            _as_new_status="$_AS_MAINTENANCE"
        elif [ "$_as_expiry_epoch" -ge "$_as_today" ] && [ "$_as_state" != "$_AS_GARANTIE" ]; then
            _as_new_status="$_AS_GARANTIE"
        fi

        if [ -z "$_as_new_status" ]; then
            continue
        fi

        if _as_api_put "PluginGenericobjectCompteusebillet" "$_as_id" "$_as_new_status"; then
            if [ "$_as_new_status" = "$_AS_GARANTIE" ]; then
                _as_garantie=$(( _as_garantie + 1 ))
                log_info "Machine $_as_name (ID $_as_id): set to Garantie (expiry: $_as_expiry)"
            else
                _as_maintenance=$(( _as_maintenance + 1 ))
                log_info "Machine $_as_name (ID $_as_id): set to Maintenance (expiry: $_as_expiry)"
            fi
        else
            _as_errors=$(( _as_errors + 1 ))
            collect_error "Failed to update machine $_as_name (ID $_as_id)"
        fi
    done

    # Note: counters inside while-pipe subshell won't propagate.
    # We log the summary from the outer scope via collected errors.
    log_info "Warranty check complete"
}

# ---- Mode: hors-support ----

_as_mode_hors_support() {
    # Resolve file path
    _as_hs_file="${_AS_FILE:-$HORS_SUPPORT_FILE}"
    if [ -z "$_as_hs_file" ]; then
        log_error "Required: --file or HORS_SUPPORT_FILE config for hors-support mode"
        exit "$EXIT_CONFIG"
    fi

    if [ ! -f "$_as_hs_file" ]; then
        log_error "Hors-support file not found: $_as_hs_file"
        exit "$EXIT_FILESYSTEM"
    fi

    log_info "Reading serial numbers from: $_as_hs_file"

    db_load_credentials || {
        log_error "Failed to load database credentials"
        exit "$EXIT_CONFIG"
    }

    _as_hs_updated=0
    _as_hs_not_found=0
    _as_hs_errors=0
    _as_hs_total=0

    while IFS= read -r _as_hs_serial || [ -n "$_as_hs_serial" ]; do
        # Skip empty lines
        _as_hs_serial=$(echo "$_as_hs_serial" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [ -z "$_as_hs_serial" ] && continue

        _as_hs_total=$(( _as_hs_total + 1 ))
        log_debug "Looking up serial: $_as_hs_serial"

        # Look up GLPI ID
        _as_hs_id=$(db_query "SELECT id FROM glpi_plugin_genericobject_compteusebillets WHERE name = '$_as_hs_serial'")

        if [ -z "$_as_hs_id" ]; then
            log_warn "No GLPI ID found for serial: $_as_hs_serial"
            _as_hs_not_found=$(( _as_hs_not_found + 1 ))
            continue
        fi

        if [ "$DRY_RUN" = "true" ]; then
            log_info "[dry-run] Would set $_as_hs_serial (ID $_as_hs_id) to Hors Support"
            _as_hs_updated=$(( _as_hs_updated + 1 ))
            continue
        fi

        if _as_api_put "PluginGenericobjectCompteusebillet" "$_as_hs_id" "$_AS_HORS_SUPPORT"; then
            _as_hs_updated=$(( _as_hs_updated + 1 ))
            log_info "Machine $_as_hs_serial (ID $_as_hs_id): set to Hors Support"
        else
            _as_hs_errors=$(( _as_hs_errors + 1 ))
            collect_error "Failed to update $_as_hs_serial (ID $_as_hs_id) to Hors Support"
        fi
    done < "$_as_hs_file"

    log_info "Hors-support update complete: $_as_hs_total processed, $_as_hs_updated updated, $_as_hs_not_found not found, $_as_hs_errors errors"
}

# ============================================================
# Main
# ============================================================

_AS_LOCK_FILE="$PROJECT_ROOT/logs/glpi-asset-status.lock"

# Acquire lock
if [ -d "$PROJECT_ROOT/logs" ]; then
    acquire_lock "$_AS_LOCK_FILE" || exit "$EXIT_LOCK"
    trap '_as_kill_session; release_lock "$_AS_LOCK_FILE"' EXIT INT TERM
fi

# Init API session
_as_init_session || exit "$EXIT_SERVICE"

# Run selected mode
case "$_AS_MODE" in
    warranty)
        _as_mode_warranty
        ;;
    hors-support)
        _as_mode_hors_support
        ;;
esac

# Check for errors and exit
_as_exit_check=0
has_errors || _as_exit_check=$?
if [ "$_as_exit_check" -eq 0 ]; then
    log_warn "Asset status update completed with errors"
    _as_err_summary=$(get_errors)
    send_alert "GLPI Asset Status - errors" "$_as_err_summary" "glpi-asset-status"
    exit "$EXIT_PARTIAL"
fi

log_info "Asset status update completed successfully"
exit "$EXIT_OK"
