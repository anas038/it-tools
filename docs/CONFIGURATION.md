# Configuration Reference

All configuration is done through a single file at `products/glpi/glpi.conf`. Copy the example to get started:

```sh
cp products/glpi/glpi.conf.example products/glpi/glpi.conf
chmod 600 products/glpi/glpi.conf
```

Default values below are the script fallbacks (what applies when a parameter is not set in the config file).

---

## GLPI Instance

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `GLPI_URL` | string | *(empty)* | Full URL of the GLPI web interface (e.g., `https://glpi.company.local`). Used by the monitor tool for DNS and HTTP checks. If empty, those checks are skipped. |
| `GLPI_INSTALL_PATH` | path | `/var/www/html/glpi` | Filesystem path to the GLPI installation. Used for backups, disk checks, and maintenance mode. |

## Database

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `DB_AUTO_DETECT` | boolean | `false` | When `true`, reads database credentials from GLPI's `config_db.php` instead of using the parameters below. |
| `DB_HOST` | string | `localhost` | MariaDB/MySQL host. |
| `DB_NAME` | string | *(empty)* | Database name. Required unless `DB_AUTO_DETECT=true`. |
| `DB_USER` | string | *(empty)* | Database user. |
| `DB_PASS` | string | *(empty)* | Database password. The config file should be `chmod 600`. |

When `DB_AUTO_DETECT=true`, credentials are parsed from `$GLPI_INSTALL_PATH/config/config_db.php`. The four `DB_*` parameters above are ignored in that case.

## Backup

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `BACKUP_DEST` | path | *(empty)* | Destination directory for backups and archives. Required for `backup` and `archive` tools. Typically a NAS mount point. |
| `BACKUP_RETENTION_DAYS` | integer | `30` | Backup directories older than this many days are removed after a successful backup. |
| `BACKUP_VERIFY` | boolean | `false` | When `true`, runs integrity checks on archives (`tar -tzf`) and SQL dumps (`gzip -t`) after backup completes. |
| `BACKUP_KEEP_PARTIAL` | boolean | `true` | When `true`, keeps partial backups (marked with a `.partial` flag file). When `false`, partial backups are deleted. |
| `BACKUP_VERIFY_MOUNT` | boolean | `true` | When `true`, verifies `BACKUP_DEST` is a mount point before writing. Set to `false` if backing up to a local directory. |

## Monitoring

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `MONITOR_DISK_WARN_PCT` | integer | `80` | Disk usage percentage that triggers a warning log. |
| `MONITOR_DISK_CRIT_PCT` | integer | `95` | Disk usage percentage that triggers a critical failure and alert. |

## Purge

All purge thresholds are in months. A value of `0` disables that purge target.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `PURGE_CLOSED_TICKETS_MONTHS` | integer | `0` | Purge closed tickets (status=6) older than this many months. |
| `PURGE_LOGS_MONTHS` | integer | `0` | Purge entries from `glpi_logs` older than this many months. |
| `PURGE_NOTIFICATIONS_MONTHS` | integer | `0` | Purge entries from `glpi_queuednotifications` older than this many months. |
| `PURGE_TRASH_MONTHS` | integer | `0` | Purge soft-deleted items (`is_deleted=1`) from asset tables older than this many months. |

Tables affected by trash purge: `glpi_tickets`, `glpi_computers`, `glpi_monitors`, `glpi_printers`, `glpi_phones`, `glpi_peripherals`, `glpi_networkequipments`, `glpi_softwarelicenses`.

## Archive

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `ARCHIVE_MODE` | string | `sqldump` | Archive strategy. `sqldump` exports records to compressed SQL files, then deletes from live DB. `archivedb` moves records to a separate archive database. |
| `ARCHIVE_DB_NAME` | string | `glpi_archive` | Target database for `archivedb` mode. Ignored when `ARCHIVE_MODE=sqldump`. |
| `ARCHIVE_MONTHS` | integer | `12` | Archive records older than this many months. Can be overridden at runtime with `--months N`. |

Archived tables: `glpi_tickets` (closed, status=6), `glpi_logs`, `glpi_queuednotifications`.

## Reports

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `REPORT_OUTPUT_DIR` | path | `/tmp` | Directory where CSV and HTML report files are saved. |
| `REPORT_CONTROLS` | string | `01,02,04,05` | Comma-separated list of controls to run. Valid values: `01`, `02`, `04`, `05`. |
| `REPORT_CATEGORIES` | string | `Intervention Préventive,Intervention Curative` | Comma-separated list of GLPI ticket categories to include in reports. |
| `REPORT_SIGNATURE` | string | `Équipe Technique` | Signature text displayed at the bottom of HTML reports. |
| `REPORT_FROM_NAME` | string | `it-tools` | Sender name used in alert subjects. |
| `REPORT_MIN_PDF_PAGES` | integer | `2` | Minimum number of PDF pages to flag in control 05. |

## GLPI Ticket URL

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `GLPI_TICKET_URL` | string | *(empty)* | Base URL for ticket links in HTML reports (e.g., `https://glpi.company.local/front/ticket.form.php?id=`). The ticket ID is appended to this URL. If empty, ticket IDs are still displayed but not clickable. |

## GLPI API

Used by the `asset_status` tool to update asset records via the GLPI REST API.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `GLPI_API_URL` | string | *(empty)* | Base URL of the GLPI REST API (e.g., `https://glpi.company.local/apirest.php`). Required for `asset_status`. |
| `GLPI_API_APP_TOKEN` | string | *(empty)* | Permanent application token generated in GLPI (Configuration > API). Required for `asset_status`. |
| `GLPI_API_USER` | string | *(empty)* | Username for GLPI API authentication. Required for `asset_status`. |
| `GLPI_API_PASS` | string | *(empty)* | Password for GLPI API authentication. The config file should be `chmod 600`. Required for `asset_status`. |

## Asset Status

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `HORS_SUPPORT_FILE` | path | *(empty)* | Default file path containing serial numbers for hors-support mode (one per line). Can be overridden at runtime with `--file`. |

## Safety

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `REQUIRE_RECENT_BACKUP` | boolean | `true` | When `true`, purge and archive tools verify a recent backup exists before proceeding. |
| `BACKUP_MAX_AGE_HOURS` | integer | `24` | Maximum age (in hours) of the most recent backup for the safety gate to pass. |

The safety gate looks for `*.tar.gz` and `*.sql.gz` files in `BACKUP_DEST` and checks the modification time of the newest one.

## Maintenance Mode

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `MAINTENANCE_MODE_ENABLED` | boolean | `false` | When `true`, purge and archive tools create a maintenance mode flag file in GLPI before running, and remove it after. |

The flag file is created at `$GLPI_INSTALL_PATH/files/_cache/maintenance_mode`.

## Lock Files

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `LOCK_TIMEOUT_MINUTES` | integer | `120` | Lock files older than this many minutes are considered stale and automatically removed. |

Lock file locations:
- Backup: `$PROJECT_ROOT/logs/glpi-backup.lock`
- Purge: `$PROJECT_ROOT/logs/glpi-purge.lock`
- Archive: `$PROJECT_ROOT/logs/glpi-archive.lock`
- Report: `$PROJECT_ROOT/logs/glpi-report.lock`
- Asset Status: `$PROJECT_ROOT/logs/glpi-asset-status.lock`

The monitor tool does not use a lock file.

## Retries

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `RETRY_COUNT` | integer | `3` | Number of attempts for retryable operations (DNS lookups, HTTP checks, DB connections, mysqldump). |
| `RETRY_DELAY_SECONDS` | integer | `10` | Seconds to wait between retry attempts. |

## Alerts

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `ALERT_CHANNELS` | string | `log` | Comma-separated list of alert channels. Supported: `log`, `email`, `teams`, `slack`. |
| `ALERT_EMAIL_TO` | string | *(empty)* | Email recipient for alerts. Requires a working `mail` command. |
| `ALERT_TEAMS_WEBHOOK` | string | *(empty)* | Microsoft Teams incoming webhook URL. |
| `ALERT_SLACK_WEBHOOK` | string | *(empty)* | Slack incoming webhook URL. |
| `ALERT_COOLDOWN_MINUTES` | integer | `60` | Suppress duplicate alerts (same tool + subject) for this many minutes. |

Cooldown state files are stored in `$LOG_DIR` (or `/tmp` if `LOG_DIR` is empty) as `.alert_cooldown_<hash>`.

## Logging

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `LOG_DIR` | path | *(empty)* | Directory for log files. When empty, logs go to stderr only. When set, logs are also written to `$LOG_DIR/it-tools.log` and alerts to `$LOG_DIR/alerts.log`. |
| `LOG_LEVEL` | string | `info` | Minimum log level. One of: `debug`, `info`, `warn`, `error`. Overridden by `--verbose` (sets `debug`) or `--quiet` (sets `error`). |

## Runtime

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `RUN_USER` | string | *(none)* | Informational: the OS user that runs it-tools. Set during installation. Not enforced by the scripts. |
