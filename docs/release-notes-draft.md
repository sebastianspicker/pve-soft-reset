# Draft Release Notes (v1.2.0)

## Highlights

- Modularized script architecture under `lib/` for clearer responsibilities and maintainability.
- Expanded safety and hardening around path validation and unattended execution.
- Improved planning/reporting UX with report-file output and pretty JSON mode.

## Added

- `--non-interactive`
- `--report-file <path>`
- `--json-pretty`
- JSON fields: `meta.non_interactive`, `meta.scope.include`, `meta.scope.exclude`, `warnings`

## Bug Fixes

- `execute_reset_pve_config`: invalid-hostname failure now correctly increments `FAILURE_COUNT` and appears in the final summary instead of being silently swallowed by `|| true`.
- `validate_config_paths`: removed dead duplicate if/else branch — both arms called `safe_realpath` identically.
- `run_audit_pipeline`: removed redundant `collect_storage_ids` call (already called as the first step of `apply_storage_scope_filters`).
- `--json` output: `ceph_found` and `ssh_keys_found` were present in the human report but absent from JSON; both boolean fields now appear in compact and pretty modes. Schema doc updated.
- `scripts/check-doc-links.sh`: replaced `rg` (ripgrep) with portable `grep -Eo`; the CI workflow did not install ripgrep, causing the docs link check step to fail.

## Safety and Hardening

- Stronger report/log path guards for symlinks and `/etc/pve` protection.
- Additional compatibility checks for mode/flag combinations.
- Dry-run accounting correctness fixes for config-change counters.
- `VANILLA_ORIGINS` regex injection fix: each origin token is now individually escaped before joining with `|`, preventing pattern injection via pipe characters in custom origin names.
- `ensure_safety_guards` path blacklist extended to cover `/proc`, `/sys`, `/boot`, `/dev`, `/run`, `/tmp`, `/srv`, and `/etc/pve`.

## Compatibility

- No intentional breaking changes for existing v1 usage.
- New behavior is additive and opt-in.

## Verification Evidence

- `bash -n pve-soft-reset.sh lib/*.bash` passed
- `shellcheck -x pve-soft-reset.sh lib/*.bash` passed
- `./scripts/check-doc-links.sh` passed
- `bats tests` passed

## Notes

- This branch is in prepare-only mode and intentionally does not publish a GitHub release.

