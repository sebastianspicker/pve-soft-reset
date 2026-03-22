# Draft Release Notes (v1.2.0)

## Highlights

- Modularized script architecture under `lib/` for clearer responsibilities and maintainability.
- Expanded safety and hardening around path validation and unattended execution.
- Improved planning/reporting UX with report-file output and pretty JSON mode.
- 8 bug fixes addressing failure-path correctness, Bash compatibility, and data-loss scenarios.
- 11 new tests bringing the suite from 44 to 55, covering CLI guards, storage audit edge cases, and JSON output validation.
- Security hardening: restrictive permissions on config backups, input validation on storage.cfg fields.

## Added

- `--non-interactive`
- `--report-file <path>`
- `--json-pretty`
- JSON fields: `meta.non_interactive`, `meta.scope.include`, `meta.scope.exclude`, `warnings`
- `lib/` modular script layout for constants, helpers, preflight, audit, execute, scope, and reporting.
- Documentation link verification script: `scripts/check-doc-links.sh`.
- 11 new BATS tests: CLI safety guards (--help exit code, --quiet/--verbose conflict, unknown option rejection), storage path validation, backup dry-run messaging, LVM snap/metadata exclusion, custom LVM pattern matching, SEP-character storage ID handling, empty storage.cfg, firewall stack detection, JSON boolean fields.
- Regex validation for `vgname` and `pool`/`thinpool` fields parsed from storage.cfg.

## Changed

- `json_escape` sed pipeline updated to handle control characters and additional escape sequences.
- `--json-pretty` moved from "Meta" to "General" section in `--help` output.
- README flowchart rewritten to accurately represent confirmation prompt flow.
- README lifecycle diagram corrected for `--list-storage` and `--json` exit paths.
- Documentation improvements: `--quiet`/`--verbose` mutual exclusion documented, `--reset-pve-config` description expanded, testing.md commands aligned with release-checklist.

## Bug Fixes

- `execute_reset_pve_config`: invalid-hostname failure now correctly increments `FAILURE_COUNT` and appears in the final summary instead of being silently swallowed by `|| true`.
- `validate_config_paths`: removed dead duplicate if/else branch -- both arms called `safe_realpath` identically.
- `run_audit_pipeline`: removed redundant `collect_storage_ids` call (already called as the first step of `apply_storage_scope_filters`).
- `--json` output: `ceph_found` and `ssh_keys_found` were present in the human report but absent from JSON; both boolean fields now appear in compact and pretty modes. Schema doc updated.
- `scripts/check-doc-links.sh`: replaced `rg` (ripgrep) with portable `grep -Eo`; the CI workflow did not install ripgrep, causing the docs link check step to fail.
- `execute_backup_pve_config` missing `|| true`: tar failure after storage wipe phases would abort the script via `set -e`, leaving destructive changes applied but no summary or config reset.
- `execute_wipe_dirs` now handles symlinks separately from regular files and uses `--one-file-system` to prevent crossing filesystem boundaries during wipe.
- `output_json_compact` empty array expansions guarded for Bash < 4.4 compatibility with `set -u`.
- `--purge-all-third-party` confirmation prompt now shows total package count and cleanly skips all purge targets when declined.
- Arithmetic expressions `((FAILURE_COUNT+=1))` guarded with `|| true` against `set -e`.
- `cleanup_lock` trap fixed to use hardcoded lock path instead of out-of-scope local variable.
- `BASH_REMATCH` regression fixed: captures saved to locals before calling functions that use `=~`.

## Safety and Hardening

- Stronger report/log path guards for symlinks and `/etc/pve` protection.
- Additional compatibility checks for mode/flag combinations.
- Dry-run accounting correctness fixes for config-change counters.
- `VANILLA_ORIGINS` regex injection fix: each origin token is now individually escaped before joining with `|`, preventing pattern injection via pipe characters in custom origin names.
- `ensure_safety_guards` path blacklist extended to cover `/proc`, `/sys`, `/boot`, `/dev`, `/run`, `/tmp`, `/srv`, and `/etc/pve`.
- Backup tarball created with `umask 077` (0600 permissions) to prevent world-readable access to sensitive config data.
- `vgname`/`pool` fields validated against `^[A-Za-z0-9+_.:/-]+$` before use in LVM/ZFS commands.

## Compatibility

- No intentional breaking changes for existing v1 usage.
- New behavior is additive and opt-in.

## Verification Evidence

- `bash -n pve-soft-reset.sh lib/*.bash` passed
- `shellcheck -x pve-soft-reset.sh lib/*.bash` passed
- `./scripts/check-doc-links.sh` passed
- `bats tests/` -- 55/55 passed

## Notes

- This branch is in prepare-only mode and intentionally does not publish a GitHub release.

