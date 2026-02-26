# IT-Tools Design Document

**Date:** 2026-02-25
**Status:** Proposed

## Overview

A POSIX sh-compatible, convention-based CLI toolkit for automating recurring IT
administration tasks. The first product module is GLPI 10.0.5. The framework is
designed to add more product modules later (Dolibarr, GitLab, etc.) using the
same patterns.

## Context

- **User:** IT Administrator at a small business
- **Objective:** Automate recurring administration tasks via shell scripts
- **First product:** GLPI (open-source ITSM) — monitoring, backup, purge, archive
- **Future products:** Dolibarr, GitLab, others (deferred)

## Environment

| Property             | Value                                      |
|----------------------|--------------------------------------------|
| Server OS            | Ubuntu 22.04/24.04 LTS                     |
| GLPI version         | 10.0.5                                     |
| Web stack            | Apache + MariaDB (bare metal / VM)         |
| GLPI install path    | /var/www/html/glpi                         |
| GLPI CLI (bin/console)| Unknown — scripts should detect and use if available |
| GLPI plugins         | FormCreator, Datainjection, others         |
| Run user             | admdev (configurable, detected at install) |
| Shell compatibility  | POSIX sh (no bash-isms)                    |
| Scheduling           | Cron                                       |
| Backup destination   | NFS/NAS mount (path configurable)          |

## Directory Structure

```
it-tools/
├── bin/
│   └── it                          # Unified dispatcher
├── products/
│   └── glpi/
│       ├── glpi.conf.example       # Per-product config template
│       ├── monitor.sh              # Health check (HTTP, services, disk, DNS)
│       ├── backup.sh               # Full backup (DB + files + webroot)
│       ├── purge.sh                # Partial purge (tickets, logs, notifs, trash)
│       └── archive.sh              # Partial archive (export + delete)
├── lib/
│   ├── common.sh                   # Colors, logging, arg parsing, confirm
│   ├── alert.sh                    # Alert dispatching (email, Teams, Slack, log)
│   ├── db.sh                       # DB helpers (credential parsing, dump, query)
│   └── backup_check.sh             # Pre-flight: verify recent backup exists
├── logs/                           # Default log directory (configurable)
├── install.sh                      # Detects user, sets up PATH, creates configs
├── uninstall.sh                    # Clean removal of files, symlinks, cron entries
├── cron/
│   └── glpi.cron.example           # Example crontab entries
├── tests/
│   └── ...                         # Test scripts
└── CLAUDE.md
```

## Design Decisions

### 1. Per-product layout

Each product gets its own directory under `products/<name>/` with its own config
and tool scripts. This maps to the admin workflow: "I manage GLPI, then Dolibarr,
then GitLab." Adding a new product means creating a new directory and config —
the dispatcher discovers products automatically.

### 2. POSIX sh compliance

All scripts use `#!/bin/sh` with `set -eu`. No bash-specific features (no arrays,
no `[[ ]]`, no `${var,,}`). This ensures maximum portability across Ubuntu, Debian,
and any future target environments.

### 3. Per-product config files

Each product has its own config file (`products/glpi/glpi.conf`). Config uses
simple KEY=VALUE format, sourced by the scripts. Credentials are stored here
with `chmod 600` file permissions.

### 4. DB credentials: dual mode

Config can either:
- Specify `DB_USER` / `DB_PASS` / `DB_NAME` / `DB_HOST` directly, or
- Set `DB_AUTO_DETECT=true` to parse GLPI's `config/config_db.php` automatically

Scripts check which mode is configured and act accordingly.

### 5. Safety gate for destructive operations

`purge.sh` and `archive.sh` check for a recent backup (within configurable hours)
before executing. They refuse to proceed without a recent backup. This is
controlled by `REQUIRE_RECENT_BACKUP` and `BACKUP_MAX_AGE_HOURS` in config.

### 6. Dry-run for all destructive operations

All destructive operations (purge, archive) support `--dry-run` flag to preview
what would be affected without making changes. Dry-run output shows record
counts and the SQL queries that would execute.

### 7. Configurable verbosity and logging

Scripts support `--verbose` and `--quiet` flags, with a default log level set in
config (`LOG_LEVEL`). Logs go to `logs/` inside the project directory by default,
configurable via `LOG_DIR`.

### 8. Multi-channel alerting

`lib/alert.sh` dispatches alerts to multiple channels simultaneously:
- **Email** via `mail` / `sendmail` / `msmtp`
- **Microsoft Teams** via incoming webhook
- **Slack** via incoming webhook
- **Log file** (always active as baseline)

Active channels are configured per product via `ALERT_CHANNELS`.

## Error Handling & Recovery

### 9. Continue on partial failure

When a script encounters a failure mid-execution (e.g., mysqldump fails but file
tar can still proceed), the script continues with remaining steps and collects
all errors. At the end, a summary of all failures is reported and an alert is
sent listing everything that went wrong. This applies to all tools.

### 10. Lock files for destructive operations

Backup, purge, and archive scripts create a lock file on start and refuse to run
if one already exists. Monitoring does **not** use lock files (it's safe to run
concurrently).

Lock files auto-expire after a configurable timeout. If the lock is older than
`LOCK_TIMEOUT_MINUTES` (default configurable in config), it is considered stale,
removed, and the script proceeds. Lock files are always cleaned up on normal exit.

### 11. Configurable partial backup behavior

When a backup fails partway (e.g., DB dump succeeded but file tar failed), the
admin can configure whether to keep the partial backup (marked as partial) or
clean it up entirely. Controlled by `BACKUP_KEEP_PARTIAL` in config.

### 12. Retry on failure

All operations support configurable retries. When an operation fails (e.g., curl
timeout, mysqldump connection refused), the script retries up to `RETRY_COUNT`
times with `RETRY_DELAY_SECONDS` between attempts. If all retries are exhausted,
the operation is marked as failed and included in the error summary.

### 13. Alert cooldown (flap suppression)

Monitoring alerts are suppressed after the first alert for a configurable cooldown
period (`ALERT_COOLDOWN_MINUTES`). This prevents flooding the admin's inbox when
a service stays down across multiple check intervals. The cooldown state is tracked
via a state file in the logs directory. No recovery alerts are sent when the
service comes back up.

### 14. Dependency checking at install

`install.sh` verifies all required dependencies are present (curl, mysqldump,
tar, gzip, mail/msmtp, systemctl, etc.) and reports any missing ones. At runtime,
scripts assume dependencies are available. This keeps the tools fast and avoids
redundant checks on every run.

### 15. Detailed exit codes

Scripts use structured exit codes to indicate the type of failure:

| Code | Meaning              |
|------|----------------------|
| 0    | Success              |
| 1    | Configuration error  |
| 2    | Dependency error     |
| 3    | Database error       |
| 4    | Service/network error|
| 5    | Filesystem error     |
| 6    | Lock conflict        |
| 7    | Safety gate blocked  |
| 8    | Partial failure      |

Cron and monitoring integrations can use these codes to distinguish failure types.

### 16. NAS mount verification

Before writing backups or archive exports, scripts verify that the configured
destination path is an active mount point (using `mountpoint -q`). If the path
is a regular directory (not mounted), the script aborts to prevent silently
writing to local disk. Controlled by `BACKUP_VERIFY_MOUNT` in config.

### 17. Optional maintenance mode

Purge and archive operations can optionally put GLPI into maintenance mode before
starting and disable it after completion. This is controlled by
`MAINTENANCE_MODE_ENABLED` in config. When enabled, users see a maintenance page
during the operation.

## Tool Specifications

### monitor.sh — Full Stack Health Check

Checks performed (all configurable):

| Check               | Method                                     |
|----------------------|--------------------------------------------|
| DNS resolution       | Resolve configured hostname                |
| HTTP(S) response     | Check status code + response time via curl |
| Apache service       | `systemctl is-active apache2`              |
| MariaDB service      | `systemctl is-active mariadb` + `mysqladmin ping` |
| PHP availability     | Check PHP-FPM or mod_php is responding     |
| Disk space           | Warn/critical thresholds (configurable %)  |

On failure: sends alerts via configured channels with details of which checks
failed. Designed to run via cron at configurable intervals.

### backup.sh — Full Backup

Steps:
1. MariaDB dump via `mysqldump` (with configurable options)
2. Tar of GLPI files directory (`/var/www/html/glpi/files/`)
3. Tar of full webroot (`/var/www/html/glpi/`)
4. Write output directly to NAS mount path (configurable)
5. Apply retention policy: delete backups older than configurable threshold
6. Optional integrity verification (test SQL dump parsing, verify archive)
7. Send alert on failure

Backup naming: `glpi-backup-YYYY-MM-DD-HHMMSS.tar.gz`

### purge.sh — Partial Purge

Requires recent backup (safety gate). Each purge target is independently
configurable (enable/disable + age threshold in months):

| Target                | DB table(s)                   | Config key                  |
|-----------------------|-------------------------------|-----------------------------|
| Closed tickets        | `glpi_tickets` (status=closed)| `PURGE_CLOSED_TICKETS_MONTHS` |
| Event logs            | `glpi_logs`                   | `PURGE_LOGS_MONTHS`         |
| Notification queue    | `glpi_queuednotifications`    | `PURGE_NOTIFICATIONS_MONTHS`|
| Trashed items         | Various (`is_deleted=1`)      | `PURGE_TRASH_MONTHS`        |

Setting a threshold to `0` disables that purge target.

`--dry-run` shows counts of records that would be deleted per target.

### archive.sh — Partial Archive

Requires recent backup (safety gate). Two configurable modes:

- **`sqldump`**: Export matching records to a SQL dump file, verify export, then
  delete from live DB.
- **`archivedb`**: Insert matching records into a separate archive database
  (`ARCHIVE_DB_NAME`), verify insertion, then delete from live DB.

Age threshold is configurable in months (1-24+), set per data type.

`--dry-run` shows counts and what would be archived.

## Config File Reference

```sh
# ============================================================
# GLPI Configuration — it-tools
# ============================================================

# -- GLPI Instance --
GLPI_URL="https://glpi.company.local"
GLPI_INSTALL_PATH="/var/www/html/glpi"

# -- Database --
# Set DB_AUTO_DETECT=true to read credentials from GLPI's config_db.php
DB_AUTO_DETECT=false
DB_HOST="localhost"
DB_NAME="glpi"
DB_USER="glpi"
DB_PASS="changeme"

# -- Backup --
BACKUP_DEST="/mnt/nas/backups/glpi"
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
ARCHIVE_MODE="sqldump"            # sqldump | archivedb
ARCHIVE_DB_NAME="glpi_archive"    # only used if ARCHIVE_MODE=archivedb
ARCHIVE_MONTHS=12

# -- Safety --
REQUIRE_RECENT_BACKUP=true
BACKUP_MAX_AGE_HOURS=24
BACKUP_KEEP_PARTIAL=true           # keep partial backups on failure
BACKUP_VERIFY_MOUNT=true           # verify NAS mount before writing

# -- Maintenance mode --
MAINTENANCE_MODE_ENABLED=false     # put GLPI in maintenance during purge/archive

# -- Lock files --
LOCK_TIMEOUT_MINUTES=120           # stale lock auto-expiry

# -- Retries --
RETRY_COUNT=3
RETRY_DELAY_SECONDS=10

# -- Alerts --
# Comma-separated list: email,teams,slack,log
ALERT_CHANNELS="email,log"
ALERT_EMAIL_TO="admin@company.local"
ALERT_TEAMS_WEBHOOK=""
ALERT_SLACK_WEBHOOK=""
ALERT_COOLDOWN_MINUTES=60          # suppress repeat alerts for this duration

# -- Logging --
LOG_DIR=""                         # empty = default (project logs/ dir)
LOG_LEVEL="info"                   # debug | info | warn | error

# -- Runtime --
RUN_USER="admdev"
```

## Invocation

```sh
# Via unified dispatcher
it glpi monitor
it glpi backup
it glpi purge --dry-run
it glpi purge
it glpi archive --months 18 --dry-run
it glpi archive

# Direct standalone execution
./products/glpi/monitor.sh
./products/glpi/backup.sh
./products/glpi/purge.sh --dry-run
./products/glpi/archive.sh
```

## Cron Examples

```cron
# GLPI monitoring — every 5 minutes
*/5 * * * * /opt/it-tools/bin/it glpi monitor

# GLPI backup — daily at 02:00
0 2 * * * /opt/it-tools/bin/it glpi backup

# GLPI purge — weekly on Sunday at 03:00
0 3 * * 0 /opt/it-tools/bin/it glpi purge

# GLPI archive — monthly on 1st at 04:00
0 4 1 * * /opt/it-tools/bin/it glpi archive
```

## Installation Specification

### 18. Install path

it-tools installs to `/opt/it-tools`. This is hardcoded as the default; the
directory is created during install.

### 19. PATH setup: user choice

The installer offers two methods for making the `it` command available:
- **Symlink** — create `/usr/local/bin/it` pointing to `/opt/it-tools/bin/it`
- **PATH append** — add `/opt/it-tools/bin` to the service user's shell profile

The user chooses during interactive install. In non-interactive mode, the method
is specified via flags.

### 20. Dual install mode (interactive + non-interactive)

- **Interactive (default):** When run without arguments, install.sh walks the
  user through each step with prompts (service user, product selection, config
  values, PATH method, cron setup, package installation).
- **Non-interactive:** When flags are provided (e.g.,
  `install.sh --user admdev --product glpi --path-method symlink`), the installer
  runs silently using the provided values. Useful for scripted/automated deploys.

### 21. Config generation

During interactive install, the installer asks for each config setting (DB host,
DB user, GLPI URL, backup destination, etc.) and generates a filled-in config
file (`products/glpi/glpi.conf`). The `.example` file remains alongside it as
a reference. In non-interactive mode, it copies the example and the user edits
manually.

### 22. Cron setup: user choice

The installer offers to install cron entries into the service user's crontab.
The user can accept (auto-install), decline (print the entries for manual setup),
or review and edit before installing. Generated crontab entries reference the
full path `/opt/it-tools/bin/it`.

### 23. Automatic file permissions

install.sh automatically sets:
- `chmod 600` on all config files (containing credentials)
- `chmod 700` on the config directory
- `chown <service_user>:<service_user>` on the entire `/opt/it-tools` tree
- `chmod +x` on all scripts in `bin/` and `products/`

### 24. Privilege auto-detection

install.sh detects whether it is running as root or a regular user:
- **As root:** performs all operations directly.
- **As regular user:** performs what it can, and uses `sudo` only for operations
  that require it (creating `/opt/it-tools`, symlinks in `/usr/local/bin`,
  setting ownership). Prompts for sudo when needed.

### 25. Post-install validation

After installation completes, install.sh runs a validation pass:
- Test DB connectivity (attempt `mysqladmin ping` or a test query)
- Test HTTP response from the configured GLPI URL
- Verify NAS backup destination is mounted (`mountpoint -q`)
- Report pass/fail for each check

This runs automatically — it is not optional. Failures are warnings (install
still succeeds), not blockers.

### 26. Dependency checking with user prompt

install.sh checks for all required OS packages:
`curl`, `tar`, `gzip`, `mysqldump` (mariadb-client), `mail`/`msmtp`,
`systemctl`, `mountpoint`, `php` (for GLPI CLI detection).

If packages are missing, the installer:
1. Lists the missing packages and the `apt install` command
2. Asks the user whether to install them automatically or skip

In non-interactive mode, missing packages are listed and the script exits with
an error.

### 27. Uninstall via separate script

`uninstall.sh` cleanly removes:
- The `/opt/it-tools` directory (after confirmation)
- The `/usr/local/bin/it` symlink (if it exists)
- PATH entries added to shell profiles
- Cron entries installed by install.sh

Config files and logs can optionally be preserved (uninstall.sh asks, or
`--keep-config` / `--purge` flags in non-interactive mode).

### 28. Adding new products: manual process

New product modules are added manually by copying an existing product directory
structure and adapting it. No automated scaffolding command is provided. The
design doc and existing product directories serve as the template.

## Future Products (Deferred)

The same `products/` pattern will be used for:
- Dolibarr
- GitLab
- Other products as needed

Each product gets its own directory, config, and tool scripts. Shared libraries
in `lib/` are reusable across products.
