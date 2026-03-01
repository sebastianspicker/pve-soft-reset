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

## Safety and Hardening

- Stronger report/log path guards for symlinks and `/etc/pve` protection.
- Additional compatibility checks for mode/flag combinations.
- Dry-run accounting correctness fixes for config-change counters.

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

