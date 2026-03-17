# Audit Findings — pve-soft-reset

Generated: 2026-03-17
Scope: all source files (`pve-soft-reset.sh`, `lib/*.bash`), tests (`tests/`), docs (`docs/*.md`, `README.md`)

---

## Pass 1 — Logical & Technical Flaws

### FIXED: Redundant `collect_storage_ids` call

**File:** `pve-soft-reset.sh:72` (removed)

`run_audit_pipeline` called `collect_storage_ids` immediately before `apply_storage_scope_filters`, which itself calls `collect_storage_ids` as its first action. The explicit call was redundant — IDs were being built twice before scope filters ran.

**Fix:** Removed the standalone `collect_storage_ids` call from `run_audit_pipeline`; `apply_storage_scope_filters` already handles the initial collection.

---

### FIXED: `ceph_found` and `ssh_keys_found` missing from JSON output

**File:** `lib/reporting.bash`, `docs/json-schema.md`

`audit_ceph` sets `CEPH_FOUND` and `audit_ssh_keys` sets `SSH_KEYS_FOUND`. Both values are correctly displayed in the human-readable `print_planned_actions` output (`Ceph artifacts: ...`, `SSH cluster keys found: ...`) but were silently absent from `--json` output. Consumers relying on the JSON API could not detect Ceph artifacts or SSH key presence.

**Fix:** Added `ceph_found` and `ssh_keys_found` boolean fields to both `output_json_compact` and `output_json_pretty`. Updated `docs/json-schema.md` to document both fields.

---

### Informational: `audit_ssh_keys` / `execute_reset_ssh_keys` pattern breadth

**File:** `lib/audit.bash:423`, `lib/execute.bash:171`

The grep pattern `"root@|pve"` would match any authorized_keys entry whose comment contains the string `pve` (e.g., a user key from a host named `approval.example.com`). Similarly, `sed -i '/root@\|pve/d'` would remove those lines. This is a deliberate design choice — in a PVE cluster context, this catches cluster-injected keys — but worth noting as a potential false-positive risk when legitimate third-party keys have coincidental substring matches.

**Not fixed:** Design intent is clear; no change made.

---

### Informational: `_run_or_dry_preamble` return-value inversion

**File:** `lib/helpers.bash:260-269`

`_run_or_dry_preamble` returns `0` (success/true) to signal "we're in dry-run, skip execution" and returns `1` (failure) to signal "proceed with real action". Callers use `&& return 0` to short-circuit. This inverts the conventional bash return-code semantics but is consistent and internally documented by usage. No bug, but the unconventional pattern warrants note.

**Not fixed:** Would require refactoring all callers.

---

### Informational: `DIRS_WIPED` counter semantics

**File:** `pve-soft-reset.sh:362`

```bash
DIRS_WIPED=$((DIRS_WIPED + ${#WIPE_DIR_ENTRIES[@]}))
```

The counter counts storage *entries* processed, not the number of individual subdirectories actually wiped. The summary label "Dir storages processed" is accurate. No mismatch, but users reading the summary should understand this counts storage definitions, not filesystem operations.

**Not fixed:** Correctly documented by the label.

---

### Test coverage gaps (no fix applied — informational)

The following code paths lack bats test coverage:

| Area | What's missing |
|------|----------------|
| LVM audit | `list_lvs_to_remove` logic — protected vs. wipeable LVs, `LVM_WIPE_EXTRA_PATTERN` |
| ZFS audit | `list_zfs_datasets_to_remove` — `vm-*` / `subvol-*` selection logic |
| Third-party | `build_package_origins_cache` — origin parsing, URI-based fallback |
| Execute phases | `execute_reset_pve_config`, `execute_reset_users_datacenter` |
| Execute wipe dirs | Subdirectory path containment, symlink handling in `execute_wipe_dirs` |
| Path helpers | `normalize_abs_path_lexical` with `..` segments and deeply nested paths |
| JSON escape | `json_escape` with special chars (newlines embedded in variable values) |
| Path traversal | Storage `path` field set to `../../../../etc/passwd` |

---

## Pass 2 — 2026 SOTA & Best-Practice Check

### Status: Codebase is broadly modern

The codebase already follows current bash best practices:

- `set -euo pipefail` at top of entry point ✓
- `[[ ]]` used consistently (never `[ ]`) ✓
- `printf` used throughout instead of `echo` ✓
- `read -r` used correctly ✓
- `local` declarations in all functions ✓
- `shellcheck` annotations used appropriately ✓
- `declare -gA` for global associative array in function (bash 4.2+) ✓
- IFS-safe `read -r -a` array splitting ✓
- `--one-file-system` on `rm -rf` during wipe ✓

### Informational: `printf "%b"` in `run_or_dry_write`

**File:** `lib/helpers.bash:289`

```bash
printf "%b" "$content" > "$file"
```

`%b` interprets backslash escape sequences (`\n`, `\t`, `\0`, etc.). All current callers pass hardcoded literal strings (e.g., `"user:root@pam:1:0:::::\nacl:...\n"`), so this is intentional and safe. However, if any future caller were to pass user-controlled content, `%b` would process escape sequences. A heredoc redirect would be safer by design but would require refactoring the function signature.

**Not fixed:** Safe with current callers; documented as a design fragility.

### Informational: `json_escape` newline limitation

**File:** `lib/helpers.bash:361`

```bash
json_escape() {
  sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r/\\r/g; s/\n/\\n/g; s/[[:cntrl:]]/ /g'
}
```

The `s/\n/\\n/g` substitution has no effect in standard sed because sed operates line-by-line and the newline was already consumed as a line delimiter. In practice, JSON values emitted are from bash variables that don't contain embedded newlines in these contexts, so this is not an active bug.

**Not fixed:** Not a current issue; would require `sed -z` or `tr` to address properly.

---

## Pass 3 — Documentation Deduplication

### FIXED: Testing commands duplicated between README.md and docs/testing.md

**Files:** `README.md`, `docs/testing.md`

The "Testing" section in `README.md` reproduced the exact same five commands already present in `docs/testing.md` under "Local Checks". With the README already linking to `docs/testing.md` in the Documentation section, this was pure duplication.

**Fix:** Replaced the README "Testing" block with a single-line reference to `docs/testing.md`.

### FIXED: docs/testing.md security section didn't reflect full blacklist

**File:** `docs/testing.md`

The security note listed the blacklisted paths but was out of date after the expanded blacklist (see Pass 5). Updated to reflect all blocked paths.

### Verified: No other significant duplication found

- `docs/cli.md` vs `README.md` quickstart: README covers quickstart use-cases; `docs/cli.md` is the full reference. Not duplication.
- `docs/json-schema.md` and JSON output section in README: README only links to the schema doc, no inline duplication.
- `docs/release-checklist.md` and `docs/release-notes-draft.md`: different purposes.
- Exit codes appear in README and `docs/cli.md` (helptext) — minimal overlap, both appropriate for their audience.

---

## Pass 4 — Security Review

### FIXED: `VANILLA_ORIGINS` regex injection

**File:** `lib/audit.bash`, `audit_third_party_by_origin`

**Before:**
```bash
vanilla_origins_re="${vanilla_origins_re// /|}"
vanilla_origins_re="$(printf "%s" "$vanilla_origins_re" | sed 's/[.*+?\[\]()^$\\{}]/\\&/g')"
```

The space-to-`|` replacement ran *before* the sed escaping. If `VANILLA_ORIGINS` contained a literal `|` (e.g., `VANILLA_ORIGINS="Debian Proxmox|malicious"`), the `|` would survive the sed pass (it was not in the escape character class) and inject an extra alternation branch into the `grep -E` pattern. An attacker with env-var control could add arbitrary pattern branches.

**Fix:** Rewrote to escape each whitespace-separated token individually before joining with `|`. Added `|` to the sed escape class.

```bash
read -r -a _origins_arr <<< "$VANILLA_ORIGINS"
[[ "$VANILLA_INCLUDE_CEPH" == "1" ]] && _origins_arr+=("Ceph")
local _vo
for _vo in "${_origins_arr[@]}"; do
  [[ -z "$_vo" ]] && continue
  _vo="$(printf "%s" "$_vo" | sed 's/[.*+?\[\]()^$\\{}|]/\\&/g')"
  vanilla_origins_re="${vanilla_origins_re:+${vanilla_origins_re}|}${_vo}"
done
```

---

### Informational: TOCTOU race between log-file symlink check and creation

**File:** `lib/cli_preflight.bash:322-324`, `lib/cli_preflight.bash:345-365`

`validate_log_file_path` checks `[[ -L "$LOG_FILE" ]]` for symlinks, but the actual `touch "$LOG_FILE"` happens later in `setup_runtime`. A concurrent process could replace the path with a symlink in the window between validation and creation. For a root-only execute-mode tool this is low-severity (a local attacker with /run write access already has root equivalent), but it is a classic TOCTOU pattern.

**Not fixed:** Fully resolving this in bash requires `set -o noclobber` + fd-level checks, which would significantly complicate the code. Risk is acceptable for the threat model.

---

### Verified: No command injection via CLI args

All user-supplied values (`--include-storage`, `--exclude-storage`, storage IDs, log/report file paths) are used only in:
- String comparisons (`[[ "$x" == "$id" ]]`)
- Path existence/attribute checks
- Array membership tests

None are interpolated into unquoted command positions. ✓

---

### Verified: Storage path traversal protection

Storage `path` values from `storage.cfg` must pass through `is_local_dir_path_simple`, which:
1. Requires the path to be an existing directory (`-d`)
2. Resolves canonical path with `safe_realpath`
3. Verifies the canonical path is under `ALLOWED_DIR_STORAGE_BASE`

And during execution, `execute_wipe_dirs` re-verifies each subdirectory is contained within `base_canon`. A path like `../../../../etc/passwd` would fail the `-d` check (not a directory) and in any case the canonical path would not be under `/var/lib/vz`. ✓

---

### Verified: `csv_to_array` nameref injection protection

**File:** `lib/helpers.bash:207-231`

The function explicitly whitelists the allowed nameref target names:
```bash
case "$out_name" in
  arr|scope_ids) ;;
  *) exit "$EXIT_RUNTIME" ;;
esac
```
This prevents an attacker from passing a crafted variable name to `declare -n` that could cause variable aliasing. ✓

---

### Verified: `PVE_ETC` path pin

`validate_config_paths` resolves `PVE_ETC` and requires the canonical result to be exactly `/etc/pve`. Setting `PVE_ETC` to anything else causes an immediate preflight exit. ✓

---

## Pass 5 — Common Attack Vectors & OWASP Hardening

### FIXED: `ensure_safety_guards` blacklist incomplete

**File:** `lib/cli_preflight.bash`

The original blacklist for `ALLOWED_DIR_STORAGE_BASE` covered `/`, `/etc`, `/root`, `/var`, `/usr`, `/home`, `/opt` (with and without trailing slash). Missing were `/proc`, `/sys`, `/boot`, `/dev`, `/run`, `/tmp`, `/srv`, and critically `/etc/pve` itself.

While the allowlist check (`is_local_dir_path_simple`) provides the primary protection by requiring the path to be under `ALLOWED_DIR_STORAGE_BASE`, the blacklist is a defense-in-depth against misconfiguration.

**Fix:** Expanded the blacklist to include all system directory roots and `/etc/pve`.

---

### Verified: Path traversal via `is_safe_subdir`

**File:** `lib/helpers.bash:166-173`

```bash
is_safe_subdir() {
  [[ -z "$sub" ]] && return 1
  [[ "$sub" == *".."* ]] && return 1
  [[ "$sub" == /* ]] && return 1
  case "$sub" in *[*?]*|*'*'*) return 1 ;; esac
}
```

Subdirectory names are checked for: empty, containing `..`, being absolute paths, and containing glob metacharacters. Double-checked: the `execute_wipe_dirs` path containment check (`dir_canon != base_canon/*`) provides a second layer even if `is_safe_subdir` were somehow bypassed. ✓

---

### Verified: `--dry-run` / `--plan` cannot be bypassed silently

Both modes work by:
- `--plan`: sets `EXEC_MODE="plan"` and `CONFIRM=false`; `main()` exits at `EXIT_OK` before reaching `run_execution_phases`
- `--dry-run`: `run_or_dry` returns early for every destructive operation
- No code path reaches destructive operations without going through `run_execution_phases` → `ensure_safety_guards` → individual execution functions

The `--plan does not call destructive commands` bats test validates this. ✓

---

### Verified: `LVM_WIPE_EXTRA_PATTERN` cannot match protected volumes

**File:** `lib/audit.bash:192-198`

Protected LVs (root, swap, data, thinpool) are skipped via `is_protected_lv` before the extra pattern is evaluated. A glob of `*` is explicitly blocked by the `!= "*"` guard. ✓

---

### Verified: Lock file prevents concurrent execute-mode runs

**File:** `lib/cli_preflight.bash:382-394`

```bash
exec 9>"$lockfile"
if ! flock -n 9; then
  die_preflight "Another instance is already running"
fi
```

`flock -n` is non-blocking and atomic at the kernel level. The lock is on a file descriptor to `/run/pve-soft-reset.lock` (only writable by root). ✓

---

## Summary of Changes (Run 1)

| # | Severity | Area | Change |
|---|----------|------|--------|
| 1 | Medium | Logic | Removed redundant `collect_storage_ids` in `run_audit_pipeline` |
| 2 | Medium | Logic/API | Added `ceph_found`+`ssh_keys_found` to JSON output; updated schema doc |
| 3 | Medium | Security | Fixed `VANILLA_ORIGINS` regex injection — per-token escaping before alternation join |
| 4 | Low | Security | Expanded `ensure_safety_guards` blacklist with 7 additional system paths |
| 5 | Low | Docs | Removed duplicate testing commands from README; added reference to docs/testing.md |
| 6 | Low | Docs | Updated docs/testing.md security note to reflect expanded blacklist and VANILLA_ORIGINS fix |

---

## Run 2 — Additional Findings (2026-03-17)

### FIXED: `execute_reset_pve_config` failure not counted in FAILURE_COUNT

**File:** `lib/execute.bash:233-236`

When `resolve_node_name` returns an invalid hostname (empty string or containing path-unsafe characters), `execute_reset_pve_config` logged an error and returned 1. However, the `FAILURE_COUNT` global was not incremented, and the caller uses `|| true` to prevent script death. The result was that a failed PVE config reset would report 0 failures in the final summary, giving a false "clean" exit.

**Fix:** Added `((FAILURE_COUNT+=1))` before `return 1`.

---

### FIXED: Dead if/else branch in `validate_config_paths`

**File:** `lib/cli_preflight.bash:128-132`

```bash
# Before — both branches identical:
if [[ -f "$STORAGE_CFG" ]]; then
  storage_cfg_canon="$(safe_realpath "$STORAGE_CFG")"
else
  storage_cfg_canon="$(safe_realpath "$STORAGE_CFG")"
fi
```

Both the `if` (file exists) and `else` (file missing) branches called `safe_realpath "$STORAGE_CFG"` with the same arguments. This is a no-op conditional — likely a leftover from a prior refactor that intended to handle the non-existent file case differently (e.g., using `realpath -m` only when the file doesn't exist). Since `safe_realpath` already handles both cases internally (`realpath -m` first, then plain `realpath`), the branch distinction is meaningless.

**Fix:** Collapsed to a single unconditional `storage_cfg_canon="$(safe_realpath "$STORAGE_CFG")"`.

---

### FIXED: CHANGELOG.md and release-notes-draft.md not updated with run 1 fixes

**Files:** `CHANGELOG.md`, `docs/release-notes-draft.md`

Neither document reflected the 6 fixes applied in run 1. The CHANGELOG `[1.2.0]` entry and release notes draft lacked the `Fixed` section entirely.

**Fix:** Added `### Fixed` section to CHANGELOG with all 4 code-level fixes. Added `## Bug Fixes` section to release-notes-draft with the same content. Updated both `## Safety and Hardening` sections with the VANILLA_ORIGINS and blacklist entries.

---

### FIXED: `docs/audit-findings.md` absent from `release-prep-inventory.md`

**File:** `docs/release-prep-inventory.md`

The inventory listed all documentation artifacts but omitted `docs/audit-findings.md`, which was created during run 1 and documents the full audit trail.

**Fix:** Added `docs/audit-findings.md` to the inventory's documentation artifacts list.

---

### Informational: `check_cluster_quorum` edge case — pvecm available but standalone node

**File:** `lib/cli_preflight.bash:157-165`

```bash
if command -v pvecm >/dev/null 2>&1 && pvecm status >/dev/null 2>&1; then
```

If `pvecm` is installed but the node is not in a cluster (e.g., a freshly converted node where pvecm is present but uninitialized), `pvecm status` may exit non-zero, making the outer `&&` false. The function returns 0, allowing config resets to proceed. This is the correct safe-fail behavior (treat "can't determine quorum" as "allow") but is worth documenting explicitly.

**Not fixed:** Intended behavior; documented.

---

## Summary of Changes (Run 2)

| # | Severity | Area | Change |
|---|----------|------|--------|
| 7 | Medium | Logic | `execute_reset_pve_config`: increment FAILURE_COUNT on invalid-hostname early return |
| 8 | Low | Logic | `validate_config_paths`: remove dead if/else duplicate branch for STORAGE_CFG |
| 9 | Low | Docs | CHANGELOG.md: added `### Fixed` section with all code-level fixes from both runs |
| 10 | Low | Docs | release-notes-draft.md: added `## Bug Fixes` section; updated hardening section |
| 11 | Low | Docs | release-prep-inventory.md: added `docs/audit-findings.md` to artifacts list |

---

## Run 3 — Additional Findings (2026-03-17)

### FIXED: `scripts/check-doc-links.sh` uses `rg` (ripgrep) not installed in CI

**File:** `scripts/check-doc-links.sh:31`

```bash
# Before:
done < <(rg -o --no-filename 'docs/[A-Za-z0-9._/-]+' "$README_FILE" | sort -u)
```

The CI workflow (`.github/workflows/ci.yml`) installs `shellcheck bats jq` but **not** `ripgrep`. The docs link check step (`./scripts/check-doc-links.sh`) would therefore fail on CI with `rg: command not found`. The script also would not run for contributors on macOS without Homebrew ripgrep.

**Fix:** Replaced `rg -o --no-filename` with `grep -Eo`, which is available on all GNU and BSD grep implementations (Linux and macOS) and requires no additional dependencies. The regex pattern is identical.

```bash
# After:
done < <(grep -Eo 'docs/[A-Za-z0-9._/-]+' "$README_FILE" | sort -u)
```

---

### Verified: `normalize_abs_path_lexical` handles `..` traversal correctly

**File:** `lib/cli_preflight.bash:265-292`

The function uses `unset "stack[$(( ${#stack[@]} - 1 ))]"` to pop. This is safe because:
1. The guard `[[ ${#stack[@]} -gt 0 ]]` prevents underflow
2. Push (`stack+=`) and pop (`unset last`) are always interleaved on a local variable — the array stays dense, so `${#stack[@]}-1` is always the correct last index
3. The empty-stack case (`out=""`) correctly falls through to `out="/"` ✓

---

### Verified: `list_lvs_to_remove` LVM entry joining is correct

**File:** `lib/audit.bash:202-207`

```bash
joined="$(printf "%s$SEP" "${to_remove[@]}")"
joined="${joined%"$SEP"}"
```

Constructs a trailing-SEP-stripped join correctly. The WIPE_LVM_ENTRIES format (`id${SEP}vg${SEP}lv1${SEP}lv2...`) is consumed correctly by both `_execute_wipe_lvm_entry` (splits on first two SEPs) and `add_sep_minus_one_to_var` (counts SEPs - 1 = LV count). ✓

---

### Verified: `for_each_sep_entry` + empty arrays safe under `set -u`

In bash 4.4+, `"${arr[@]}"` on an empty array produces zero words without triggering the `set -u` "unbound variable" error. All callers of `for_each_sep_entry` correctly handle the case where the array is empty (loop body simply never executes). ✓

---

## Summary of Changes (Run 3)

| # | Severity | Area | Change |
|---|----------|------|--------|
| 12 | High | CI/Portability | `check-doc-links.sh`: replace `rg` with `grep -Eo` — CI was missing ripgrep dependency |
