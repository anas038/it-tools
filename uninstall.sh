#!/bin/sh
# uninstall.sh — Clean removal of it-tools
# Design doc §27
set -eu

INSTALL_DIR="/opt/it-tools"

_RED='\033[0;31m'
_GREEN='\033[0;32m'
_YELLOW='\033[0;33m'
_BLUE='\033[0;34m'
_NC='\033[0m'

_info()  { printf "${_BLUE}[INFO]${_NC} %s\n" "$*"; }
_ok()    { printf "${_GREEN}[OK]${_NC} %s\n" "$*"; }
_warn()  { printf "${_YELLOW}[WARN]${_NC} %s\n" "$*"; }
_error() { printf "${_RED}[ERROR]${_NC} %s\n" "$*" >&2; }

_ask_yn() {
    printf "${_BLUE}?${_NC} %s [y/N] " "$1"
    read -r _answer
    case "$_answer" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

# ---- Parse flags ----
_KEEP_CONFIG=false
_PURGE_ALL=false
_INTERACTIVE=true

while [ $# -gt 0 ]; do
    case "$1" in
        --keep-config) _KEEP_CONFIG=true; _INTERACTIVE=false ;;
        --purge)       _PURGE_ALL=true; _INTERACTIVE=false ;;
        --help|-h)
            cat << EOF
Usage: uninstall.sh [--keep-config | --purge]

Options:
  --keep-config   Remove tools but preserve config files and logs
  --purge         Remove everything including configs and logs
  (default)       Interactive — asks what to keep
EOF
            exit 0
            ;;
        *) _error "Unknown option: $1"; exit 1 ;;
    esac
    shift
done

_SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    _SUDO="sudo"
fi

printf "\n"
printf "${_RED}╔══════════════════════════════════════╗${_NC}\n"
printf "${_RED}║   it-tools uninstaller               ║${_NC}\n"
printf "${_RED}╚══════════════════════════════════════╝${_NC}\n"
printf "\n"

if [ ! -d "$INSTALL_DIR" ]; then
    _error "it-tools not found at $INSTALL_DIR"
    exit 1
fi

# ---- Config preservation ----
if [ "$_INTERACTIVE" = "true" ]; then
    if _ask_yn "Keep config files and logs?"; then
        _KEEP_CONFIG=true
    fi
fi

# ---- Remove symlink ----
if [ -L "/usr/local/bin/it" ]; then
    $_SUDO rm -f /usr/local/bin/it
    _ok "Removed symlink: /usr/local/bin/it"
fi

# ---- Remove PATH entries ----
for _pf in "$HOME/.profile" "$HOME/.bashrc" "$HOME/.bash_profile"; do
    if [ -f "$_pf" ] && grep -q "$INSTALL_DIR/bin" "$_pf" 2>/dev/null; then
        _tmp=$(mktemp)
        grep -v "$INSTALL_DIR/bin" "$_pf" > "$_tmp"
        mv "$_tmp" "$_pf"
        _ok "Removed PATH entry from $_pf"
    fi
done

# ---- Remove cron entries ----
_cron_user=$(whoami)
_existing=$(crontab -u "$_cron_user" -l 2>/dev/null || true)
if echo "$_existing" | grep -q "it-tools\|$INSTALL_DIR"; then
    echo "$_existing" | grep -v "it-tools\|$INSTALL_DIR" | \
        crontab -u "$_cron_user" -
    _ok "Removed cron entries for $_cron_user"
fi

# ---- Backup configs if keeping ----
if [ "$_KEEP_CONFIG" = "true" ]; then
    _backup_dir="/tmp/it-tools-config-backup-$(date '+%Y%m%d%H%M%S')"
    mkdir -p "$_backup_dir"
    # Copy config files
    find "$INSTALL_DIR/products" -name "*.conf" -exec cp {} "$_backup_dir/" \; 2>/dev/null || true
    # Copy logs
    cp -r "$INSTALL_DIR/logs" "$_backup_dir/" 2>/dev/null || true
    _ok "Configs and logs backed up to: $_backup_dir"
fi

# ---- Remove install directory ----
if [ "$_INTERACTIVE" = "true" ]; then
    if _ask_yn "Remove $INSTALL_DIR?"; then
        $_SUDO rm -rf "$INSTALL_DIR"
        _ok "Removed: $INSTALL_DIR"
    else
        _info "Skipped removal of $INSTALL_DIR"
    fi
else
    $_SUDO rm -rf "$INSTALL_DIR"
    _ok "Removed: $INSTALL_DIR"
fi

printf "\n"
_ok "it-tools has been uninstalled"
if [ "$_KEEP_CONFIG" = "true" ]; then
    _info "Config backup: $_backup_dir"
fi
printf "\n"
