#!/bin/sh
# test_dispatcher.sh — Tests for bin/it dispatcher
# POSIX sh compliant — no bash-isms
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/test_helper.sh"

echo "=== test_dispatcher.sh ==="

# ============================================================
# 1. Help output shows usage
# ============================================================
test_start "dispatcher_help_shows_usage"
_output=$("$PROJECT_ROOT/bin/it" help 2>&1 || true)
assert_contains "$_output" "Usage"

# ============================================================
# 2. List shows products
# ============================================================
test_start "dispatcher_list_shows_products"
# Create a dummy product for testing
_dummy_dir="$PROJECT_ROOT/products/testprod"
mkdir -p "$_dummy_dir"
cat > "$_dummy_dir/dummy.sh" << 'EOF'
#!/bin/sh
# description: A test tool
run() { echo "dummy output"; }
if [ "${0##*/}" = "dummy.sh" ]; then run "$@"; fi
EOF
chmod +x "$_dummy_dir/dummy.sh"

_output=$("$PROJECT_ROOT/bin/it" list 2>&1 || true)
assert_contains "$_output" "testprod"

# ============================================================
# 3. Unknown product fails
# ============================================================
test_start "dispatcher_unknown_product_fails"
_result=0
"$PROJECT_ROOT/bin/it" nonexistent monitor 2>/dev/null || _result=$?
assert_false "$_result" "unknown product should return non-zero"

# Cleanup
rm -rf "$_dummy_dir"

test_summary
