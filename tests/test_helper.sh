#!/bin/sh
# test_helper.sh — Test assertion library for it-tools
# POSIX sh compliant — no bash-isms

_TESTS_RUN=0
_TESTS_PASSED=0
_TESTS_FAILED=0
_CURRENT_TEST=""

test_start() {
    _CURRENT_TEST="$1"
    _TESTS_RUN=$(( _TESTS_RUN + 1 ))
}

_test_pass() {
    _TESTS_PASSED=$(( _TESTS_PASSED + 1 ))
}

_test_fail() {
    _msg="$1"
    _TESTS_FAILED=$(( _TESTS_FAILED + 1 ))
    echo "  FAIL [${_CURRENT_TEST}]: ${_msg}" >&2
}

assert_equals() {
    _expected="$1"
    _actual="$2"
    _msg="${3:-expected '${_expected}' but got '${_actual}'}"
    if [ "$_expected" = "$_actual" ]; then
        _test_pass
    else
        _test_fail "$_msg"
    fi
}

assert_true() {
    _value="$1"
    _msg="${2:-expected 0 (true) but got '${_value}'}"
    if [ "$_value" -eq 0 ] 2>/dev/null; then
        _test_pass
    else
        _test_fail "$_msg"
    fi
}

assert_false() {
    _value="$1"
    _msg="${2:-expected non-zero (false) but got '${_value}'}"
    if [ "$_value" -ne 0 ] 2>/dev/null; then
        _test_pass
    else
        _test_fail "$_msg"
    fi
}

assert_contains() {
    _haystack="$1"
    _needle="$2"
    _msg="${3:-expected '${_haystack}' to contain '${_needle}'}"
    case "$_haystack" in
        *"$_needle"*)
            _test_pass
            ;;
        *)
            _test_fail "$_msg"
            ;;
    esac
}

assert_not_contains() {
    _haystack="$1"
    _needle="$2"
    _msg="${3:-expected '${_haystack}' to not contain '${_needle}'}"
    case "$_haystack" in
        *"$_needle"*)
            _test_fail "$_msg"
            ;;
        *)
            _test_pass
            ;;
    esac
}

assert_file_exists() {
    _path="$1"
    _msg="${2:-expected file '${_path}' to exist}"
    if [ -f "$_path" ]; then
        _test_pass
    else
        _test_fail "$_msg"
    fi
}

test_summary() {
    echo ""
    echo "Tests run: ${_TESTS_RUN}"
    echo "Passed:    ${_TESTS_PASSED}"
    echo "Failed:    ${_TESTS_FAILED}"
    if [ "$_TESTS_FAILED" -gt 0 ]; then
        return 1
    fi
    return 0
}
