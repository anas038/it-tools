#!/bin/sh
# install.sh — IT-Tools installer
# Supports interactive (default) and non-interactive (via flags) modes
# Design doc: §18-§26
set -eu

INSTALL_DIR="/opt/it-tools"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ---- Defaults (overridden by flags in non-interactive mode) ----
INSTALL_USER=""
INSTALL_PRODUCT="glpi"
INSTALL_PATH_METHOD=""  # symlink or profile
INSTALL_INTERACTIVE=true
INSTALL_CRON=""  # yes, no, or empty (ask)

# ---- Colors ----
_RED='\033[0;31m'
_GREEN='\033[0;32m'
_YELLOW='\033[0;33m'
_BLUE='\033[0;34m'
_NC='\033[0m'

_info()  { printf "${_BLUE}[INFO]${_NC} %s\n" "$*"; }
_ok()    { printf "${_GREEN}[OK]${_NC} %s\n" "$*"; }
_warn()  { printf "${_YELLOW}[WARN]${_NC} %s\n" "$*"; }
_error() { printf "${_RED}[ERROR]${_NC} %s\n" "$*" >&2; }

_ask() {
    printf "${_BLUE}?${_NC} %s " "$1"
    read -r _answer
    echo "$_answer"
}

_ask_yn() {
    printf "${_BLUE}?${_NC} %s [y/N] " "$1"
    read -r _answer
    case "$_answer" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

# ---- Parse flags (non-interactive mode) ----
while [ $# -gt 0 ]; do
    case "$1" in
        --user)       shift; INSTALL_USER="$1"; INSTALL_INTERACTIVE=false ;;
        --product)    shift; INSTALL_PRODUCT="$1"; INSTALL_INTERACTIVE=false ;;
        --path-method) shift; INSTALL_PATH_METHOD="$1"; INSTALL_INTERACTIVE=false ;;
        --cron)       INSTALL_CRON="yes"; INSTALL_INTERACTIVE=false ;;
        --no-cron)    INSTALL_CRON="no"; INSTALL_INTERACTIVE=false ;;
        --help|-h)
            cat << EOF
Usage: install.sh [options]

Interactive mode (default): walks you through each step.
Non-interactive mode: provide all options via flags.

Options:
  --user <name>        Service user (default: auto-detect)
  --product <name>     Product to configure (default: glpi)
  --path-method <m>    'symlink' or 'profile'
  --cron               Auto-install cron jobs
  --no-cron            Skip cron setup
  --help               Show this help
EOF
            exit 0
            ;;
        *) _error "Unknown option: $1"; exit 1 ;;
    esac
    shift
done

# ---- Privilege detection (§24) ----
_SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    _info "Running as $(whoami) — will use sudo when needed"
    _SUDO="sudo"
else
    _info "Running as root"
fi

# ---- Banner ----
printf "\n"
printf "${_BLUE}╔══════════════════════════════════════╗${_NC}\n"
printf "${_BLUE}║   it-tools installer                 ║${_NC}\n"
printf "${_BLUE}║   IT Administration Automation       ║${_NC}\n"
printf "${_BLUE}╚══════════════════════════════════════╝${_NC}\n"
printf "\n"

# ---- Step 1: Dependency checking (§26) ----
_info "Checking dependencies..."
_MISSING=""
for _dep_cmd in curl tar gzip mysql mysqldump systemctl mountpoint; do
    if command -v "$_dep_cmd" >/dev/null 2>&1; then
        _ok "  Found: $_dep_cmd"
    else
        _warn "  Missing: $_dep_cmd"
        _MISSING="$_MISSING $_dep_cmd"
    fi
done

# Check for mail command
_has_mail=false
for _mail_cmd in mail msmtp sendmail; do
    if command -v "$_mail_cmd" >/dev/null 2>&1; then
        _ok "  Found mail: $_mail_cmd"
        _has_mail=true
        break
    fi
done
if [ "$_has_mail" = "false" ]; then
    _warn "  Missing: mail/msmtp/sendmail (email alerts won't work)"
fi

if [ -n "$_MISSING" ]; then
    _warn "Missing packages:$_MISSING"
    # Map commands to apt packages
    _APT_PKGS=""
    for _dep_m in $_MISSING; do
        case "$_dep_m" in
            mysql|mysqldump) _APT_PKGS="$_APT_PKGS mariadb-client" ;;
            curl)            _APT_PKGS="$_APT_PKGS curl" ;;
            gzip)            _APT_PKGS="$_APT_PKGS gzip" ;;
            *)               ;; # systemctl, mountpoint are in base system
        esac
    done
    if [ -n "$_APT_PKGS" ]; then
        _info "Install command: $_SUDO apt install -y$_APT_PKGS"
        if [ "$INSTALL_INTERACTIVE" = "true" ]; then
            if _ask_yn "Install missing packages now?"; then
                $_SUDO apt install -y $_APT_PKGS
            fi
        else
            _error "Missing dependencies in non-interactive mode. Install manually."
            exit 2
        fi
    fi
fi

# ---- Step 2: Detect service user (§20) ----
if [ -z "$INSTALL_USER" ]; then
    if [ "$INSTALL_INTERACTIVE" = "true" ]; then
        _default_user=$(whoami)
        INSTALL_USER=$(_ask "Service user [$_default_user]:")
        INSTALL_USER="${INSTALL_USER:-$_default_user}"
    else
        INSTALL_USER=$(whoami)
    fi
fi
_info "Service user: $INSTALL_USER"

# ---- Step 3: Create install directory (§18) ----
_info "Installing to: $INSTALL_DIR"
if [ ! -d "$INSTALL_DIR" ]; then
    $_SUDO mkdir -p "$INSTALL_DIR"
fi

# Copy files
$_SUDO cp -r "$SCRIPT_DIR/bin" "$INSTALL_DIR/"
$_SUDO cp -r "$SCRIPT_DIR/lib" "$INSTALL_DIR/"
$_SUDO cp -r "$SCRIPT_DIR/products" "$INSTALL_DIR/"
$_SUDO cp -r "$SCRIPT_DIR/cron" "$INSTALL_DIR/"
$_SUDO cp -r "$SCRIPT_DIR/tests" "$INSTALL_DIR/"
$_SUDO mkdir -p "$INSTALL_DIR/logs"

_ok "Files copied to $INSTALL_DIR"

# ---- Step 4: PATH setup (§19) ----
if [ -z "$INSTALL_PATH_METHOD" ] && [ "$INSTALL_INTERACTIVE" = "true" ]; then
    printf "\nHow should the 'it' command be available?\n"
    printf "  1) Symlink in /usr/local/bin (recommended)\n"
    printf "  2) Add to PATH in shell profile\n"
    _choice=$(_ask "Choice [1]:")
    case "$_choice" in
        2) INSTALL_PATH_METHOD="profile" ;;
        *) INSTALL_PATH_METHOD="symlink" ;;
    esac
fi
INSTALL_PATH_METHOD="${INSTALL_PATH_METHOD:-symlink}"

case "$INSTALL_PATH_METHOD" in
    symlink)
        $_SUDO ln -sf "$INSTALL_DIR/bin/it" /usr/local/bin/it
        _ok "Symlink created: /usr/local/bin/it -> $INSTALL_DIR/bin/it"
        ;;
    profile)
        _profile_file=""
        for _pf in "$HOME/.profile" "$HOME/.bashrc" "$HOME/.bash_profile"; do
            if [ -f "$_pf" ]; then
                _profile_file="$_pf"
                break
            fi
        done
        if [ -n "$_profile_file" ]; then
            if ! grep -q "$INSTALL_DIR/bin" "$_profile_file" 2>/dev/null; then
                echo "export PATH=\"\$PATH:$INSTALL_DIR/bin\"" >> "$_profile_file"
                _ok "Added $INSTALL_DIR/bin to PATH in $_profile_file"
            else
                _info "PATH already configured in $_profile_file"
            fi
        fi
        ;;
esac

# ---- Step 5: Config generation (§21) ----
_CONF_DIR="$INSTALL_DIR/products/$INSTALL_PRODUCT"
_CONF_FILE="$_CONF_DIR/${INSTALL_PRODUCT}.conf"
_CONF_EXAMPLE="$_CONF_DIR/${INSTALL_PRODUCT}.conf.example"

if [ ! -f "$_CONF_FILE" ] && [ -f "$_CONF_EXAMPLE" ]; then
    if [ "$INSTALL_INTERACTIVE" = "true" ]; then
        _info "Configuring $INSTALL_PRODUCT..."
        printf "\n"

        _glpi_url=$(_ask "GLPI URL [https://glpi.company.local]:")
        _glpi_url="${_glpi_url:-https://glpi.company.local}"

        _glpi_path=$(_ask "GLPI install path [/var/www/html/glpi]:")
        _glpi_path="${_glpi_path:-/var/www/html/glpi}"

        _db_auto=$(_ask "Auto-detect DB credentials from GLPI config? [y/N]:")
        case "$_db_auto" in
            [yY]*) _db_auto_detect="true" ;;
            *) _db_auto_detect="false" ;;
        esac

        _db_host="localhost"; _db_name="glpi"; _db_user="glpi"; _db_pass=""
        if [ "$_db_auto_detect" = "false" ]; then
            _db_host=$(_ask "DB host [localhost]:")
            _db_host="${_db_host:-localhost}"
            _db_name=$(_ask "DB name [glpi]:")
            _db_name="${_db_name:-glpi}"
            _db_user=$(_ask "DB user [glpi]:")
            _db_user="${_db_user:-glpi}"
            _db_pass=$(_ask "DB password:")
        fi

        _backup_dest=$(_ask "Backup destination (NAS path) [/mnt/nas/backups/glpi]:")
        _backup_dest="${_backup_dest:-/mnt/nas/backups/glpi}"

        _alert_email=$(_ask "Alert email address [admin@company.local]:")
        _alert_email="${_alert_email:-admin@company.local}"

        # Generate config
        $_SUDO sh -c "cat > '$_CONF_FILE'" << CONFEOF
# GLPI Configuration — it-tools
# Generated by install.sh on $(date '+%Y-%m-%d %H:%M:%S')

# -- GLPI Instance --
GLPI_URL="$_glpi_url"
GLPI_INSTALL_PATH="$_glpi_path"

# -- Database --
DB_AUTO_DETECT=$_db_auto_detect
DB_HOST="$_db_host"
DB_NAME="$_db_name"
DB_USER="$_db_user"
DB_PASS="$_db_pass"

# -- Backup --
BACKUP_DEST="$_backup_dest"
BACKUP_RETENTION_DAYS=30
BACKUP_VERIFY=false

# -- Monitoring --
MONITOR_DISK_WARN_PCT=80
MONITOR_DISK_CRIT_PCT=95

# -- Purge thresholds (months, 0 = disabled) --
PURGE_CLOSED_TICKETS_MONTHS=12
PURGE_LOGS_MONTHS=6
PURGE_NOTIFICATIONS_MONTHS=3
PURGE_TRASH_MONTHS=1

# -- Archive --
ARCHIVE_MODE="sqldump"
ARCHIVE_DB_NAME="glpi_archive"
ARCHIVE_MONTHS=12

# -- Safety --
REQUIRE_RECENT_BACKUP=true
BACKUP_MAX_AGE_HOURS=24
BACKUP_KEEP_PARTIAL=true
BACKUP_VERIFY_MOUNT=true

# -- Maintenance mode --
MAINTENANCE_MODE_ENABLED=false

# -- Lock files --
LOCK_TIMEOUT_MINUTES=120

# -- Retries --
RETRY_COUNT=3
RETRY_DELAY_SECONDS=10

# -- Alerts --
ALERT_CHANNELS="email,log"
ALERT_EMAIL_TO="$_alert_email"
ALERT_TEAMS_WEBHOOK=""
ALERT_SLACK_WEBHOOK=""
ALERT_COOLDOWN_MINUTES=60

# -- Logging --
LOG_DIR=""
LOG_LEVEL="info"

# -- Runtime --
RUN_USER="$INSTALL_USER"
CONFEOF
        _ok "Config generated: $_CONF_FILE"
    else
        $_SUDO cp "$_CONF_EXAMPLE" "$_CONF_FILE"
        _info "Config copied from example — edit $_CONF_FILE manually"
    fi
fi

# ---- Step 6: File permissions (§23) ----
_info "Setting permissions..."
$_SUDO chown -R "${INSTALL_USER}:${INSTALL_USER}" "$INSTALL_DIR"
$_SUDO chmod +x "$INSTALL_DIR"/bin/*
$_SUDO find "$INSTALL_DIR/products" -name "*.sh" -exec chmod +x {} \;
$_SUDO find "$INSTALL_DIR/products" -name "*.conf" -exec chmod 600 {} \;
$_SUDO find "$INSTALL_DIR/products" -name "*.conf.example" -exec chmod 644 {} \;
$_SUDO chmod 700 "$INSTALL_DIR/logs"
_ok "Permissions set"

# ---- Step 7: Cron setup (§22) ----
_CRON_EXAMPLE="$INSTALL_DIR/cron/${INSTALL_PRODUCT}.cron.example"
if [ -f "$_CRON_EXAMPLE" ]; then
    if [ -z "$INSTALL_CRON" ] && [ "$INSTALL_INTERACTIVE" = "true" ]; then
        printf "\nCron entries for %s:\n" "$INSTALL_PRODUCT"
        cat "$_CRON_EXAMPLE"
        printf "\n"
        if _ask_yn "Install these cron entries for user $INSTALL_USER?"; then
            INSTALL_CRON="yes"
        else
            INSTALL_CRON="no"
        fi
    fi
    if [ "$INSTALL_CRON" = "yes" ]; then
        _existing=$(crontab -u "$INSTALL_USER" -l 2>/dev/null || true)
        if echo "$_existing" | grep -q "it-tools"; then
            _info "Cron entries already exist, skipping"
        else
            ( echo "$_existing"; echo ""; cat "$_CRON_EXAMPLE" ) | \
                $_SUDO crontab -u "$INSTALL_USER" -
            _ok "Cron entries installed for $INSTALL_USER"
        fi
    else
        _info "Skipped cron setup. Install manually from: $_CRON_EXAMPLE"
    fi
fi

# ---- Step 8: Post-install validation (§25) ----
printf "\n"
_info "Running post-install validation..."

# Source config for validation
if [ -f "$_CONF_FILE" ]; then
    . "$_CONF_FILE"
fi

# Test DB connectivity
if command -v mysqladmin >/dev/null 2>&1 && [ -n "${DB_HOST:-}" ]; then
    if [ "${DB_AUTO_DETECT:-false}" = "true" ]; then
        _ok "  DB: auto-detect mode (will be tested at runtime)"
    elif MYSQL_PWD="${DB_PASS:-}" mysqladmin ping \
        -h "${DB_HOST:-localhost}" -u "${DB_USER:-}" >/dev/null 2>&1; then
        _ok "  DB: MariaDB is reachable"
    else
        _warn "  DB: Cannot connect to MariaDB at ${DB_HOST:-localhost}"
    fi
else
    _warn "  DB: mysqladmin not available or DB_HOST not set"
fi

# Test HTTP
if [ -n "${GLPI_URL:-}" ]; then
    _http_status=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 \
        "${GLPI_URL}" 2>/dev/null || echo "000")
    if [ "$_http_status" -ge 200 ] 2>/dev/null && [ "$_http_status" -lt 400 ] 2>/dev/null; then
        _ok "  HTTP: $GLPI_URL responds (status: $_http_status)"
    else
        _warn "  HTTP: $GLPI_URL returned status $_http_status"
    fi
else
    _warn "  HTTP: GLPI_URL not configured"
fi

# Test NAS mount
if [ -n "${BACKUP_DEST:-}" ]; then
    if mountpoint -q "$BACKUP_DEST" 2>/dev/null; then
        _ok "  NAS: $BACKUP_DEST is mounted"
    else
        _warn "  NAS: $BACKUP_DEST is not a mount point"
    fi
else
    _warn "  NAS: BACKUP_DEST not configured"
fi

# ---- Done ----
printf "\n"
printf "${_GREEN}╔══════════════════════════════════════╗${_NC}\n"
printf "${_GREEN}║   Installation complete!             ║${_NC}\n"
printf "${_GREEN}╚══════════════════════════════════════╝${_NC}\n"
printf "\n"
_info "Install directory: $INSTALL_DIR"
_info "Config file: $_CONF_FILE"
_info "Try: it $INSTALL_PRODUCT list"
printf "\n"
