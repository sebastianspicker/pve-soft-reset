# Release Prep Inventory

Snapshot classification for the current release-prep branch.

## Release artifacts

- `pve-soft-reset.sh`
- `lib/constants.bash`
- `lib/helpers.bash`
- `lib/cli_preflight.bash`
- `lib/storage_scope.bash`
- `lib/audit.bash`
- `lib/execute.bash`
- `lib/reporting.bash`
- `.github/workflows/ci.yml`
- `.gitignore`
- `README.md`
- `docs/cli.md`
- `docs/json-schema.md`
- `docs/testing.md`
- `CHANGELOG.md`
- `docs/release-checklist.md`
- `docs/release-notes-draft.md`
- `scripts/check-doc-links.sh`

## Test artifacts (kept)

- `tests/audit_storage.bats`
- `tests/json_output.bats`
- `tests/safety_guards.bats`
- `tests/helpers/common.bash`
- `tests/fixtures/storage.cfg.basic`

## Removed stale artifacts

- `docs/reference.txt` (removed; no longer referenced)

## Temporary artifacts policy

- No build output or temporary release files are tracked.
- Local report outputs are ignored by `.gitignore` (`*.report.txt`, `report-*.txt`).

