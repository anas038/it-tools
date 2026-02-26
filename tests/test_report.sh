#!/bin/sh
# test_report.sh — Tests for lib/report.sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$PROJECT_ROOT/tests/test_helper.sh"
. "$PROJECT_ROOT/lib/common.sh"

# Mock db_query for report_check_plugin_tables
_DB_NAME="test_db"
db_query() { echo "$_MOCK_DB_RESULT"; }

. "$PROJECT_ROOT/lib/report.sh"

# ============================================================
# report_html_header
# ============================================================

test_start "report_html_header produces valid HTML opening"
_output=$(report_html_header "Test Title" "Test description" "01/01/2026")
assert_contains "$_output" "<html>"
assert_contains "$_output" "Test Title"
assert_contains "$_output" "01/01/2026"
assert_contains "$_output" "Test description"
assert_contains "$_output" "<table"

# ============================================================
# report_html_table_header
# ============================================================

test_start "report_html_table_header produces column headers"
_output=$(report_html_table_header "ID" "Technicien" "Client")
assert_contains "$_output" "background-color:#3498db"
assert_contains "$_output" "ID"
assert_contains "$_output" "Technicien"
assert_contains "$_output" "Client"
assert_contains "$_output" "<th"

# ============================================================
# report_html_table_row
# ============================================================

test_start "report_html_table_row produces clickable ticket ID"
_output=$(report_html_table_row "https://glpi.local/ticket?id=" "42" "John" "Paris")
assert_contains "$_output" "https://glpi.local/ticket?id=42"
assert_contains "$_output" ">42</a>"
assert_contains "$_output" "John"
assert_contains "$_output" "Paris"

test_start "report_html_table_row works with empty ticket URL"
_output=$(report_html_table_row "" "42" "John")
assert_contains "$_output" ">42</a>"

# ============================================================
# report_html_group_header
# ============================================================

test_start "report_html_group_header produces technician group row"
_output=$(report_html_group_header "Martin Dupont")
assert_contains "$_output" "background-color:#e6f3ff"
assert_contains "$_output" "Technicien: Martin Dupont"
assert_contains "$_output" "font-weight:bold"

test_start "report_html_group_header accepts custom colspan"
_output=$(report_html_group_header "Test Tech" "5")
assert_contains "$_output" "colspan='5'"

# ============================================================
# report_html_footer
# ============================================================

test_start "report_html_footer includes signature and closing tags"
_output=$(report_html_footer "Équipe Technique")
assert_contains "$_output" "Équipe Technique"
assert_contains "$_output" "Cordialement"
assert_contains "$_output" "</html>"

# ============================================================
# report_csv_header
# ============================================================

test_start "report_csv_header produces quoted comma-separated line"
_output=$(report_csv_header "ID" "Technicien" "Client")
assert_contains "$_output" '"ID","Technicien","Client"'

# ============================================================
# report_csv_row
# ============================================================

test_start "report_csv_row produces quoted comma-separated values"
_output=$(report_csv_row "42" "Martin" "Paris")
assert_contains "$_output" '"42","Martin","Paris"'

test_start "report_csv_row handles empty fields"
_output=$(report_csv_row "42" "" "Paris")
assert_contains "$_output" '"42","","Paris"'

# ============================================================
# report_check_plugin_tables
# ============================================================

test_start "report_check_plugin_tables returns 0 when tables exist"
_MOCK_DB_RESULT="1"
LOG_LEVEL="error"  # suppress debug output
_result=0
report_check_plugin_tables || _result=$?
assert_true "$_result"

test_start "report_check_plugin_tables returns 1 when tables missing"
_MOCK_DB_RESULT="0"
_result=0
report_check_plugin_tables || _result=$?
assert_false "$_result"

# ============================================================
# Summary
# ============================================================

test_summary
