# pve-soft-reset

[![CI](https://github.com/sebastian/pve-soft-reset/actions/workflows/ci.yml/badge.svg)](https://github.com/sebastian/pve-soft-reset/actions/workflows/ci.yml)

Audit-based soft reset for Proxmox VE hosts, without reinstalling the OS.

The script audits the current host state, derives actions from live data, and can then execute or simulate cleanup/reset steps. Third-party package detection is based on APT origin (Debian, Proxmox, and optionally Ceph).

**Requirements:** Bash 4+, Proxmox VE host; root (or equivalent) is required for execute mode.

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
- `--non-interactive` guard to block accidental prompt waits in unattended runs.

## How It Works

```mermaid
flowchart TD
  A["CLI invocation"] --> B["Parse flags and mode"]
  B --> C["Preflight: root, path, runtime guards"]
  C -->|blocked| X3["Exit 3 (preflight/safety)"]
  C --> D["Audit pipeline"]

  subgraph D1["Audit Pipeline"]
    D --> D2["storage.cfg parse"]
    D2 --> D3["collect IDs + scope filters"]
    D3 --> D4["dependency checks"]
    D4 --> D5["LVM/ZFS/third-party/ceph/ssh/firewall audits"]
  end

  D5 --> E{"Selected mode"}
  E -->|"--list-storage"| M1["Print storage IDs"] --> X0["Exit 0"]
  E -->|"--json (--json-pretty optional)"| M2["Emit JSON object"] --> X0
  E -->|"--plan / --audit-only"| M3["Print preflight + planned actions"] --> X0
  E -->|"--dry-run / execute"| F["Execution pipeline"]

  subgraph F1["Execution Pipeline"]
    F --> F2["Safety guards"]
    F2 --> F3["Wipe dir/LVM/ZFS targets"]
    F3 --> F4["Config quorum gate + optional backup"]
    F4 --> F5["Third-party purge"]
    F5 --> F6{"Prompted destructive steps"}
    F6 -->|"--non-interactive and prompt required"| X3
    F6 -->|"confirmed / --yes"| F7["Optional reset actions"]
    F7 --> F8["Final summary"]
  end

  F8 --> R{"Any failures?"}
  R -->|yes| X1["Exit 1 (runtime/partial failure)"]
  R -->|no| X0
```

## Lifecycle

```mermaid
flowchart TD
  L1["Start"] --> L2["Parse args + preflight"]
  L2 -->|"preflight fail"| E3["Exit 3"]
  L2 --> L3["Audit and scope"]
  L3 --> L4["Render report context"]

  L4 -->|"list-storage"| E0a["Exit 0"]
  L4 -->|"json/json-pretty"| E0b["Exit 0"]
  L4 -->|"plan/audit-only"| E0c["Exit 0"]
  L4 -->|"dry-run or execute"| L5["Run execution phases"]

  L5 --> L6{"Interactive confirmations needed?"}
  L6 -->|"yes + non-interactive"| E3
  L6 -->|"confirmed / auto-yes"| L7["Apply reset/purge steps"]
  L7 --> L8["Print final summary"]
  L8 --> L9{"failure_count > 0 ?"}
  L9 -->|"yes"| E1["Exit 1"]
  L9 -->|"no"| E0d["Exit 0"]
```

List-storage and json exit after the audit; plan and audit exit after the report; dry-run and execute continue through execution phases to the final summary.

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

5. Write a report artifact while planning:

```bash
./pve-soft-reset.sh --plan --report-file ./plan.report.txt
```

6. Emit pretty JSON for automation/debug readability:

```bash
./pve-soft-reset.sh --json --json-pretty
```

## Exit Codes

- `0`: success
- `1`: runtime/partial failure
- `2`: CLI usage error
- `3`: preflight/safety blocker

## Documentation

- [Changelog](CHANGELOG.md)
- [CLI Reference](docs/cli.md)
- [JSON Output Schema](docs/json-schema.md)
- [Testing Guide](docs/testing.md)
- [Release Checklist](docs/release-checklist.md)
- [Draft Release Notes](docs/release-notes-draft.md)
- [Release Prep Inventory](docs/release-prep-inventory.md)

## Testing

```bash
bash -n pve-soft-reset.sh
shellcheck -x pve-soft-reset.sh
shellcheck -x lib/*.bash
./scripts/check-doc-links.sh
bats tests
```

## Migration Notes (v1.2.0)

- No breaking CLI or JSON changes.
- New flags are optional: `--non-interactive`, `--report-file`, `--json-pretty`.
- JSON output remains backward compatible; additive fields are available under `meta` and `warnings`.

## License

See [LICENSE](LICENSE).
