#!/bin/sh
# lib/alert.sh — Multi-channel alert dispatching
# Depends on: lib/common.sh (must be sourced first)
#
# Supports: email, teams (Microsoft Teams webhook), slack, log
# Config keys: ALERT_CHANNELS, ALERT_EMAIL_TO, ALERT_TEAMS_WEBHOOK,
#              ALERT_SLACK_WEBHOOK, ALERT_COOLDOWN_MINUTES

ALERT_CHANNELS="${ALERT_CHANNELS:-log}"
ALERT_EMAIL_TO="${ALERT_EMAIL_TO:-}"
ALERT_TEAMS_WEBHOOK="${ALERT_TEAMS_WEBHOOK:-}"
ALERT_SLACK_WEBHOOK="${ALERT_SLACK_WEBHOOK:-}"
ALERT_COOLDOWN_MINUTES="${ALERT_COOLDOWN_MINUTES:-60}"

# ============================================================
# Cooldown State
# ============================================================

_cooldown_file() {
    _cf_tool="$1"
    _cf_subject="$2"
    _cf_hash=$(printf '%s:%s' "$_cf_tool" "$_cf_subject" | cksum | cut -d' ' -f1)
    _cf_state_dir="${LOG_DIR:-/tmp}"
    echo "$_cf_state_dir/.alert_cooldown_${_cf_hash}"
}

_is_in_cooldown() {
    _iic_tool="$1"
    _iic_subject="$2"
    _iic_cf=$(_cooldown_file "$_iic_tool" "$_iic_subject")
    if [ -f "$_iic_cf" ]; then
        _iic_now=$(date +%s)
        _iic_file_mod=$(stat -c %Y "$_iic_cf" 2>/dev/null || echo "0")
        _iic_age=$(( _iic_now - _iic_file_mod ))
        _iic_timeout=$(( ALERT_COOLDOWN_MINUTES * 60 ))
        if [ "$_iic_age" -lt "$_iic_timeout" ]; then
            log_debug "Alert suppressed (cooldown: ${_iic_age}s/${_iic_timeout}s): $_iic_subject"
            return 0  # still in cooldown
        fi
        rm -f "$_iic_cf"
    fi
    return 1  # not in cooldown
}

_set_cooldown() {
    _sc_tool="$1"
    _sc_subject="$2"
    _sc_cf=$(_cooldown_file "$_sc_tool" "$_sc_subject")
    touch "$_sc_cf"
}

# ============================================================
# Channel Senders
# ============================================================

_alert_log() {
    _al_subject="$1"
    _al_body="$2"
    _al_tool="$3"
    _al_log_file="${LOG_DIR:-/tmp}/alerts.log"
    _al_ts=$(date '+%Y-%m-%d %H:%M:%S')
    printf "[%s] [%s] %s: %s\n" "$_al_ts" "$_al_tool" "$_al_subject" "$_al_body" \
        >> "$_al_log_file"
}

_alert_email() {
    _ae_subject="$1"
    _ae_body="$2"
    _ae_tool="$3"
    if [ -z "$ALERT_EMAIL_TO" ]; then
        log_warn "ALERT_EMAIL_TO not configured, skipping email alert"
        return 0
    fi
    printf '%s\n' "$_ae_body" | mail -s "[it-tools/$_ae_tool] $_ae_subject" "$ALERT_EMAIL_TO" \
        2>/dev/null || {
        log_warn "Failed to send email alert to $ALERT_EMAIL_TO"
        collect_error "Email alert failed: $_ae_subject"
    }
}

_alert_teams() {
    _at_subject="$1"
    _at_body="$2"
    _at_tool="$3"
    if [ -z "$ALERT_TEAMS_WEBHOOK" ]; then
        log_warn "ALERT_TEAMS_WEBHOOK not configured, skipping Teams alert"
        return 0
    fi
    _at_payload=$(printf '{"@type":"MessageCard","summary":"%s","sections":[{"activityTitle":"[it-tools/%s] %s","text":"%s"}]}' \
        "$_at_subject" "$_at_tool" "$_at_subject" "$_at_body")
    curl -s -o /dev/null -w '' -H "Content-Type: application/json" \
        -d "$_at_payload" "$ALERT_TEAMS_WEBHOOK" 2>/dev/null || {
        log_warn "Failed to send Teams alert"
        collect_error "Teams alert failed: $_at_subject"
    }
}

_alert_slack() {
    _as_subject="$1"
    _as_body="$2"
    _as_tool="$3"
    if [ -z "$ALERT_SLACK_WEBHOOK" ]; then
        log_warn "ALERT_SLACK_WEBHOOK not configured, skipping Slack alert"
        return 0
    fi
    _as_payload=$(printf '{"text":"*[it-tools/%s] %s*\n%s"}' \
        "$_as_tool" "$_as_subject" "$_as_body")
    curl -s -o /dev/null -w '' -H "Content-Type: application/json" \
        -d "$_as_payload" "$ALERT_SLACK_WEBHOOK" 2>/dev/null || {
        log_warn "Failed to send Slack alert"
        collect_error "Slack alert failed: $_as_subject"
    }
}

# ============================================================
# Main Dispatcher
# ============================================================

send_alert() {
    _sa_subject="$1"
    _sa_body="$2"
    _sa_tool="${3:-unknown}"

    # Check cooldown
    if _is_in_cooldown "$_sa_tool" "$_sa_subject"; then
        return 0
    fi

    log_info "Sending alert: $_sa_subject"

    # Parse channels (comma-separated)
    _sa_channels="$ALERT_CHANNELS"
    _sa_old_ifs="$IFS"
    IFS=','
    for _sa_channel in $_sa_channels; do
        # Trim whitespace
        _sa_channel=$(echo "$_sa_channel" | tr -d ' ')
        case "$_sa_channel" in
            log)   _alert_log   "$_sa_subject" "$_sa_body" "$_sa_tool" ;;
            email) _alert_email "$_sa_subject" "$_sa_body" "$_sa_tool" ;;
            teams) _alert_teams "$_sa_subject" "$_sa_body" "$_sa_tool" ;;
            slack) _alert_slack "$_sa_subject" "$_sa_body" "$_sa_tool" ;;
            *)     log_warn "Unknown alert channel: $_sa_channel" ;;
        esac
    done
    IFS="$_sa_old_ifs"

    # Set cooldown after sending
    _set_cooldown "$_sa_tool" "$_sa_subject"
}
