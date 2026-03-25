# CLI Reference

> Without a mode flag the script runs in **execute mode**, which is
> **DESTRUCTIVE** -- it wipes storage, removes volumes, and (with reset
> flags) overwrites PVE configuration. Always use `--plan` or `--dry-run`
> first.

## Core Modes

- `--plan`: deterministic plan output, no execution, no prompts.
- `--audit-only`: run audit and print planned actions.
- `--dry-run`: simulate execution phases (read-only).
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
- `--quiet`: warnings/errors only. Cannot be combined with `--verbose` (usage exit code `2`).
- `--log-file <path>`: custom log file path.

Safety notes:
- `--report-file` and `--log-file` must not point to symlinks.
- `--report-file` and `--log-file` are rejected if they point to `/etc/pve` (including normalized paths like `/tmp/../etc/pve/...`).

## Reset Flags (DESTRUCTIVE)

- `--reset-pve-config`: **delete** guest configs (VM/CT), SDN, resource mappings, jobs, firewall (host, cluster, alias/groups/ipset), HA, notification config, metric servers, vzdump defaults, pve-ssh-known_hosts, manager status files, node private directory, and task logs.
- `--reset-users-datacenter`: **overwrite** users/ACL/secrets/datacenter to minimal defaults (root@pam only).
- `--reset-storage-cfg`: **overwrite** storage.cfg with the vanilla default.
- `--reset-all`: equivalent to all three reset flags above.
- `--backup-config`: back up `/etc/pve` before reset operations (only runs when combined with a reset flag).

All reset operations require cluster quorum and prompt for confirmation unless `--yes` is set.

## Third-Party Cleanup (DESTRUCTIVE)

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
