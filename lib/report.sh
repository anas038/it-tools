#!/bin/sh
# lib/report.sh — Report generation helpers for it-tools
# Depends on: lib/common.sh (must be sourced first), lib/db.sh
#
# Provides HTML report generation and CSV formatting functions
# used by the ticket quality control report tool.
# All functions write to stdout (caller redirects to file).

# ============================================================
# Plugin table verification
# ============================================================

report_check_plugin_tables() {
    _rpt_tables="glpi_plugin_fields_ticketrfrenceticketexternes
glpi_plugin_fields_clientfielddropdowns
glpi_plugin_fields_villefielddropdowns
glpi_plugin_genericobject_compteusebillets"

    _rpt_missing=""
    for _rpt_tbl in $_rpt_tables; do
        _rpt_exists=$(db_query "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '$_DB_NAME' AND table_name = '$_rpt_tbl'")
        if [ "$_rpt_exists" != "1" ]; then
            _rpt_missing="$_rpt_missing $_rpt_tbl"
        fi
    done

    if [ -n "$_rpt_missing" ]; then
        log_warn "Missing plugin tables:$_rpt_missing"
        log_warn "Report controls require GLPI Fields and Generic Object plugins"
        return 1
    fi
    return 0
}

# ============================================================
# HTML generation
# ============================================================

report_html_header() {
    _rpt_title="$1"
    _rpt_desc="$2"
    _rpt_date="$3"

    cat << RPTEOF
<html><body style='font-family:Arial,sans-serif;'>
<div style='max-width:1000px; margin:0 auto;'>
<h2 style='color:#2c3e50;'>$_rpt_title - Rapport du $_rpt_date</h2>
<p style='line-height:1.6;'>
$_rpt_desc
</p>
<p style='margin-top:20px;line-height:1.6;'>
Merci de compléter les informations manquantes dans GLPI pour ces tickets.<br>
</p>
<p><b>Tableau de contrôle :</b></p>
<table border='1' cellpadding='5' cellspacing='0' style='border-collapse:collapse;width:100%;margin-top:20px;'>
RPTEOF
}

report_html_table_header() {
    printf "<tr style=\"background-color:#3498db;color:white;\">\n"
    for _rpt_col in "$@"; do
        printf "<th style=\"padding:8px;text-align:left;\">%s</th>\n" "$_rpt_col"
    done
    printf "</tr>\n"
}

report_html_table_row() {
    _rpt_ticket_url="$1"
    _rpt_id="$2"
    shift 2

    printf "<tr>\n"
    printf "<td style='padding:8px;border-bottom:1px solid #ddd;'><a href=\"%s%s\" target=\"_blank\" style='color:#2980b9;text-decoration:none;font-weight:bold;'>%s</a></td>\n" "$_rpt_ticket_url" "$_rpt_id" "$_rpt_id"
    for _rpt_val in "$@"; do
        printf "<td style='padding:8px;border-bottom:1px solid #ddd;'>%s</td>\n" "$_rpt_val"
    done
    printf "</tr>\n"
}

report_html_group_header() {
    _rpt_label="$1"
    _rpt_colspan="${2:-9}"

    printf "<tr style='background-color:#e6f3ff;'>\n"
    printf "<td colspan='%s' style='padding:8px;font-weight:bold;'>Technicien: %s</td>\n" "$_rpt_colspan" "$_rpt_label"
    printf "</tr>\n"
}

report_html_footer() {
    _rpt_sig="$1"

    cat << RPTEOF
</table>
<p style='border-top:1px solid #eee;padding-top:10px;color:#7f8c8d;'>
Cordialement,<br>
<strong>$_rpt_sig</strong><br>
</p>
</div></body></html>
RPTEOF
}

# ============================================================
# CSV generation
# ============================================================

report_csv_header() {
    _rpt_first=true
    for _rpt_col in "$@"; do
        if [ "$_rpt_first" = "true" ]; then
            _rpt_first=false
        else
            printf ","
        fi
        printf '"%s"' "$_rpt_col"
    done
    printf "\n"
}

report_csv_row() {
    _rpt_first=true
    for _rpt_val in "$@"; do
        if [ "$_rpt_first" = "true" ]; then
            _rpt_first=false
        else
            printf ","
        fi
        # Quote fields that may contain commas
        printf '"%s"' "$_rpt_val"
    done
    printf "\n"
}
