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

### Changed
- README updated with operational workflow and lifecycle diagrams.
- CLI and JSON docs aligned with implemented behavior and safety constraints.
- Safety guard test coverage expanded for path validation, flag compatibility, and dry-run accounting.

### Security / Hardening
- Hardened path validation for report/log targets, including symlink checks and `/etc/pve` path protection.
- Enforced report-mode incompatibility with machine-only modes (`--json`, `--list-storage`).
- Improved dry-run accounting so config-change counters are not incremented on simulation.
- Reduced risk in parsing logic and shell option handling.

### Compatibility
- No intentional breaking changes to existing v1 CLI behavior.
- New flags and JSON fields are additive.

### Release status
- Prepare-only state: validated and ready for tag/release, not published from this branch.

