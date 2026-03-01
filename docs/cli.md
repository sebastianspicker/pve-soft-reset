# CLI Reference

## Core Modes

- `--plan`: deterministic plan output, no execution, no prompts.
- `--audit-only`: run audit and print planned actions.
- `--dry-run`: simulate execution phases.
- `--json`: output audit result as JSON and exit.
- `--json-pretty`: pretty-print JSON output (requires `--json`).
- `--list-storage`: print discovered storage IDs and exit.

Only one core mode can be used at a time.

## Scope Flags

- `--include-storage <csv>`: only include listed storage IDs.
- `--exclude-storage <csv>`: exclude listed storage IDs.
- `--report-file <path>`: write preflight/planned/summary report to file.

Unknown IDs in include/exclude produce usage exit code `2`.
`--json-pretty` without `--json` produces usage exit code `2`.
`--report-file` cannot be combined with `--json` or `--list-storage`.

## Execution/UX Flags

- `-y`, `--yes`: skip confirmation prompts.
- `--non-interactive`: fail with preflight exit code `3` if a confirmation prompt would be required.
- `--no-sync`: skip sync after wipe phases.
- `--no-color`: force colorless output.
- `--verbose`: debug-style verbosity.
- `--quiet`: warnings/errors only.
- `--log-file <path>`: custom log file path.

Safety notes:
- `--report-file` and `--log-file` must not point to symlinks.
- `--report-file` and `--log-file` are rejected if they point to `/etc/pve` (including normalized paths like `/tmp/../etc/pve/...`).

## Reset Flags

- `--reset-pve-config`
- `--reset-users-datacenter`
- `--reset-storage-cfg`
- `--reset-all` (combines all reset flags)
- `--backup-config`

## Third-Party Cleanup

- `--purge-all-third-party`: purge all detected non-vanilla packages.

## Meta Flags

- `--version`: print version and exit.
- `--help`: print usage and exit.

## Examples

Plan only:

```bash
./pve-soft-reset.sh --plan
```

Dry-run scoped to selected storages:

```bash
./pve-soft-reset.sh --dry-run --include-storage local,local-lvm
```

Real execution with explicit resets:

```bash
sudo ./pve-soft-reset.sh --reset-pve-config --reset-users-datacenter
```
