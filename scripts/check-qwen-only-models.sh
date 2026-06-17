#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
blocked_family="l""lama"
pattern="\\b${blocked_family}([0-9]|[-_.:]|\\b)|meta-${blocked_family}"

if rg -nPi "$pattern" --glob '!.git/**' "$repo_root"; then
  echo "fail: blocked model-family reference found" >&2
  exit 1
fi

echo "ok: no blocked model-family references found"
