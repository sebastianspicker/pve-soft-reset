# Testing Guide

## Local Checks

```bash
bash -n pve-soft-reset.sh
shellcheck -x pve-soft-reset.sh
bats tests
```

## Test Layout

- `tests/audit_storage.bats`: storage parsing, node/disabled handling, include/exclude scope.
- `tests/json_output.bats`: JSON validity + stable array keys.
- `tests/safety_guards.bats`: usage/preflight exit codes, no-color, plan no-side-effect behavior.
- `tests/fixtures/storage.cfg.basic`: canonical fixture with placeholder base path.
- `tests/helpers/common.bash`: mock command setup for deterministic testing.

## Notes

- Tests run with `PVE_SOFT_RESET_TEST_MODE=1` to avoid requiring root and `/etc/pve`.
- External system commands are mocked for deterministic behavior.
- CI runs Bash syntax check, ShellCheck, and Bats.
