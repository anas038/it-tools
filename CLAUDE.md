# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

it-tools is a POSIX sh CLI toolkit for automating IT administration tasks. The first product module is GLPI (open-source ITSM). The framework supports multiple products under `products/<name>/`.

## Shell Constraints

All scripts MUST be POSIX sh compliant (`#!/bin/sh`, `set -eu`). No bash-isms:
- No `[[ ]]` — use `[ ]`
- No arrays — use space-separated strings or positional parameters
- No `${var,,}` — use `tr '[:upper:]' '[:lower:]'`
- No `<<<` here-strings — use `echo ... | cmd`
- No `source` — use `.`

## Architecture

- `bin/it` — Dispatcher. Auto-discovers products in `products/` and tools within them
- `lib/common.sh` — Logging, exit codes, lock files, retries, error collection
- `lib/alert.sh` — Multi-channel alerts (email, Teams, Slack, log) with cooldown
- `lib/db.sh` — DB credential loading (direct or GLPI auto-detect), query/dump helpers
- `lib/backup_check.sh` — Safety gate: verify recent backup before destructive ops
- `lib/report.sh` — HTML/CSV report generation helpers for ticket quality control
- `products/<name>/<tool>.sh` — Product-specific tools. Each has `# description:` comment

## Exit Codes

0=OK, 1=Config, 2=Dependency, 3=Database, 4=Service, 5=Filesystem, 6=Lock, 7=Safety, 8=Partial

## Testing

Run: `sh tests/run_tests.sh`
Single test: `sh tests/test_common.sh`
Test helper provides: `assert_equals`, `assert_true`, `assert_contains`, `assert_file_exists`

## Adding a New Tool

1. Create `products/<product>/<tool>.sh` with `# description:` comment
2. Source `lib/common.sh` and any needed libraries
3. Call `parse_common_flags "$@"` for --dry-run, --verbose, --quiet
4. The dispatcher discovers it automatically

## Documentation

- `README.md` — Project overview, quick start, cron examples
- `docs/USAGE.md` — Per-tool CLI reference with flags, steps, and exit codes
- `docs/CONFIGURATION.md` — All config parameters with types and defaults (from script fallbacks)
- `docs/TROUBLESHOOTING.md` — Errors by exit code with verbatim messages and fixes
- `docs/plans/` — Internal design and implementation plans

When adding or changing tools, update `docs/USAGE.md` and `docs/CONFIGURATION.md` to match. Error messages should stay in sync with `docs/TROUBLESHOOTING.md`. Version is runtime-only (`bin/it`), not hardcoded in docs.

## Key Design Decisions

- Report and asset_status tools use lock files; monitoring does not
- Destructive ops (backup/purge/archive) use lock files; monitoring does not
- Purge/archive require a recent backup (safety gate)
- All destructive ops support --dry-run
- Scripts continue on partial failure and report all errors at the end
- Alert cooldown prevents repeated notifications for sustained outages
