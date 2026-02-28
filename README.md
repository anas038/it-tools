# it-tools

IT administration automation toolkit. Automates monitoring, backup, purge, and archive operations for GLPI (open-source ITSM).

## Features

- **Check** — Pre-flight validation of config, dependencies, paths, database, and config values
- **Monitor** — Full stack health check: DNS, HTTP, Apache, MariaDB, PHP, disk space, SSL certificate expiry. Sends recovery alerts when issues resolve.
- **Backup** — Database dump + files + webroot with retention policy and integrity verification
- **Restore** — Selective restore of database, files, and/or webroot from a backup image
- **Purge** — Delete old tickets, logs, notifications, and trashed items with configurable thresholds
- **Archive** — Export old data to SQL dumps or an archive database, then remove from live DB
- **Report** — Ticket quality control reports with CSV + HTML output
- **Asset Status** — Update asset warranty and support status via GLPI API
- **Status** — Read-only overview of GLPI instance, database, and backup state

All tools support `--dry-run`, multi-channel alerts (email, Teams, Slack), lock files to prevent concurrent runs, and a safety gate that requires a recent backup before destructive operations.

## Requirements

- POSIX sh (`/bin/sh`)
- `curl`, `tar`, `gzip`
- `mysql`, `mysqldump` (MariaDB client)
- `systemctl`, `mountpoint` (Linux)
- `nslookup` (from `dnsutils`)
- `mail`, `msmtp`, or `sendmail` (for email alerts, optional)

## Quick Start

### Install

```sh
git clone https://github.com/anas038/it-tools.git
cd it-tools
sudo sh install.sh
```

The installer will:
1. Check dependencies
2. Copy files to `/opt/it-tools`
3. Create a symlink at `/usr/local/bin/it`
4. Walk you through configuration
5. Optionally set up cron jobs

For non-interactive installs:

```sh
sudo sh install.sh --user admdev --product glpi --path-method symlink --cron
```

### Configure

```sh
cp products/glpi/glpi.conf.example products/glpi/glpi.conf
chmod 600 products/glpi/glpi.conf
# Edit glpi.conf with your environment values
```

See [docs/CONFIGURATION.md](docs/CONFIGURATION.md) for every parameter.

### Run

```sh
it glpi list                     # List available tools
it glpi monitor                  # Run health check
it glpi backup --dry-run         # Preview backup
it glpi backup                   # Run backup
it glpi purge --dry-run          # Preview purge
it glpi archive --months 6       # Archive data older than 6 months
```

See [docs/USAGE.md](docs/USAGE.md) for detailed per-tool documentation.

## Cron Examples

```cron
# Health monitoring — every 5 minutes
*/5 * * * * /opt/it-tools/bin/it glpi monitor >> /opt/it-tools/logs/cron.log 2>&1

# Full backup — daily at 02:00
0 2 * * * /opt/it-tools/bin/it glpi backup >> /opt/it-tools/logs/cron.log 2>&1

# Purge old data — weekly on Sunday at 03:00
0 3 * * 0 /opt/it-tools/bin/it glpi purge >> /opt/it-tools/logs/cron.log 2>&1

# Archive old data — monthly on 1st at 04:00
0 4 1 * * /opt/it-tools/bin/it glpi archive >> /opt/it-tools/logs/cron.log 2>&1
```

## Uninstall

```sh
sudo sh uninstall.sh                # Interactive — asks what to keep
sudo sh uninstall.sh --keep-config  # Remove tools, preserve configs and logs
sudo sh uninstall.sh --purge        # Remove everything
```

## Documentation

- [Usage Guide](docs/USAGE.md) — CLI structure, common flags, per-tool reference
- [Configuration Reference](docs/CONFIGURATION.md) — Every config parameter with defaults
- [Troubleshooting](docs/TROUBLESHOOTING.md) — Error messages, causes, and fixes by exit code

## Project Structure

```
bin/it                          Dispatcher (auto-discovers products and tools)
lib/common.sh                   Logging, exit codes, locks, retries, error collection
lib/alert.sh                    Multi-channel alerts with cooldown
lib/db.sh                       Database credential loading and query helpers
lib/backup_check.sh             Safety gate (verify recent backup)
products/glpi/check.sh          Config and dependency validator
products/glpi/monitor.sh        Health check tool
products/glpi/backup.sh         Backup tool
products/glpi/restore.sh        Restore tool
products/glpi/purge.sh          Purge tool
products/glpi/archive.sh        Archive tool
products/glpi/report.sh         Ticket quality reports
products/glpi/asset_status.sh   Warranty and support status
products/glpi/status.sh         Instance overview
products/glpi/glpi.conf.example Example configuration
cron/glpi.cron.example          Example cron entries
install.sh                      Installer
uninstall.sh                    Uninstaller
```

## Adding a New Tool

1. Create `products/<product>/<tool>.sh` with a `# description:` comment on line 2
2. Source `lib/common.sh` and any needed libraries
3. Call `parse_common_flags "$@"` for `--dry-run`, `--verbose`, `--quiet`, `--help`
4. The dispatcher discovers it automatically — no registration needed

## License

All rights reserved.
