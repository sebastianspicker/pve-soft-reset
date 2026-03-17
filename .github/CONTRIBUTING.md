# Contributing

## Development setup

Run the local checks before opening a PR:

```bash
bash -n pve-soft-reset.sh lib/*.bash
shellcheck -x pve-soft-reset.sh lib/*.bash
./scripts/check-doc-links.sh
bats tests
```

## Pull requests

- Keep changes focused; one concern per PR.
- Add or update bats tests for any changed behaviour in `lib/`.
- Update `docs/` if CLI flags or JSON output change.
- All CI checks must pass before merge.

## Reporting bugs

Use the [bug report template](.github/ISSUE_TEMPLATE/bug_report.md).
