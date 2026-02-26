# Usage Guide

## CLI Structure

```
it <product> <tool> [options]
```

The `it` command auto-discovers products and tools at runtime. No registration is needed — drop a script in `products/<name>/` and it appears automatically.

### Discovery Commands

```sh
it list                # List available products
it glpi list           # List tools for GLPI
it help                # Show global help
it version             # Show version
```

### Common Flags

Every tool supports these flags:

| Flag | Effect |
|------|--------|
| `--dry-run` | Preview changes without executing. Destructive tools (backup, purge, archive) show what would happen. |
| `--verbose` | Enable debug-level logging. Sets `LOG_LEVEL=debug`. |
| `--quiet` | Suppress all output except errors. Sets `LOG_LEVEL=error`. |
| `--help` | Show tool-specific help text. |

## Exit Codes

All tools use the same exit code scheme:

| Code | Name | Meaning |
|------|------|---------|
| 0 | OK | Completed successfully |
| 1 | Config | Missing or invalid configuration |
| 2 | Dependency | Required external command not found |
| 3 | Database | Database connection or query failure |
| 4 | Service | Service check failed (used by monitor) |
| 5 | Filesystem | File or directory operation failed |
| 6 | Lock | Another instance is already running |
| 7 | Safety | Safety gate blocked the operation (no recent backup) |
| 8 | Partial | Completed with some errors (partial success) |

---

## Tools

### monitor

Full stack health check for GLPI. Does not require a lock file and does not modify any data.

```sh
it glpi monitor
it glpi monitor --verbose
```

**Checks performed (in order):**

1. **DNS** — Resolves the hostname from `GLPI_URL` via `nslookup`
2. **HTTP** — Sends a GET request to `GLPI_URL`, expects status 2xx/3xx
3. **Apache** — Verifies `apache2` service is active via `systemctl`
4. **MariaDB service** — Verifies `mariadb` service is active via `systemctl`
5. **MariaDB connectivity** — Pings the database with `mysqladmin` (if DB credentials are available)
6. **PHP** — Checks `php` command exists and detects PHP-FPM service
7. **Disk** — Checks disk usage on the `GLPI_INSTALL_PATH` partition against warning/critical thresholds

**Behavior:**
- Checks that fail are collected (not immediate abort) so all issues are reported at once
- If any check fails, an alert is sent and the tool exits with code 4 (Service)
- If `GLPI_URL` is empty, DNS and HTTP checks are skipped with a warning
- If DB credentials are not available, the connectivity check is skipped

**Relevant config:**

| Parameter | Purpose |
|-----------|---------|
| `GLPI_URL` | Target for DNS and HTTP checks |
| `GLPI_INSTALL_PATH` | Target for disk usage check |
| `MONITOR_DISK_WARN_PCT` | Disk warning threshold (default: 80%) |
| `MONITOR_DISK_CRIT_PCT` | Disk critical threshold (default: 95%) |
| `DB_*` / `DB_AUTO_DETECT` | Database credentials for connectivity check |
| `ALERT_*` | Alert channels and cooldown |
| `RETRY_COUNT` / `RETRY_DELAY_SECONDS` | Retries for DNS, HTTP, and DB checks |

**Example cron (every 5 minutes):**

```cron
*/5 * * * * /opt/it-tools/bin/it glpi monitor >> /opt/it-tools/logs/cron.log 2>&1
```

---

### backup

Full backup of GLPI: database dump, files directory, and webroot. Uses a lock file to prevent concurrent runs.

```sh
it glpi backup
it glpi backup --dry-run
it glpi backup --verbose
```

**Steps performed (in order):**

1. Verify `BACKUP_DEST` is a mount point (if `BACKUP_VERIFY_MOUNT=true`)
2. Acquire lock (`logs/glpi-backup.lock`)
3. **Database dump** — `mysqldump --single-transaction --quick`, then gzip
4. **Files archive** — `tar -czf` of `$GLPI_INSTALL_PATH/files/`
5. **Webroot archive** — `tar -czf` of `$GLPI_INSTALL_PATH` (excluding `files/`)
6. Handle partial failures (keep or discard based on `BACKUP_KEEP_PARTIAL`)
7. **Integrity verification** (if `BACKUP_VERIFY=true`) — tests all `.tar.gz` and `.sql.gz` files
8. **Retention policy** — removes backup directories older than `BACKUP_RETENTION_DAYS`
9. Release lock

**Output structure:**

```
$BACKUP_DEST/
  glpi-backup-2026-02-26-020000/
    glpi-db-2026-02-26-020000.sql.gz
    glpi-files-2026-02-26-020000.tar.gz
    glpi-webroot-2026-02-26-020000.tar.gz
    .partial                              # only if backup was incomplete
```

**Behavior:**
- If a step fails, the error is collected and the backup continues with remaining steps
- A partial backup is marked with a `.partial` flag file (unless `BACKUP_KEEP_PARTIAL=false`)
- Exits with code 8 (Partial) if any step failed, code 0 on full success

**Relevant config:**

| Parameter | Purpose |
|-----------|---------|
| `BACKUP_DEST` | Destination directory (required) |
| `GLPI_INSTALL_PATH` | Source for files and webroot archives (required) |
| `BACKUP_RETENTION_DAYS` | Auto-delete old backups (default: 30) |
| `BACKUP_VERIFY` | Run integrity checks after backup (default: false) |
| `BACKUP_KEEP_PARTIAL` | Keep incomplete backups (default: true) |
| `BACKUP_VERIFY_MOUNT` | Verify NAS mount before writing (default: true) |
| `DB_*` / `DB_AUTO_DETECT` | Database credentials |
| `LOCK_TIMEOUT_MINUTES` | Stale lock auto-expiry (default: 120) |

**Example cron (daily at 02:00):**

```cron
0 2 * * * /opt/it-tools/bin/it glpi backup >> /opt/it-tools/logs/cron.log 2>&1
```

---

### purge

Permanently deletes old data from GLPI tables. Requires a recent backup (safety gate). Uses a lock file and optional maintenance mode.

```sh
it glpi purge --dry-run      # always preview first
it glpi purge
it glpi purge --verbose
```

**Purge targets:**

| Target | Table | Filter | Threshold |
|--------|-------|--------|-----------|
| Closed tickets | `glpi_tickets` | `status = 6 AND date_mod < cutoff` | `PURGE_CLOSED_TICKETS_MONTHS` |
| Event logs | `glpi_logs` | `date_mod < cutoff` | `PURGE_LOGS_MONTHS` |
| Notifications | `glpi_queuednotifications` | `create_time < cutoff` | `PURGE_NOTIFICATIONS_MONTHS` |
| Trashed items | 8 asset tables | `is_deleted = 1 AND date_mod < cutoff` | `PURGE_TRASH_MONTHS` |

Trash-purge tables: `glpi_tickets`, `glpi_computers`, `glpi_monitors`, `glpi_printers`, `glpi_phones`, `glpi_peripherals`, `glpi_networkequipments`, `glpi_softwarelicenses`.

**Steps performed (in order):**

1. Safety gate — verify a recent backup exists in `BACKUP_DEST`
2. Acquire lock (`logs/glpi-purge.lock`)
3. Load DB credentials
4. Enable maintenance mode (if `MAINTENANCE_MODE_ENABLED=true`)
5. Run each purge target (skipped if threshold is `0`)
6. Disable maintenance mode
7. Release lock

**Behavior:**
- All thresholds default to `0` (disabled). You must explicitly configure which targets to purge.
- Failed deletes are collected as errors; purge continues with remaining targets.
- Exits with code 8 (Partial) if any delete failed, code 0 on full success.

**Relevant config:**

| Parameter | Purpose |
|-----------|---------|
| `PURGE_CLOSED_TICKETS_MONTHS` | Threshold for ticket purge (default: 0/disabled) |
| `PURGE_LOGS_MONTHS` | Threshold for log purge (default: 0/disabled) |
| `PURGE_NOTIFICATIONS_MONTHS` | Threshold for notification purge (default: 0/disabled) |
| `PURGE_TRASH_MONTHS` | Threshold for trash purge (default: 0/disabled) |
| `REQUIRE_RECENT_BACKUP` | Enable safety gate (default: true) |
| `BACKUP_MAX_AGE_HOURS` | Max backup age for safety gate (default: 24) |
| `BACKUP_DEST` | Where to look for backups (required for safety gate) |
| `MAINTENANCE_MODE_ENABLED` | Put GLPI in maintenance during purge (default: false) |

**Example cron (weekly on Sunday at 03:00):**

```cron
0 3 * * 0 /opt/it-tools/bin/it glpi purge >> /opt/it-tools/logs/cron.log 2>&1
```

---

### archive

Exports old data from GLPI, then deletes the exported records from the live database. Requires a recent backup (safety gate). Uses a lock file and optional maintenance mode.

```sh
it glpi archive --dry-run
it glpi archive
it glpi archive --months 6       # override threshold
it glpi archive --verbose
```

**Archive modes:**

| Mode | How it works |
|------|--------------|
| `sqldump` (default) | Exports matching rows to compressed SQL files in `$BACKUP_DEST/glpi-archive-<timestamp>/`, then deletes from live DB. |
| `archivedb` | Inserts matching rows into `$ARCHIVE_DB_NAME` (same table names), verifies row count, then deletes from live DB. |

**Archived tables:**

| Data | Table | Filter |
|------|-------|--------|
| Closed tickets | `glpi_tickets` | `status = 6 AND date_mod < cutoff` |
| Event logs | `glpi_logs` | `date_mod < cutoff` |
| Notifications | `glpi_queuednotifications` | `create_time < cutoff` |

**Steps performed (in order):**

1. Safety gate — verify a recent backup exists
2. Acquire lock (`logs/glpi-archive.lock`)
3. Load DB credentials
4. Enable maintenance mode (if `MAINTENANCE_MODE_ENABLED=true`)
5. Archive each table (export, verify, delete from live DB)
6. Disable maintenance mode
7. Release lock

**Behavior:**
- In `sqldump` mode, the export file is verified to be non-empty before deleting from the live DB
- In `archivedb` mode, the row count in the archive DB is verified against the expected count before deleting
- The `--months` flag overrides `ARCHIVE_MONTHS` for that run
- Exits with code 8 (Partial) if any table failed, code 0 on full success

**Relevant config:**

| Parameter | Purpose |
|-----------|---------|
| `ARCHIVE_MODE` | `sqldump` or `archivedb` (default: sqldump) |
| `ARCHIVE_DB_NAME` | Target database for `archivedb` mode (default: glpi_archive) |
| `ARCHIVE_MONTHS` | Archive records older than this (default: 12) |
| `REQUIRE_RECENT_BACKUP` | Enable safety gate (default: true) |
| `BACKUP_MAX_AGE_HOURS` | Max backup age for safety gate (default: 24) |
| `BACKUP_DEST` | Where to store archive dumps / check for backups |
| `MAINTENANCE_MODE_ENABLED` | Put GLPI in maintenance during archive (default: false) |

**Example cron (monthly on the 1st at 04:00):**

```cron
0 4 1 * * /opt/it-tools/bin/it glpi archive >> /opt/it-tools/logs/cron.log 2>&1
```

---

### report

Generates ticket quality control reports for GLPI. Checks resolved tickets for missing data fields and produces CSV + HTML reports. Uses a lock file. Does not modify any data.

```sh
it glpi report
it glpi report --control 01
it glpi report --dry-run
it glpi report --verbose
```

**Controls available:**

| Control | Description | What it checks |
|---------|-------------|----------------|
| 01 | Missing SN / report number | Serial number or report number is empty, and report is not a "Fermeture" |
| 02 | Missing "Pannes" field | The pannefielddropdowns_id field is NULL, empty, or 0 |
| 04 | No attachments | No documents attached (ticket, solution, or followup) |
| 05 | PDF page count | PDF attachments with at least N pages (configurable) |

**Steps performed (in order):**

1. Acquire lock (`logs/glpi-report.lock`)
2. Load DB credentials
3. Verify plugin tables exist (skip gracefully if missing)
4. For each enabled control (or just the one specified via `--control`):
   a. Execute SQL query via `db_query`
   b. For control 05: post-process with `pdfinfo` page count check
   c. Generate CSV file with results
   d. Generate HTML file with technician-grouped table
5. Send summary alert via `send_alert`
6. Release lock

**Behavior:**
- Controls are configured via `REPORT_CONTROLS` (comma-separated, default: `01,02,04,05`)
- Use `--control N` to run a single control
- If plugin tables are missing, reports are skipped with a warning (not an error)
- Empty results are skipped (no file generated)
- Reports are saved to `REPORT_OUTPUT_DIR` as `glpi-control-{N}-{YYYYMMDD}.csv` and `.html`
- HTML reports include clickable ticket IDs linking to `GLPI_TICKET_URL`
- French user-facing output (email reports), English logs

**Relevant config:**

| Parameter | Purpose |
|-----------|---------|
| `REPORT_OUTPUT_DIR` | Where to save CSV/HTML files (default: `/tmp`) |
| `REPORT_CONTROLS` | Which controls to run (default: `01,02,04,05`) |
| `REPORT_CATEGORIES` | GLPI ticket categories to check (default: `Intervention Préventive,Intervention Curative`) |
| `REPORT_SIGNATURE` | Signature at bottom of HTML report (default: `Équipe Technique`) |
| `REPORT_MIN_PDF_PAGES` | Minimum PDF pages for control 05 (default: `2`) |
| `GLPI_TICKET_URL` | Base URL for ticket links in HTML reports |
| `DB_*` / `DB_AUTO_DETECT` | Database credentials |
| `ALERT_*` | Alert channels and cooldown |

**Example cron (weekdays at 07:00):**

```cron
0 7 * * 1-5 /opt/it-tools/bin/it glpi report >> /opt/it-tools/logs/cron.log 2>&1
```

---

### asset_status

Updates asset warranty and support status via the GLPI REST API. Supports two modes: automatic warranty computation and manual hors-support designation. Uses a lock file.

```sh
it glpi asset_status --mode warranty
it glpi asset_status --mode warranty --dry-run
it glpi asset_status --mode hors-support --file /path/to/serials.txt
it glpi asset_status --mode hors-support --dry-run
```

**Modes:**

| Mode | How it works |
|------|--------------|
| `warranty` | Queries all machines from DB, computes warranty expiry from `warranty_date + warranty_duration`, updates status to Garantie (1) or Maintenance (2) via API. Machines already set to Hors Support (3) are skipped. |
| `hors-support` | Reads serial numbers from a file (one per line), looks up GLPI ID via DB, sets status to Hors Support (3) via API. |

**Steps performed (in order):**

1. Acquire lock (`logs/glpi-asset-status.lock`)
2. Initialize GLPI API session (`initSession`)
3. **warranty mode**: Query machines via `db_query`, compute warranty expiry, compare to today, PUT status update via API
4. **hors-support mode**: Read serial numbers from file, look up GLPI ID via `db_query`, PUT status=3 via API
5. Kill GLPI API session (`killSession`)
6. Send alert if errors occurred
7. Release lock

**Behavior:**
- Requires GLPI API credentials (`GLPI_API_URL`, `GLPI_API_APP_TOKEN`, `GLPI_API_USER`, `GLPI_API_PASS`)
- API session is automatically cleaned up on exit (including on interrupt)
- Machines with status Hors Support (3) are ignored in warranty mode
- Machines with incomplete warranty info (no date or zero duration) are skipped
- Failed API calls are collected as errors; processing continues with remaining machines

**Relevant config:**

| Parameter | Purpose |
|-----------|---------|
| `GLPI_API_URL` | GLPI REST API base URL (required) |
| `GLPI_API_APP_TOKEN` | Permanent application token (required) |
| `GLPI_API_USER` | API login username (required) |
| `GLPI_API_PASS` | API login password (required) |
| `HORS_SUPPORT_FILE` | Default file for hors-support serial numbers (overridden by `--file`) |
| `DB_*` / `DB_AUTO_DETECT` | Database credentials |
| `ALERT_*` | Alert channels and cooldown |

**Example cron (Monday at 06:00):**

```cron
0 6 * * 1 /opt/it-tools/bin/it glpi asset_status --mode warranty >> /opt/it-tools/logs/cron.log 2>&1
```
