# Troubleshooting Guide

Errors in it-tools are signaled via exit codes. Each section below covers one exit code with the actual error messages you may see, their causes, and how to fix them.

---

## Exit Code 1 — Configuration

**Message:** `Config file not found: <path>`
- **Cause:** The tool expected `products/glpi/glpi.conf` but it does not exist.
- **Fix:**
  ```sh
  cp products/glpi/glpi.conf.example products/glpi/glpi.conf
  chmod 600 products/glpi/glpi.conf
  # Edit the file with your environment's values
  ```

**Message:** `Required argument missing: BACKUP_DEST`
- **Cause:** `BACKUP_DEST` is empty in your config file. The backup and archive tools require it.
- **Fix:** Set `BACKUP_DEST` in `glpi.conf` to your backup directory path.

**Message:** `Required argument missing: GLPI_INSTALL_PATH`
- **Cause:** `GLPI_INSTALL_PATH` is empty. Should not happen with the default (`/var/www/html/glpi`), but can occur if explicitly set to empty.
- **Fix:** Set `GLPI_INSTALL_PATH` in `glpi.conf` to your GLPI installation path.

**Message:** `Database name not configured`
- **Cause:** `DB_NAME` is empty and `DB_AUTO_DETECT` is not `true`.
- **Fix:** Either set `DB_NAME` in your config, or set `DB_AUTO_DETECT=true` to read credentials from GLPI's `config_db.php`.

**Message:** `GLPI config_db.php not found: <path>`
- **Cause:** `DB_AUTO_DETECT=true` but the GLPI config file does not exist at the expected path.
- **Fix:** Verify `GLPI_INSTALL_PATH` points to a valid GLPI installation that has `config/config_db.php`.

**Message:** `Unknown product: <name>`
- **Cause:** The product name passed to `it` does not match any directory under `products/`.
- **Fix:** Run `it list` to see available products.

**Message:** `Unknown tool: <name> (product: <product>)`
- **Cause:** The tool name does not match any `.sh` file in the product directory.
- **Fix:** Run `it <product> list` to see available tools.

**Message:** `Config file has syntax errors: <path>`
- **Cause:** `glpi.conf` contains a shell syntax error (unclosed quote, invalid assignment).
- **Fix:** Run `sh -n products/glpi/glpi.conf` to see the error, then fix the file.

**Message:** `Unknown ARCHIVE_MODE: <value>`
- **Cause:** `ARCHIVE_MODE` is set to something other than `sqldump` or `archivedb`.
- **Fix:** Set `ARCHIVE_MODE=sqldump` or `ARCHIVE_MODE=archivedb` in `glpi.conf`.

**Message:** `Invalid control: <value> (valid: 01, 02, 04, 05)`
- **Cause:** The `--control` flag was given an unsupported value.
- **Fix:** Use one of: `01`, `02`, `04`, `05`.

**Message:** `Invalid mode: <value> (valid: warranty, hors-support)`
- **Cause:** The `--mode` flag for `asset_status` was given an unsupported value.
- **Fix:** Use `--mode warranty` or `--mode hors-support`.

**Message:** `Required argument missing: GLPI_API_URL`
- **Cause:** The `asset_status` tool requires GLPI API configuration but one or more parameters are empty.
- **Fix:** Set `GLPI_API_URL`, `GLPI_API_APP_TOKEN`, `GLPI_API_USER`, and `GLPI_API_PASS` in `glpi.conf`.

**Message:** `Hors-support file not found: <path>`
- **Cause:** The file specified by `--file` or `HORS_SUPPORT_FILE` does not exist.
- **Fix:** Verify the file path. The file should contain one serial number per line.

**Message:** `No backups found in <path>`
- **Cause:** The restore tool's interactive selection found no `glpi-backup-*` directories in `BACKUP_DEST`.
- **Fix:** Run a backup first: `it glpi backup`

**Message:** `No database dump found in backup` / `No files archive found in backup` / `No webroot archive found in backup`
- **Cause:** The selected backup directory is missing the expected archive file for the requested component.
- **Fix:** Select a different backup or re-run `it glpi backup` to create a complete backup.

---

## Exit Code 2 — Dependency

**Message:** *(from install.sh)* `Missing: <command>`
- **Cause:** A required system command is not installed.
- **Dependencies:** `curl`, `tar`, `gzip`, `mysql`, `mysqldump`, `systemctl`, `mountpoint`, `nslookup`, `pdfinfo`
- **Fix:**
  ```sh
  # Debian/Ubuntu
  sudo apt install -y curl gzip mariadb-client dnsutils

  # For email alerts
  sudo apt install -y msmtp

  # For PDF page count (control 05)
  sudo apt install -y poppler-utils
  ```

---

## Exit Code 3 — Database

**Message:** `Cannot connect to database`
- **Cause:** MariaDB is not running, credentials are wrong, or the host is unreachable.
- **Fix:**
  ```sh
  # Check MariaDB is running
  systemctl status mariadb

  # Test connectivity manually
  mysql -h <DB_HOST> -u <DB_USER> -p <DB_NAME> -e "SELECT 1"

  # If using auto-detect, verify the config file
  cat /var/www/html/glpi/config/config_db.php
  ```

**Message:** `Failed to purge closed tickets` / `Failed to purge event logs` / `Failed to purge notifications` / `Failed to purge trash from <table>`
- **Cause:** A DELETE query failed during purge. Likely a DB permission issue or table lock.
- **Fix:** Verify the DB user has DELETE privileges on the GLPI database.

**Message:** `Failed to export <table> for archiving` / `Failed to delete archived records from <table>`
- **Cause:** A SELECT or DELETE query failed during archive. Could be a permissions issue, table lock, or disk full (for sqldump mode).
- **Fix:** Check DB user privileges and disk space on the archive destination.

---

**Message:** `Missing plugin tables: <list>`
- **Cause:** The report tool requires GLPI plugins (Fields and Generic Object) with specific tables. The tables were not found in the database.
- **Fix:** Install and enable the required GLPI plugins:
  - **Fields plugin** — provides `glpi_plugin_fields_ticketrfrenceticketexternes` and related dropdown tables
  - **Generic Object plugin** — provides `glpi_plugin_genericobject_compteusebillets`

  The report tool will skip gracefully (exit 0) if plugin tables are missing.

**Message:** `GLPI API authentication failed (HTTP <code>): <body>`
- **Cause:** The GLPI REST API rejected the login credentials.
- **Fix:**
  ```sh
  # Test API credentials manually
  curl -s -H "Content-Type: application/json" \
       -H "App-Token: YOUR_APP_TOKEN" \
       -d '{"login":"YOUR_USER","password":"YOUR_PASS"}' \
       https://glpi.company.local/apirest.php/initSession

  # Common issues:
  # - App token not enabled in GLPI (Configuration > API)
  # - API user does not have API access rights
  # - API URL is incorrect (should end with /apirest.php)
  ```

---

## Exit Code 4 — Service

**Message:** `GLPI health check FAILED: <list of checks>`
- **Cause:** One or more monitor checks failed. The message lists which ones (e.g., `DNS, HTTP, Service`).
- **Fix:** Address each failed check individually:

  | Check | Detail message | Fix |
  |-------|---------------|-----|
  | DNS | `Cannot resolve <hostname>` | Check DNS server, verify hostname in `GLPI_URL` |
  | HTTP | `<url> returned status <code>` | Check Apache config, firewall rules, GLPI setup |
  | Service | `apache2 is not running` | `sudo systemctl start apache2` |
  | Service | `mariadb is not running` | `sudo systemctl start mariadb` |
  | MariaDB | `Cannot connect to database` | See Exit Code 3 above |
  | PHP | `php command not found` | Install PHP: `sudo apt install php` |
  | PHP-FPM | `<service> is not running` | `sudo systemctl start php8.2-fpm` (adjust version) |
  | Disk | `CRITICAL: <N>% used (threshold: <M>%)` | Free disk space on the GLPI partition |
  | SSL | `Cannot retrieve certificate from <host>:<port>` | Check that `GLPI_URL` is reachable and serving a valid TLS certificate |
  | SSL | `Certificate EXPIRED (<N> days ago): <host>` | Renew the TLS certificate immediately |
  | SSL | `Certificate expires in <N> days (critical threshold: <M>d): <host>` | Renew the TLS certificate before it expires |

---

## Exit Code 5 — Filesystem

**Message:** `Backup destination is not a mount point: <path>`
- **Cause:** `BACKUP_VERIFY_MOUNT=true` and `BACKUP_DEST` is not a mounted filesystem (e.g., the NAS is not mounted).
- **Fix:**
  ```sh
  # Check if the NAS is mounted
  mountpoint -q /mnt/nas/backups/glpi && echo "mounted" || echo "not mounted"

  # Mount it
  sudo mount /mnt/nas/backups/glpi

  # Or disable mount verification for local directories
  # Set BACKUP_VERIFY_MOUNT=false in glpi.conf
  ```

**Message:** `Backup directory not found: <path>`
- **Cause:** The path given to `--backup` does not exist on disk.
- **Fix:** Check the `--backup` path. Use `ls` to verify the backup directory exists.

**Message:** `No backup archives found in: <path>`
- **Cause:** The backup directory exists but contains no `.sql.gz` or `.tar.gz` files.
- **Fix:** Select a different backup directory that contains the expected archive files.

**Message:** `Files directory not found: <path>` / `GLPI install path not found: <path>`
- **Cause:** The GLPI installation path in the config does not exist on disk.
- **Fix:** Verify `GLPI_INSTALL_PATH` in `glpi.conf` matches the actual install location.

**Message:** `Files directory archive failed` / `Webroot archive failed`
- **Cause:** `tar` failed to create the archive. Common causes: permissions, disk full, or path not accessible.
- **Fix:** Check permissions on the source directory and free space on the backup destination.

---

## Exit Code 6 — Lock

**Message:** `Lock file exists and is not stale: <path>`
- **Cause:** Another instance of the same tool is already running, or a previous run crashed without cleaning up its lock file.
- **Fix:**
  ```sh
  # Check if another instance is actually running
  ps aux | grep "it glpi"

  # If no process is running, the lock is orphaned — remove it
  rm /opt/it-tools/logs/glpi-backup.lock   # or glpi-restore.lock, glpi-purge.lock, glpi-archive.lock, glpi-report.lock, glpi-asset-status.lock

  # Locks auto-expire after LOCK_TIMEOUT_MINUTES (default: 120 min)
  ```

Lock file locations:
- `logs/glpi-backup.lock`
- `logs/glpi-restore.lock`
- `logs/glpi-purge.lock`
- `logs/glpi-archive.lock`
- `logs/glpi-report.lock`
- `logs/glpi-asset-status.lock`

---

## Exit Code 7 — Safety

**Message:** `BACKUP_DEST not configured, cannot verify recent backup`
- **Cause:** The safety gate requires `BACKUP_DEST` to know where to look for backups, but it is empty.
- **Fix:** Set `BACKUP_DEST` in `glpi.conf`.

**Message:** `Backup directory does not exist: <path>`
- **Cause:** The `BACKUP_DEST` directory does not exist on disk.
- **Fix:** Create the directory or mount the NAS:
  ```sh
  sudo mkdir -p /mnt/nas/backups/glpi
  ```

**Message:** `No backup files found in <path>`
- **Cause:** The safety gate found no `*.tar.gz` or `*.sql.gz` files in `BACKUP_DEST`.
- **Fix:** Run a backup first: `it glpi backup`

**Message:** `Backup is marked as partial (incomplete): <path>`
- **Cause:** The restore tool detected a `.partial` flag file in the selected backup directory. Partial backups are not safe to restore from.
- **Fix:** Select a different (complete) backup, or re-run `it glpi backup` to create a new complete backup.

**Message:** `Most recent backup is <N>h old (max: <M>h): <file>`
- **Cause:** The newest backup file is older than `BACKUP_MAX_AGE_HOURS`.
- **Fix:**
  ```sh
  # Run a fresh backup
  it glpi backup

  # Or increase the threshold
  # Set BACKUP_MAX_AGE_HOURS=48 in glpi.conf

  # Or disable the safety gate (not recommended)
  # Set REQUIRE_RECENT_BACKUP=false in glpi.conf
  ```

---

## Exit Code 8 — Partial

**Message:** `GLPI backup completed with errors` / `GLPI restore completed with errors` / `GLPI purge completed with errors` / `GLPI archive completed with errors`
- **Cause:** The operation completed but some steps failed. The specific errors are listed in the alert and log output.
- **Fix:** Review the logged errors (see the alert or stderr output) and address each one individually. Common causes: a single table failed while others succeeded, or a file archive failed but the DB dump succeeded.

---

## Common Issues

### Alerts not being sent

**Symptom:** Operations fail but no email/Slack/Teams notifications arrive.

**Checks:**
1. Verify `ALERT_CHANNELS` includes the desired channel (e.g., `email,log`)
2. For email: verify a working `mail` / `msmtp` / `sendmail` command exists
3. For Teams/Slack: verify the webhook URL is correct and not expired
4. Check `ALERT_COOLDOWN_MINUTES` — alerts are suppressed for repeat issues

```sh
# Test email manually
echo "test" | mail -s "it-tools test" admin@company.local

# Check for cooldown files
ls -la ${LOG_DIR:-/tmp}/.alert_cooldown_*
```

### Alerts suppressed by cooldown

**Symptom:** The first alert arrives but subsequent ones for the same issue do not.

**Cause:** The cooldown mechanism suppresses duplicate alerts (same tool + subject) for `ALERT_COOLDOWN_MINUTES` (default: 60 minutes).

**Fix:**
```sh
# Remove cooldown files to allow immediate re-alerting
rm ${LOG_DIR:-/tmp}/.alert_cooldown_*

# Or reduce the cooldown period in glpi.conf
# ALERT_COOLDOWN_MINUTES=15
```

### Permission errors

**Symptom:** Tools fail to write logs, create lock files, or read the config file.

**Fix:**
```sh
# Re-apply correct permissions
sudo chown -R <RUN_USER>:<RUN_USER> /opt/it-tools
sudo chmod 600 /opt/it-tools/products/glpi/glpi.conf
sudo chmod 700 /opt/it-tools/logs
```

### Cron jobs not running

**Symptom:** Scheduled tasks do not execute.

**Checks:**
1. Verify cron entries exist: `crontab -l`
2. Check cron log: `grep it-tools /var/log/syslog`
3. Verify the `it` command is accessible from cron's PATH:
   ```sh
   # If using symlink method
   ls -la /usr/local/bin/it

   # If using profile method, cron doesn't source profiles — use full path
   # /opt/it-tools/bin/it glpi monitor
   ```
4. Check the cron output log: `tail /opt/it-tools/logs/cron.log`

### Status shows "unavailable" for database fields

**Symptom:** `it glpi status` shows `unavailable` for MariaDB version, DB size, etc.

**Checks:**
1. Verify DB credentials in `glpi.conf` (or set `DB_AUTO_DETECT=true`)
2. Verify MariaDB is running: `systemctl status mariadb`
3. Run with `--verbose` to see debug output

### Check tool reports multiple failures

**Symptom:** `it glpi check` shows several `[FAIL]` lines after initial setup.

**Checks:**
1. Start with `it glpi check --quiet` to see only failures
2. Fix config issues first (exit code 1), then dependency issues (exit code 2)
3. Run `it glpi check --verbose` for debug details on each check

### Dry-run shows no records to purge/archive

**Symptom:** `it glpi purge --dry-run` shows 0 records for all targets.

**Checks:**
1. Verify thresholds are not `0` (disabled): check `PURGE_*_MONTHS` in `glpi.conf`
2. Verify DB credentials are correct: the count queries may be silently failing
3. Run with `--verbose` to see debug output including SQL queries
