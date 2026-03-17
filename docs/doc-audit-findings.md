# Documentation Audit Findings — pve-soft-reset

Generated: 2026-03-17
Scope: `README.md`, `docs/*.md`, inline comments and usage strings in `pve-soft-reset.sh` and `lib/*.bash`

---

## Pass 1 — AI Slop Detection

No AI slop phrases ("seamlessly", "robust", "comprehensive", "leverage", "utilize", "streamline",
"powerful", "flexible", "easy-to-use", "best practices") found in any documentation file or
inline comment. The codebase documentation was already written in direct, functional prose.

No hollow padding or over-hedging patterns found. No bullet disease identified (bullet lists
present are appropriate for CLI flag references and step-by-step quickstart instructions).

---

## Pass 2 — Human Writing Style

### FIXED: Passive voice in README.md Requirements line

**File:** `README.md:9`

**Before:**
```
**Requirements:** Bash 4+, Proxmox VE host; root (or equivalent) is required for execute mode.
```

**After:**
```
**Requirements:** Bash 4+, Proxmox VE host; execute mode requires root.
```

Removed passive construction "is required for execute mode" → active "execute mode requires root".
Also removed the parenthetical "(or equivalent)" which is implied.

---

### FIXED: "Development / security" section — impenetrable run-on sentence and passive opener

**File:** `docs/testing.md:28-30`

**Before:**
```markdown
## Development / security

Safety measures implemented in the script include: log file must not be a symlink, a directory,
or under `/etc/pve`; `ALLOWED_DIR_STORAGE_BASE` blacklist includes `/`, `/etc`, `/etc/pve`,
`/root`, `/var`, `/usr`, `/home`, `/opt`, `/proc`, `/sys`, `/boot`, `/dev`, `/run`, `/tmp`,
`/srv`; `CONFIGS_CLEARED` only incremented on success; `csv_to_array` restricted to known
output variable names; `VANILLA_ORIGINS` tokens are individually regex-escaped before
alternation to prevent pattern injection. When changing audit or execution logic, run the
full test suite and ShellCheck.
```

Issues:
- Heading "Development / security" is ambiguous (what does the Development part refer to?).
- Passive opener "Safety measures implemented in the script include:" obscures agency.
- Five distinct constraints chained with semicolons into a single sentence — unreadable on first pass.
- The final instruction ("run the full test suite") is buried at the end of the wall of text.

**After:**
```markdown
## Security constraints

The log file must not be a symlink, a directory, or under `/etc/pve`. `ALLOWED_DIR_STORAGE_BASE`
is blacklisted against `/`, `/etc`, `/etc/pve`, `/root`, `/var`, `/usr`, `/home`, `/opt`,
`/proc`, `/sys`, `/boot`, `/dev`, `/run`, `/tmp`, and `/srv`. `CONFIGS_CLEARED` increments
only on success. `csv_to_array` accepts only known output variable names. `VANILLA_ORIGINS`
tokens are individually regex-escaped before alternation to prevent pattern injection.

When changing audit or execution logic, run the full test suite and ShellCheck.
```

Changes: renamed heading to the direct "Security constraints", rewrote as five short active
sentences (one per constraint), separated the developer instruction into its own paragraph.

---

## Pass 3 — Documentation Quality and Deduplication

### Verified: No duplication found

All documentation was reviewed for cross-file duplication:

- `README.md` quickstart vs `docs/cli.md` examples: distinct audiences (intro vs reference). No duplication.
- `README.md` exit codes vs `docs/cli.md`: README has the canonical table; cli.md usage string footer repeats the same four codes in a single line — appropriate for quick reference in both places.
- `docs/testing.md` vs `README.md` Testing section: previously fixed (code audit run 1). README now simply references testing.md.
- `docs/release-notes-draft.md` vs `docs/audit-findings.md` bug listings: different contexts (user-facing release notes vs internal audit trail). No consolidation needed.

### Verified: No stale content found

- CLI flag documentation in `docs/cli.md` matches flags parsed in `lib/cli_preflight.bash:8-108`. All flags present and described correctly.
- Exit code table in README matches `EXIT_OK/EXIT_RUNTIME/EXIT_USAGE/EXIT_PREFLIGHT` constants in `lib/constants.bash`.
- JSON schema doc (`docs/json-schema.md`) was verified to match actual JSON output in `lib/reporting.bash` (including `ceph_found` and `ssh_keys_found` added in code audit run 1).

### Verified: Structural issues

No information is buried under the wrong heading. No caveats appear after examples where they should precede them.

The "Development / security" → "Security constraints" rename (Pass 2) also improves discoverability: developers looking for safety constraints will find the section immediately.

---

---

## Run 2 — Additional Findings (2026-03-17)

### FIXED: Reset Flags section in docs/cli.md had no descriptions

**File:** `docs/cli.md:38-44`

The Reset Flags section listed five flags bare, with no descriptions:

```markdown
## Reset Flags

- `--reset-pve-config`
- `--reset-users-datacenter`
- `--reset-storage-cfg`
- `--reset-all` (combines all reset flags)
- `--backup-config`
```

The `--help` output (usage() in `lib/helpers.bash`) describes each flag clearly. A reader consulting the CLI reference doc got less information than `--help`. The `--backup-config` behavior — only runs when combined with a reset flag — was undocumented in both places.

**Fix:**

```markdown
## Reset Flags

- `--reset-pve-config`: reset guest configs, SDN, mappings, jobs, firewall, and HA.
- `--reset-users-datacenter`: reset users/ACL/secrets/datacenter to minimal defaults.
- `--reset-storage-cfg`: overwrite storage.cfg with the vanilla default.
- `--reset-all`: equivalent to all three reset flags above.
- `--backup-config`: back up `/etc/pve` before reset operations (only runs when combined with a reset flag).

All reset operations require cluster quorum and prompt for confirmation unless `--yes` is set.
```

### FIXED: `docs/json-schema.md` — meta object missing 5 of 8 fields

**File:** `docs/json-schema.md:7-10`

The `meta` object in the schema only documented `non_interactive`, `scope.include`, and `scope.exclude`. The actual JSON output (`lib/reporting.bash`, `output_json_compact` and `output_json_pretty`) emits eight fields in `meta`: `version`, `timestamp`, `hostname`, `failure_count`, `mode`, `non_interactive`, and `scope` (as a nested object with `include`/`exclude`). The notation `scope.include` was also ambiguous — it looks like a flat dotted key but the actual output is a nested JSON object.

**Before:**
```markdown
- `meta` (object)
  - `non_interactive` (boolean)
  - `scope.include` (string)
  - `scope.exclude` (string)
```

**After:**
```markdown
- `meta` (object)
  - `version` (string)
  - `timestamp` (string, ISO 8601)
  - `hostname` (string)
  - `failure_count` (integer)
  - `mode` (string: `execute`, `dry-run`, `plan`, `audit`, `json`, or `list-storage`)
  - `non_interactive` (boolean)
  - `scope` (object)
    - `include` (string, CSV or empty)
    - `exclude` (string, CSV or empty)
```

---

## Summary

| # | Pass | File | Change |
|---|------|------|--------|
| 1 | 2 | `README.md` | Fix passive voice: "root (or equivalent) is required" → "execute mode requires root" |
| 2 | 2 | `docs/testing.md` | Rename "Development / security" → "Security constraints"; rewrite run-on sentence as five direct sentences |
| 3 | 3 | `docs/cli.md` | Add missing descriptions to Reset Flags section; document `--backup-config` conditional behavior and quorum requirement |
| 4 | 3 | `docs/json-schema.md` | Add missing `meta` fields: `version`, `timestamp`, `hostname`, `failure_count`, `mode`; clarify `scope` as nested object |
