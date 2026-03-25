# Testing Guide

## Local Checks

```bash
bash -n pve-soft-reset.sh lib/*.bash
shellcheck -x pve-soft-reset.sh lib/*.bash
./scripts/check-doc-links.sh
bats tests
```

## Test Layout

- `tests/audit_storage.bats`: storage parsing, node/disabled handling, include/exclude scope.
- `tests/audit_third_party.bats`: third-party package detection by origin, unknown-origin fallback, purge target inclusion.
- `tests/execute_wipe.bats`: LVM/ZFS/dir wipe planned actions, protected volume exclusion, dry-run output.
- `tests/json_output.bats`: JSON validity, stable array keys, additive metadata fields (`meta.non_interactive`, `meta.scope`, `warnings`), and `--json-pretty` formatting.
- `tests/reset_pve_config.bats`: PVE config reset for VM/CT/SDN/jobs artifacts, hostname validation guard.
- `tests/safety_guards.bats`: usage/preflight exit codes, no-color, plan no-side-effect behavior, non-interactive/report-file/json-pretty guardrails, log-file path safety (symlink, /etc/pve, path traversal), report-file symlink/path-traversal rejection, ALLOWED_DIR_STORAGE_BASE blacklist for system paths, and dry-run config-change accounting.
- `tests/fixtures/storage.cfg.basic`: canonical fixture with placeholder base path.
- `tests/helpers/common.bash`: mock command setup for deterministic testing.

## Notes

- Tests run with `PVE_SOFT_RESET_TEST_MODE=1` to avoid requiring root and `/etc/pve`.
- **Do not set `PVE_SOFT_RESET_TEST_MODE` in production**; it bypasses root and path validation.
- External system commands are mocked for deterministic behavior.
- CI runs Bash syntax check, ShellCheck, and Bats.

## Security constraints

The log file must not be a symlink, a directory, or under `/etc/pve`. `ALLOWED_DIR_STORAGE_BASE` is blacklisted against `/`, `/etc`, `/etc/pve`, `/root`, `/var`, `/usr`, `/home`, `/opt`, `/proc`, `/sys`, `/boot`, `/dev`, `/run`, `/tmp`, and `/srv`. `CONFIGS_CLEARED` increments only on success. `csv_to_array` accepts only known output variable names. `VANILLA_ORIGINS` tokens are individually regex-escaped before alternation to prevent pattern injection.

When changing audit or execution logic, run the full test suite and ShellCheck.
