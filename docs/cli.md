# CLI Reference

## Core Modes

- `--plan`: deterministic plan output, no execution, no prompts.
- `--audit-only`: run audit and print planned actions.
- `--dry-run`: simulate execution phases.
- `--json`: output audit result as JSON and exit.
- `--list-storage`: print discovered storage IDs and exit.

Only one core mode can be used at a time.

## Scope Flags

- `--include-storage <csv>`: only include listed storage IDs.
- `--exclude-storage <csv>`: exclude listed storage IDs.

Unknown IDs in include/exclude produce usage exit code `2`.

## Execution/UX Flags

- `-y`, `--yes`: skip confirmation prompts.
- `--no-sync`: skip sync after wipe phases.
- `--no-color`: force colorless output.
- `--verbose`: debug-style verbosity.
- `--quiet`: warnings/errors only.
- `--log-file <path>`: custom log file path.

## Reset Flags

- `--reset-pve-config`
- `--reset-users-datacenter`
- `--reset-storage-cfg`
- `--reset-all` (combines all reset flags)
- `--backup-config`

## Third-Party Cleanup

- `--purge-all-third-party`: purge all detected non-vanilla packages.

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
