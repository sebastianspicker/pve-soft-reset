#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
README_FILE="$ROOT_DIR/README.md"

required_docs=(
  "docs/cli.md"
  "docs/json-schema.md"
  "docs/testing.md"
)

for doc in "${required_docs[@]}"; do
  if ! grep -q "($doc)" "$README_FILE"; then
    echo "Missing required README link: $doc" >&2
    exit 1
  fi
  if [[ ! -f "$ROOT_DIR/$doc" ]]; then
    echo "Required documentation file missing: $doc" >&2
    exit 1
  fi
done

# Any docs/* reference in README must point to an existing file.
while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  if [[ ! -f "$ROOT_DIR/$match" ]]; then
    echo "README references non-existent documentation artifact: $match" >&2
    exit 1
  fi
done < <(rg -o --no-filename 'docs/[A-Za-z0-9._/-]+' "$README_FILE" | sort -u)

echo "Documentation link checks passed"
