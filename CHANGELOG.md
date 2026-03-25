# Changelog

All notable changes to this project are documented in this file.

## [1.2.0] - 2026-03-01 (prepare-only)

### Added
- `--non-interactive` flag to enforce unattended safety behavior.
- `--report-file <path>` support for preflight/planned/summary report output.
- `--json-pretty` formatting option for `--json` output.
- New JSON metadata fields: `meta.non_interactive`, `meta.scope.include`, `meta.scope.exclude`.
- New top-level JSON field: `warnings`.
- `lib/` modular script layout for constants, helpers, preflight, audit, execute, scope, and reporting.
- Documentation link verification script: `scripts/check-doc-links.sh`.
- 11 new BATS tests covering CLI safety guards (--help, --quiet/--verbose conflict, unknown option), storage path validation (/etc/pve restriction), backup dry-run, LVM snap/metadata exclusion, LVM_WIPE_EXTRA_PATTERN matching, storage ID with SEP character handling, empty storage.cfg, firewall stack detection, and JSON boolean field presence.
- Regex validation for `vgname` and `pool`/`thinpool` fields parsed from storage.cfg (`^[A-Za-z0-9+_.:/-]+$`), rejecting entries with invalid characters before they reach LVM/ZFS commands.

### Changed
- `json_escape` sed pipeline updated to handle control characters and additional escape sequences.
- `--json-pretty` moved from "Meta" to "General" section in `--help` output to match its placement alongside `--json` in docs/cli.md.
- README flowchart rewritten to accurately show the main confirmation prompt (execute mode only) and per-feature prompts (ceph, ssh, users, storage) as distinct steps.
- README lifecycle diagram corrected so `--list-storage` and `--json` exit directly after audit instead of passing through report rendering.
- `--quiet`/`--verbose` mutual exclusion documented in docs/cli.md.
- `--reset-pve-config` description in docs/cli.md expanded to list all targets (notification, metric servers, vzdump defaults, pve-ssh-known_hosts, manager status files, node private directory, task logs).
- `testing.md` updated: `bash -n` command now includes `lib/*.bash`, shellcheck consolidated to single command, test file descriptions expanded.
- `docs/json-schema.md` jq example now notes `jq` as a prerequisite.
- `docs/release-notes-draft.md` aligned with CHANGELOG entries (Added, Changed sections).

### Fixed
- `execute_reset_pve_config`: invalid-hostname early return no longer silently skips FAILURE_COUNT increment.
- `validate_config_paths`: removed dead duplicate if/else branch in STORAGE_CFG canonicalisation.
- `run_audit_pipeline`: removed redundant `collect_storage_ids` call (already called by `apply_storage_scope_filters`).
- `--json` output: added missing `ceph_found` and `ssh_keys_found` boolean fields; updated `docs/json-schema.md`.
- `scripts/check-doc-links.sh`: replaced `rg` (ripgrep) with `grep -Eo` for portability; CI was missing the ripgrep dependency.
- `execute_backup_pve_config` missing `|| true` in `run_execution_phases`: if tar failed (e.g., disk full), `set -e` would abort after storage wipe phases had already run, leaving the user with destructive changes applied but no summary or config reset.
- `execute_wipe_dirs` now handles symlinks separately from regular files (using `rm -f` vs `rm -rf --one-file-system`), and uses `--one-file-system` to prevent crossing filesystem boundaries during wipe.
- `output_json_compact` empty array expansions guarded with length checks to prevent "unbound variable" errors on Bash < 4.4 with `set -u`.
- `--purge-all-third-party` confirmation prompt now shows total package count and cleanly skips all purge targets (including CrowdSec) when declined.
- `((FAILURE_COUNT+=1))` and `((CONFIGS_CLEARED+=1))` arithmetic expressions guarded with `|| true` to prevent `set -e` termination if the expression ever evaluates to 0.
- `cleanup_lock` trap now uses the hardcoded path `/run/pve-soft-reset.lock` instead of the out-of-scope local `$lockfile` variable, which expanded to empty string after `setup_runtime` returned, leaving a stale lock file.
- `BASH_REMATCH` regression in `audit_storage_cfg`: Phase 3 regex validation guards in `emit_storage_block` clobbered `BASH_REMATCH` before the caller could read captured groups; fixed by saving captures to local variables before the call.

### Security / Hardening
- Hardened path validation for report/log targets, including symlink checks and `/etc/pve` path protection.
- Enforced report-mode incompatibility with machine-only modes (`--json`, `--list-storage`).
- Dry-run no longer increments config-change counters.
- Tighter parsing logic and shell option handling.
- `VANILLA_ORIGINS` env-var tokens are now individually regex-escaped before alternation join, preventing pattern injection via `|` in custom origin names.
- `ensure_safety_guards` blacklist expanded to cover `/proc`, `/sys`, `/boot`, `/dev`, `/run`, `/tmp`, `/srv`, `/etc/pve`.
- Backup tarball (`/etc/pve` config backup) now created with `umask 077` (0600 permissions) to prevent world-readable access to sensitive data (shadow.cfg, API tokens, TFA config, ACME keys).
- `vgname` and `pool`/`thinpool` fields from storage.cfg validated against `^[A-Za-z0-9+_.:/-]+$` before use in LVM/ZFS commands, providing defense-in-depth against exotic characters.

### Compatibility
- No intentional breaking changes to existing v1 CLI behavior.
- New flags and JSON fields are additive.

### Release status
- Prepare-only state: validated and ready for tag/release, not published from this branch.

