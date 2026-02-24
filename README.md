# pve-soft-reset

Audit-based soft reset for Proxmox VE hosts, without reinstalling the OS.

The script audits the current host state, derives actions from live data, and can then execute or simulate cleanup/reset steps.

## What It Does

- Audits `storage.cfg` and derives directory/LVM/ZFS wipe targets.
- Detects third-party packages by APT origin.
- Optionally resets Proxmox config artifacts (VM/CT configs, SDN, mappings, jobs, firewall, HA).
- Optionally resets users/datacenter config to a minimal baseline.
- Supports safe planning and scoping before execution.

## Key Safety Features

- Explicit preflight checks and dedicated preflight exit code.
- Storage path allowlist with blacklist protection for dangerous bases.
- `--plan` mode for deterministic no-side-effect planning.
- `--dry-run` mode for execution simulation.
- Storage ID scoping via include/exclude filters.

## Quickstart

1. Show deterministic plan only:

```bash
./pve-soft-reset.sh --plan
```

2. Simulate full execution:

```bash
./pve-soft-reset.sh --dry-run
```

3. Execute for real:

```bash
sudo ./pve-soft-reset.sh
```

4. Scope to selected storages:

```bash
./pve-soft-reset.sh --plan --include-storage local,local-lvm
```

## Exit Codes

- `0`: success
- `1`: runtime/partial failure
- `2`: CLI usage error
- `3`: preflight/safety blocker

## Documentation

- [CLI Reference](docs/cli.md)
- [JSON Output Schema](docs/json-schema.md)
- [Testing Guide](docs/testing.md)
- [Reference Snapshot](docs/reference.txt)

## Testing

```bash
bash -n pve-soft-reset.sh
shellcheck -x pve-soft-reset.sh
bats tests
```

## License

See [LICENSE](LICENSE).
