# GitHub Audit Findings — pve-soft-reset

Generated: 2026-03-17
Scope: `README.md`, `.github/**`, `.github/workflows/ci.yml`, `CHANGELOG.md`, scripts invoked by CI

---

## Pass 1 — GitHub Polish

### FIXED: Missing MIT license badge in README.md

**File:** `README.md:3`

LICENSE file exists (MIT) but no license badge was present next to the CI badge.

**Fix:** Added `[![License: MIT](...)]` badge on the line after the CI badge.

---

### FIXED: Missing .github/CONTRIBUTING.md

**File:** `.github/CONTRIBUTING.md` (created)

No CONTRIBUTING file existed. Contributors had no guidance on local checks or PR expectations.

**Fix:** Created minimal CONTRIBUTING.md with the local check commands, PR expectations, and a link to the bug report template.

---

### FIXED: Missing .github/SECURITY.md

**File:** `.github/SECURITY.md` (created)

No security policy existed. GitHub surfaces this file in the Security tab and in the "report a vulnerability" flow.

**Fix:** Created minimal SECURITY.md covering supported versions, private reporting via GitHub Security Advisories, and response SLA.

---

### FIXED: Missing issue template

**File:** `.github/ISSUE_TEMPLATE/bug_report.md` (created)

No issue template existed. Bug reports would arrive with no structured information (version, command, environment).

**Fix:** Created a bug report template prompting for version output, command used, expected/actual behaviour, and environment details.

---

### FIXED: Missing pull request template

**File:** `.github/pull_request_template.md` (created)

No PR template existed.

**Fix:** Created minimal PR template with a summary prompt and a checklist covering the five CI gates (bash -n, shellcheck, bats, docs update, changelog entry).

---

### Verified: CHANGELOG.md follows Keep A Changelog convention

`CHANGELOG.md` has a `[1.2.0] - 2026-03-01` entry with Added/Changed/Fixed/Security sections and a compatibility note. Format is consistent. No incomplete entries found.

### Verified: docs/release-notes-draft.md has Highlights and Verification Evidence

Both sections are present. No action needed.

---

## Pass 2 — CI Quality and Correctness

### FIXED: Workflow triggers not scoped to main branch

**File:** `.github/workflows/ci.yml:3-6`

**Before:**
```yaml
on:
  push:
  pull_request:
```

The bare `push:` triggered CI on every branch push including feature branches without PRs. The bare `pull_request:` triggered on PRs targeting any base branch.

**Fix:** Scoped both triggers to `branches: [main]`.

---

### FIXED: `bash -n` only checked entry point, not lib/

**File:** `.github/workflows/ci.yml:24-25`

**Before:**
```yaml
- name: Bash syntax check
  run: bash -n pve-soft-reset.sh
```

`lib/*.bash` was not syntax-checked. A syntax error in a lib file would only be caught by shellcheck, not by the dedicated syntax step.

**Fix:** Changed to `bash -n pve-soft-reset.sh lib/*.bash`.

---

### FIXED: Two ShellCheck steps merged into one

**File:** `.github/workflows/ci.yml`

**Before:**
```yaml
- name: ShellCheck
  run: shellcheck -x pve-soft-reset.sh

- name: ShellCheck lib
  run: shellcheck -x lib/*.bash
```

Two sequential steps invoking shellcheck on the same codebase. No functional reason to split them.

**Fix:** Merged into `shellcheck -x pve-soft-reset.sh lib/*.bash`.

---

### FIXED: Runner pinned to ubuntu-24.04

**File:** `.github/workflows/ci.yml:14`

`ubuntu-latest` advances automatically when GitHub changes the default, which can silently break CI when tool versions change (e.g. bats, shellcheck). The repo uses no unusual tooling so the simplest fix is pinning to a concrete LTS.

**Fix:** Changed `ubuntu-latest` → `ubuntu-24.04`.

---

### Verified: No CD steps present

The workflow has no deploy, publish, release, push, or registry steps. Confirmed clean.

### Verified: All CI tools are explicitly installed

`shellcheck`, `bats`, and `jq` are installed via `apt-get`. `bash`, `find`, `grep`, `sort` are pre-installed on the runner. No uninstalled tool references found.

### Verified: Step order is logical

Syntax check → ShellCheck → doc link check → bats. Correct order (static analysis before runtime tests).

---

## Pass 3 — GitHub Security

### FIXED: No permissions block (overly broad default GITHUB_TOKEN)

**File:** `.github/workflows/ci.yml`

GitHub Actions defaults the `GITHUB_TOKEN` to write permissions on all scopes when no `permissions:` block is declared. A CI workflow that only reads code and runs tests needs only `contents: read`.

**Fix:** Added top-level `permissions: contents: read` to the workflow.

---

### FIXED: Missing CODEOWNERS for workflow directory

**File:** `.github/CODEOWNERS` (created)

No CODEOWNERS file existed. Without it, workflow files can be modified in a PR without requiring maintainer review — a common supply-chain attack vector (modify CI to exfiltrate secrets or run malicious code on merge).

**Fix:** Created `.github/CODEOWNERS` requiring `@sebastianspicker` review for any change under `.github/workflows/`.

---

### Verified: No script injection via github context

No workflow `run:` block interpolates `${{ github.event.* }}`, `${{ github.head_ref }}`, or any other untrusted context variable directly into shell. All `run:` steps use only static commands and shell globs. No injection surface found.

### Verified: No pull_request_target misuse

The workflow uses `pull_request:` (safe), not `pull_request_target:`. No privilege escalation risk.

### Verified: No secret exposure

No `echo`, `printf`, or debug flags that could print secrets. No secrets in `env:` default values.

### Verified: No artifact/cache poisoning surface

`actions/cache` and `actions/upload-artifact` are not used. No poisoning surface.

### Verified: Third-party actions

Only `actions/checkout@v4` is used. This is an official GitHub action pinned to a major version tag, which is acceptable per the audit policy (SHA pinning required only for non-`actions/` org). No third-party actions present.

---

## Summary

| # | Pass | File | Change |
|---|------|------|--------|
| 1 | 1 | `README.md` | Add MIT license badge |
| 2 | 1 | `.github/CONTRIBUTING.md` | Create with local check commands and PR expectations |
| 3 | 1 | `.github/SECURITY.md` | Create with vulnerability reporting policy |
| 4 | 1 | `.github/ISSUE_TEMPLATE/bug_report.md` | Create bug report template |
| 5 | 1 | `.github/pull_request_template.md` | Create PR checklist template |
| 6 | 2 | `.github/workflows/ci.yml` | Scope triggers to `branches: [main]` |
| 7 | 2 | `.github/workflows/ci.yml` | `bash -n` now covers `lib/*.bash` |
| 8 | 2 | `.github/workflows/ci.yml` | Merged two ShellCheck steps into one |
| 9 | 2 | `.github/workflows/ci.yml` | `ubuntu-latest` → `ubuntu-24.04` |
| 10 | 3 | `.github/workflows/ci.yml` | Add `permissions: contents: read` |
| 11 | 3 | `.github/CODEOWNERS` | Create — require maintainer review for workflow changes |
