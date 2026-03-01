# Testing Guide

## Local Checks

```bash
bash -n pve-soft-reset.sh
shellcheck -x pve-soft-reset.sh
shellcheck -x lib/*.bash
./scripts/check-doc-links.sh
bats tests
```

## Test Layout

- `tests/audit_storage.bats`: storage parsing, node/disabled handling, include/exclude scope.
- `tests/json_output.bats`: JSON validity + stable array keys.
- `tests/safety_guards.bats`: usage/preflight exit codes, no-color, plan no-side-effect behavior, non-interactive/report-file/json-pretty guardrails.
- `tests/fixtures/storage.cfg.basic`: canonical fixture with placeholder base path.
- `tests/helpers/common.bash`: mock command setup for deterministic testing.

## Notes

- Tests run with `PVE_SOFT_RESET_TEST_MODE=1` to avoid requiring root and `/etc/pve`.
- **Do not set `PVE_SOFT_RESET_TEST_MODE` in production**; it bypasses root and path validation.
- External system commands are mocked for deterministic behavior.
- CI runs Bash syntax check, ShellCheck, and Bats.

## Development / security

Safety measures implemented in the script include: log file must not be a symlink, a directory, or under `/etc/pve`; `ALLOWED_DIR_STORAGE_BASE` blacklist includes `/`, `/etc`, `/root`, `/var`, `/usr`, `/home`, `/opt`; `CONFIGS_CLEARED` only incremented on success; `csv_to_array` restricted to known output variable names. When changing audit or execution logic, run the full test suite and ShellCheck.
