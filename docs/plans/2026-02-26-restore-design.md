# Design: GLPI Restore Tool

## Overview

A restore tool (`it glpi restore`) that reverses the backup process, restoring GLPI from a backup image (DB dump + files archive + webroot archive).

## User Decisions

- Selective restore via `--db`, `--files`, `--webroot` flags (or all if none specified)
- Interactive backup selection (numbered list) or `--backup <path>` for scripted use
- Always enable maintenance mode during restore
- Interactive confirmation required before overwriting live system
- Stop Apache/PHP-FPM during file restore; MariaDB stays running for DB import

## CLI Interface

```
it glpi restore [--backup <path>] [--db] [--files] [--webroot] [--dry-run] [--verbose] [--quiet]
```

- No component flags → restore all 3 (DB + files + webroot)
- `--db` → restore database only
- `--files` → restore files/ directory only
- `--webroot` → restore webroot only (excluding files/)
- Flags are combinable: `--db --files` restores both but not webroot
- `--backup <path>` → direct path to backup directory (non-interactive)
- No `--backup` → show numbered list of available backups, user picks

## Restore Steps

1. Acquire lock (`logs/glpi-restore.lock`)
2. Select backup — interactive list or `--backup` path
3. Validate: check backup directory has expected files, reject `.partial` backups
4. Show summary of what will be restored, ask for `yes` confirmation
5. Enable maintenance mode (`files/_cache/maintenance_mode`)
6. Stop Apache/PHP-FPM services
7. **Restore DB** (if selected): `gunzip -k` → `mysql < dump.sql`
8. **Restore files** (if selected): extract `files-*.tar.gz` to `$GLPI_INSTALL_PATH/`
9. **Restore webroot** (if selected): extract `webroot-*.tar.gz` to parent of `$GLPI_INSTALL_PATH/`
10. Fix file permissions (`chown -R` to web server user)
11. Start Apache/PHP-FPM services
12. Disable maintenance mode
13. Release lock, send summary alert

## Safety

- Interactive `confirm` before proceeding (auto-declines in dry-run and non-terminal)
- `.partial` backups are rejected
- Lock file prevents concurrent restores
- Maintenance mode prevents user access during restore
- Services are restarted via `trap` even on failure

## Service Management

```sh
# Detect PHP-FPM service name dynamically
_php_fpm=$(systemctl list-units --type=service --state=active | grep php | awk '{print $1}' | head -1)

# Stop before restore
systemctl stop apache2
[ -n "$_php_fpm" ] && systemctl stop "$_php_fpm"

# Restart after (in trap too)
systemctl start "$_php_fpm"
systemctl start apache2
```

## Interactive Backup Selection

```
Available backups in /mnt/nas/backups/glpi:
  1) 2026-02-26-020000  (DB: 45M, Files: 1.2G, Webroot: 89M)
  2) 2026-02-25-020000  (DB: 44M, Files: 1.2G, Webroot: 89M)
  3) 2026-02-24-020000  (PARTIAL - skipped)

Select backup [1]:
```

## Config

No new config keys. Uses existing: `BACKUP_DEST`, `GLPI_INSTALL_PATH`, `DB_*`, `RUN_USER`.

## Files to Create/Modify

- **Create:** `products/glpi/restore.sh`
- **Update:** `docs/USAGE.md` — add restore section
- **Update:** `docs/CONFIGURATION.md` — add lock file entry
- **Update:** `docs/TROUBLESHOOTING.md` — add restore errors
