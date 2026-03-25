# Release Checklist (Prepare-Only)

Use this checklist to prepare a release candidate for GitHub without publishing it.

## 1. Repository hygiene

- Verify branch context:
  - `git status --short --branch`
- Confirm no accidental temporary artifacts are tracked.
- Confirm stale docs were removed (for example `docs/reference.txt`) and are not referenced.

## 2. Validation gates (must pass)

- `bash -n pve-soft-reset.sh lib/*.bash`
- `shellcheck -x pve-soft-reset.sh lib/*.bash`
- `./scripts/check-doc-links.sh`
- `bats tests`

## 3. Documentation parity checks

- `README.md` quickstart examples reflect supported flags.
- `docs/cli.md` matches `--help` output and flag compatibility rules.
- `docs/json-schema.md` matches actual `--json` fields.
- Version notes in `README.md` and `CHANGELOG.md` align with `lib/constants.bash`.

## 4. Diagram checks

- README "How It Works" mermaid flow includes:
  - parse/preflight gates
  - audit pipeline
  - mode branching
  - confirmation/non-interactive path
  - summary + exit outcomes
- README lifecycle diagram includes:
  - start, audit, reporting, early exits, execute path, success/failure exits

## 5. Release notes preparation

- Update `CHANGELOG.md` for target version.
- Update `docs/release-notes-draft.md` with highlights, hardening, compatibility, and verification evidence.

## 6. Tag plan (do not publish in prepare-only mode)

- Determine release tag format: `vX.Y.Z`.
- Verify tag does not exist:
  - `git tag --list | grep -x "vX.Y.Z"`
- Prepare but do not run publish actions.

## 7. Prepare-only stop point

At this point, repository is release-ready. Stop before:

- pushing release tags
- creating/publishing GitHub release objects

