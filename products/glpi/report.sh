#!/bin/sh
# description: Ticket quality control reports for GLPI
# usage: it glpi report [--control 01|02|04|05] [--dry-run] [--verbose] [--quiet]
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

. "$PROJECT_ROOT/lib/common.sh"
. "$PROJECT_ROOT/lib/alert.sh"
. "$PROJECT_ROOT/lib/db.sh"
. "$PROJECT_ROOT/lib/report.sh"

# ---- Config ----
_CONFIG_FILE="$SCRIPT_DIR/glpi.conf"
if [ -f "$_CONFIG_FILE" ]; then
    load_config "$_CONFIG_FILE"
fi

REPORT_OUTPUT_DIR="${REPORT_OUTPUT_DIR:-/tmp}"
REPORT_CONTROLS="${REPORT_CONTROLS:-01,02,04,05}"
REPORT_CATEGORIES="${REPORT_CATEGORIES:-Intervention Préventive,Intervention Curative}"
REPORT_SIGNATURE="${REPORT_SIGNATURE:-Équipe Technique}"
REPORT_FROM_NAME="${REPORT_FROM_NAME:-it-tools}"
REPORT_MIN_PDF_PAGES="${REPORT_MIN_PDF_PAGES:-2}"
GLPI_TICKET_URL="${GLPI_TICKET_URL:-}"
GLPI_INSTALL_PATH="${GLPI_INSTALL_PATH:-/var/www/html/glpi}"

# ---- Parse flags ----
_RPT_CONTROL=""
_ARGS=""
while [ $# -gt 0 ]; do
    case "$1" in
        --control)
            shift
            _RPT_CONTROL="$1"
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
Usage: it glpi report [--control 01|02|04|05] [--dry-run] [--verbose] [--quiet]

Generates ticket quality control reports for GLPI.

Controls:
  01  Missing serial number (SN) or report number
  02  Missing "Pannes" field
  04  No attachments
  05  PDF attachments with too many pages

Options:
  --control N   Run only control N (01, 02, 04, or 05)
  --dry-run     Preview without executing queries
  --verbose     Enable debug logging
  --quiet       Suppress non-error output
  --help        Show this help
EOF
    exit 0
}

# ---- Validate --control value if specified ----
if [ -n "$_RPT_CONTROL" ]; then
    case "$_RPT_CONTROL" in
        01|02|04|05) ;;
        *) log_error "Invalid control: $_RPT_CONTROL (valid: 01, 02, 04, 05)"
           exit "$EXIT_CONFIG" ;;
    esac
    REPORT_CONTROLS="$_RPT_CONTROL"
fi

# ---- Setup ----
_RPT_DATE_FILE=$(date +'%Y%m%d')
_RPT_DATE_DISPLAY=$(date +'%d/%m/%Y')
_RPT_LOCK_FILE="$PROJECT_ROOT/logs/glpi-report.lock"
_RPT_GENERATED=0
_RPT_SKIPPED=0

# ---- Build category SQL clause ----
_rpt_build_category_clause() {
    _rbc_clause=""
    _rbc_old_ifs="$IFS"
    IFS=","
    for _rbc_cat in $REPORT_CATEGORIES; do
        if [ -n "$_rbc_clause" ]; then
            _rbc_clause="$_rbc_clause, "
        fi
        _rbc_clause="$_rbc_clause'$_rbc_cat'"
    done
    IFS="$_rbc_old_ifs"
    echo "$_rbc_clause"
}

# ---- Base SQL (shared by all controls) ----
_rpt_base_select() {
    cat << 'SQLEOF'
SELECT
    t.id,
    IFNULL((
        SELECT CONCAT(u.realname, ' ', u.firstname)
        FROM glpi_tickets_users tu
        JOIN glpi_users u ON tu.users_id = u.id
        WHERE tu.tickets_id = t.id AND tu.type = 2
        LIMIT 1
    ), ''),
    IFNULL(client.name, ''),
    IFNULL(ville.name, ''),
    IFNULL(c.name, ''),
    IFNULL(DATE_FORMAT(t.solvedate, '%Y-%m-%d'), ''),
    IFNULL(f.nrapportfieldtwo, ''),
    IFNULL(f.daterapportfield, ''),
    IFNULL(gobj.name, '')
SQLEOF
}

_rpt_base_from() {
    cat << 'SQLEOF'
FROM glpi_tickets t
LEFT JOIN glpi_itilcategories c ON t.itilcategories_id = c.id
LEFT JOIN glpi_plugin_fields_ticketrfrenceticketexternes f
    ON f.items_id = t.id AND f.itemtype = 'Ticket'
LEFT JOIN glpi_plugin_fields_clientfielddropdowns client
    ON client.id = f.plugin_fields_clientfielddropdowns_id
LEFT JOIN glpi_plugin_fields_villefielddropdowns ville
    ON ville.id = f.plugin_fields_villefielddropdowns_id
LEFT JOIN glpi_plugin_genericobject_compteusebillets gobj
    ON gobj.id = JSON_UNQUOTE(JSON_EXTRACT(
        f.plugin_genericobject_compteusebillets_id_snfieldtwo, '$[0]'))
SQLEOF
}

# ---- Control-specific queries ----

_rpt_query_01() {
    _rq_cats="$1"
    _rpt_base_select
    _rpt_base_from
    cat << SQLEOF
WHERE t.status = 5
  AND c.name IN ($_rq_cats)
  AND (
      f.plugin_genericobject_compteusebillets_id_snfieldtwo IS NULL
      OR f.plugin_genericobject_compteusebillets_id_snfieldtwo = ''
      OR f.plugin_genericobject_compteusebillets_id_snfieldtwo = '0'
      OR f.nrapportfieldtwo IS NULL
      OR f.nrapportfieldtwo = ''
  )
  AND (
      f.nrapportfieldtwo NOT LIKE '%FERMETURE%'
      AND f.nrapportfieldtwo NOT LIKE '%Fermeture%'
  )
ORDER BY
    IFNULL((SELECT CONCAT(u.realname, ' ', u.firstname) FROM glpi_tickets_users tu JOIN glpi_users u ON tu.users_id = u.id WHERE tu.tickets_id = t.id AND tu.type = 2 LIMIT 1), ''),
    t.solvedate DESC
SQLEOF
}

_rpt_query_02() {
    _rq_cats="$1"
    _rpt_base_select
    _rpt_base_from
    cat << SQLEOF
WHERE t.status = 5
  AND c.name IN ($_rq_cats)
  AND (
      f.plugin_fields_pannefielddropdowns_id IS NULL
      OR f.plugin_fields_pannefielddropdowns_id = ''
      OR f.plugin_fields_pannefielddropdowns_id = '0'
  )
ORDER BY
    IFNULL((SELECT CONCAT(u.realname, ' ', u.firstname) FROM glpi_tickets_users tu JOIN glpi_users u ON tu.users_id = u.id WHERE tu.tickets_id = t.id AND tu.type = 2 LIMIT 1), ''),
    t.solvedate DESC
SQLEOF
}

_rpt_query_04() {
    _rq_cats="$1"
    cat << SQLEOF
SET SESSION sql_mode=(SELECT REPLACE(@@sql_mode,'ONLY_FULL_GROUP_BY',''));
SQLEOF
    _rpt_base_select
    _rpt_base_from
    cat << SQLEOF
LEFT JOIN (
    SELECT items_id FROM glpi_documents_items WHERE itemtype = 'Ticket'
    UNION
    SELECT s.items_id
    FROM glpi_itilsolutions s
    JOIN glpi_documents_items di ON di.items_id = s.id AND di.itemtype = 'ITILSolution'
    WHERE s.itemtype = 'Ticket'
    UNION
    SELECT fw.items_id
    FROM glpi_itilfollowups fw
    JOIN glpi_documents_items di ON di.items_id = fw.id AND di.itemtype = 'ITILFollowup'
    WHERE fw.itemtype = 'Ticket'
) AS all_docs ON all_docs.items_id = t.id
WHERE t.status = 5
  AND c.name IN ($_rq_cats)
  AND all_docs.items_id IS NULL
ORDER BY
    IFNULL((SELECT CONCAT(u.realname, ' ', u.firstname) FROM glpi_tickets_users tu JOIN glpi_users u ON tu.users_id = u.id WHERE tu.tickets_id = t.id AND tu.type = 2 LIMIT 1), ''),
    t.solvedate DESC
SQLEOF
}

_rpt_query_05() {
    _rq_cats="$1"
    cat << SQLEOF
SET SESSION sql_mode=(SELECT REPLACE(@@sql_mode,'ONLY_FULL_GROUP_BY',''));
SQLEOF
    printf "SELECT\n    t.id,\n"
    printf "    IFNULL((\n"
    printf "        SELECT CONCAT(u.realname, ' ', u.firstname)\n"
    printf "        FROM glpi_tickets_users tu\n"
    printf "        JOIN glpi_users u ON tu.users_id = u.id\n"
    printf "        WHERE tu.tickets_id = t.id AND tu.type = 2\n"
    printf "        LIMIT 1\n"
    printf "    ), ''),\n"
    printf "    IFNULL(client.name, ''),\n"
    printf "    IFNULL(ville.name, ''),\n"
    printf "    IFNULL(c.name, ''),\n"
    printf "    IFNULL(DATE_FORMAT(t.solvedate, '%%Y-%%m-%%d'), ''),\n"
    printf "    IFNULL(f.nrapportfieldtwo, ''),\n"
    printf "    IFNULL(f.daterapportfield, ''),\n"
    printf "    IFNULL(gobj.name, ''),\n"
    printf "    GROUP_CONCAT(DISTINCT d.filepath SEPARATOR '|')\n"
    _rpt_base_from
    cat << SQLEOF
LEFT JOIN glpi_documents_items di_ticket
    ON di_ticket.items_id = t.id AND di_ticket.itemtype = 'Ticket'
LEFT JOIN glpi_itilsolutions s
    ON s.itemtype = 'Ticket' AND s.items_id = t.id
LEFT JOIN glpi_documents_items di_sol
    ON di_sol.items_id = s.id AND di_sol.itemtype = 'ITILSolution'
LEFT JOIN glpi_itilfollowups tf
    ON tf.itemtype = 'Ticket' AND tf.items_id = t.id
LEFT JOIN glpi_documents_items di_followup
    ON di_followup.items_id = tf.id AND di_followup.itemtype = 'ITILFollowup'
LEFT JOIN glpi_documents d
    ON d.id IN (di_ticket.documents_id, di_sol.documents_id, di_followup.documents_id)
    AND (LOWER(d.filename) LIKE '%.pdf' OR d.mime = 'application/pdf')
WHERE t.status = 5
  AND c.name IN ($_rq_cats)
GROUP BY t.id
HAVING COUNT(DISTINCT d.id) >= 1
ORDER BY
    IFNULL((SELECT CONCAT(u.realname, ' ', u.firstname) FROM glpi_tickets_users tu JOIN glpi_users u ON tu.users_id = u.id WHERE tu.tickets_id = t.id AND tu.type = 2 LIMIT 1), ''),
    t.solvedate DESC
SQLEOF
}

# ---- Control descriptions (French, for reports) ----

_rpt_control_title() {
    case "$1" in
        01) echo "Contrôle des tickets résolus" ;;
        02) echo "Contrôle des tickets résolus" ;;
        04) echo "Contrôle des tickets résolus" ;;
        05) echo "Contrôle des tickets résolus" ;;
    esac
}

_rpt_control_description() {
    case "$1" in
        01) printf "Ce rapport liste les tickets <b>résolus</b> des catégories suivantes :<br>\n"
            _rpt_print_categories
            printf "Pour lesquels le numéro de série (SN) ou le numéro de rapport (N° Rapport) n'ont pas été renseignés.\n" ;;
        02) printf "Ce rapport liste les tickets <b>résolus</b> des catégories suivantes :<br>\n"
            _rpt_print_categories
            printf "Pour lesquels le champ <b>Pannes</b> n'a pas été renseigné.\n" ;;
        04) printf "Ce rapport liste les tickets <b>résolus</b> des catégories suivantes :<br>\n"
            _rpt_print_categories
            printf "Pour lesquels <b>aucune pièce jointe</b> (d'aucun type) n'a été attachée.\n" ;;
        05) printf "Ce rapport liste les tickets <b>résolus</b> des catégories suivantes :<br>\n"
            _rpt_print_categories
            printf "Pour lesquels une pièce jointe PDF contient <b>au moins %s pages</b>.\n" "$REPORT_MIN_PDF_PAGES" ;;
    esac
}

_rpt_print_categories() {
    _rpc_old_ifs="$IFS"
    IFS=","
    for _rpc_cat in $REPORT_CATEGORIES; do
        printf "- %s<br>\n" "$_rpc_cat"
    done
    IFS="$_rpc_old_ifs"
    printf "<br>\n"
}

# ---- Generate report for a single control ----

_rpt_generate_control() {
    _rgc_num="$1"
    _rgc_cats="$2"
    _rgc_csv="$REPORT_OUTPUT_DIR/glpi-control-${_rgc_num}-${_RPT_DATE_FILE}.csv"
    _rgc_html="$REPORT_OUTPUT_DIR/glpi-control-${_rgc_num}-${_RPT_DATE_FILE}.html"

    log_info "Running control $_rgc_num..."

    # Build SQL query
    _rgc_sql=$( case "$_rgc_num" in
        01) _rpt_query_01 "$_rgc_cats" ;;
        02) _rpt_query_02 "$_rgc_cats" ;;
        04) _rpt_query_04 "$_rgc_cats" ;;
        05) _rpt_query_05 "$_rgc_cats" ;;
    esac )

    log_debug "SQL for control $_rgc_num: $_rgc_sql"

    # Execute query
    _rgc_result=$(db_query "$_rgc_sql") || {
        collect_error "Control $_rgc_num: database query failed"
        return 1
    }

    # Handle dry-run (db_query returns empty)
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[dry-run] Would generate CSV: $_rgc_csv"
        log_info "[dry-run] Would generate HTML: $_rgc_html"
        return 0
    fi

    # Check for empty results
    if [ -z "$_rgc_result" ]; then
        log_info "Control $_rgc_num: no matching tickets found"
        _RPT_SKIPPED=$(( _RPT_SKIPPED + 1 ))
        return 0
    fi

    # For control 05, apply pdfinfo post-filter
    if [ "$_rgc_num" = "05" ]; then
        _rgc_result=$(_rpt_filter_pdf_pages "$_rgc_result")
        if [ -z "$_rgc_result" ]; then
            log_info "Control 05: no tickets with PDF >= $REPORT_MIN_PDF_PAGES pages"
            _RPT_SKIPPED=$(( _RPT_SKIPPED + 1 ))
            return 0
        fi
    fi

    # Generate CSV
    {
        report_csv_header "ID" "Technicien" "Client" "Ville" "Categorie" \
            "Date résolution" "Numéro Rapport" "Date Rapport" "Numéro Serie"
        echo "$_rgc_result" | while IFS='	' read -r _id _tech _client _ville _cat _date _rapport _date_r _sn _extra; do
            report_csv_row "$_id" "$_tech" "$_client" "$_ville" "$_cat" \
                "$_date" "$_rapport" "$_date_r" "$_sn"
        done
    } > "$_rgc_csv"
    log_info "CSV saved: $_rgc_csv"

    # Generate HTML
    {
        _rgc_title=$(_rpt_control_title "$_rgc_num")
        _rgc_desc=$(_rpt_control_description "$_rgc_num")
        report_html_header "$_rgc_title" "$_rgc_desc" "$_RPT_DATE_DISPLAY"
        report_html_table_header "ID" "Technicien" "Client" "Ville" "Categorie" \
            "Date résolution" "Numéro Rapport" "Date Rapport" "Numéro Serie"

        _rgc_current_tech=""
        echo "$_rgc_result" | sort -t'	' -k2,2 -k6,6r | \
        while IFS='	' read -r _id _tech _client _ville _cat _date _rapport _date_r _sn _extra; do
            # Group by technician
            if [ "$_tech" != "$_rgc_current_tech" ]; then
                _rgc_current_tech="$_tech"
                report_html_group_header "$_tech"
            fi
            report_html_table_row "$GLPI_TICKET_URL" "$_id" "$_tech" "$_client" \
                "$_ville" "$_cat" "$_date" "$_rapport" "$_date_r" "$_sn"
        done

        report_html_footer "$REPORT_SIGNATURE"
    } > "$_rgc_html"
    log_info "HTML saved: $_rgc_html"

    _RPT_GENERATED=$(( _RPT_GENERATED + 1 ))
    return 0
}

# ---- Control 05: PDF page count filter ----

_rpt_filter_pdf_pages() {
    _rfp_input="$1"
    _rfp_pdf_base="$GLPI_INSTALL_PATH/files"

    if ! command -v pdfinfo >/dev/null 2>&1; then
        log_warn "pdfinfo not found — skipping PDF page count filter"
        echo "$_rfp_input"
        return 0
    fi

    echo "$_rfp_input" | while IFS='	' read -r _id _tech _client _ville _cat _date _rapport _date_r _sn _paths; do
        [ -z "$_id" ] && continue
        _rfp_multipage=false

        # Split pipe-separated paths
        _rfp_old_ifs="$IFS"
        IFS='|'
        for _rfp_rel_path in $_paths; do
            [ -z "$_rfp_rel_path" ] && continue
            _rfp_full_path="$_rfp_pdf_base/$_rfp_rel_path"
            if [ -f "$_rfp_full_path" ]; then
                _rfp_pages=$(pdfinfo "$_rfp_full_path" 2>/dev/null | sed -n 's/^Pages: *//p')
                _rfp_pages="${_rfp_pages:-0}"
                if [ "$_rfp_pages" -ge "$REPORT_MIN_PDF_PAGES" ] 2>/dev/null; then
                    _rfp_multipage=true
                    break
                fi
            fi
        done
        IFS="$_rfp_old_ifs"

        if [ "$_rfp_multipage" = "true" ]; then
            printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
                "$_id" "$_tech" "$_client" "$_ville" "$_cat" "$_date" "$_rapport" "$_date_r" "$_sn"
        fi
    done
}

# ============================================================
# Main
# ============================================================

# Acquire lock
if [ -d "$PROJECT_ROOT/logs" ]; then
    acquire_lock "$_RPT_LOCK_FILE" || exit "$EXIT_LOCK"
    trap 'release_lock "$_RPT_LOCK_FILE"' EXIT INT TERM
fi

# Load DB credentials
db_load_credentials || {
    log_error "Failed to load database credentials"
    exit "$EXIT_CONFIG"
}

# Check plugin tables
if [ "$DRY_RUN" != "true" ]; then
    _rpt_tables_ok=0
    report_check_plugin_tables || _rpt_tables_ok=$?
    if [ "$_rpt_tables_ok" -ne 0 ]; then
        log_warn "Skipping report generation — plugin tables not found"
        exit "$EXIT_OK"
    fi
fi

# Build category clause
_RPT_CAT_CLAUSE=$(_rpt_build_category_clause)
log_debug "Category clause: $_RPT_CAT_CLAUSE"

# Run controls
_rpt_old_ifs="$IFS"
IFS=","
for _rpt_ctl in $REPORT_CONTROLS; do
    _rpt_generate_control "$_rpt_ctl" "$_RPT_CAT_CLAUSE" || true
done
IFS="$_rpt_old_ifs"

# Summary
log_info "Report generation complete: $_RPT_GENERATED generated, $_RPT_SKIPPED skipped (no data)"

# Send alert with summary if reports were generated
if [ "$_RPT_GENERATED" -gt 0 ] && [ "$DRY_RUN" != "true" ]; then
    _rpt_alert_body="Reports generated: $_RPT_GENERATED"
    _rpt_has_err=0
    has_errors || _rpt_has_err=$?
    if [ "$_rpt_has_err" -eq 0 ]; then
        _rpt_alert_body="$_rpt_alert_body (with errors: $(get_errors))"
    fi
    send_alert "GLPI Report - $REPORT_FROM_NAME" "$_rpt_alert_body" "glpi-report"
fi

# Exit with appropriate code
_rpt_exit_check=0
has_errors || _rpt_exit_check=$?
if [ "$_rpt_exit_check" -eq 0 ]; then
    log_warn "Report generation completed with errors"
    get_errors | while read -r _rpt_err_line; do
        log_error "  $_rpt_err_line"
    done
    exit "$EXIT_PARTIAL"
fi

exit "$EXIT_OK"
