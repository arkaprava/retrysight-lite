#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Scans tracked source files for hardcoded RetrySight Lite secrets:
#   adm_<64 hex>  admin tokens
#   asl_<64 hex>  agent API keys
#
# Usage:
#   scripts/scan-secrets.sh            scan tracked files in the repo
#   scripts/scan-secrets.sh --all      scan tracked + untracked files
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Locate the git repository. The project layout may keep the repo at the
# project root or nested (e.g. manager/).
REPO_ROOT=""
for candidate in "$ROOT" "$ROOT/manager"; do
  if git -C "$candidate" rev-parse --absolute-git-dir >/dev/null 2>&1; then
    REPO_ROOT="$(git -C "$candidate" rev-parse --show-toplevel 2>/dev/null)"
    break
  fi
done

if [[ -z "$REPO_ROOT" ]]; then
  echo "ERROR: no git repository found under $ROOT" >&2
  exit 1
fi
export REPO_ROOT

INCLUDE_UNTRACKED=0
if [[ "${1:-}" == "--all" ]]; then
  INCLUDE_UNTRACKED=1
fi

# Token patterns: prefix + at least 16 hex chars (real tokens are 64 hex).
PATTERNS='adm_[0-9a-f]{16,}|asl_[0-9a-f]{16,}'

if [[ "$INCLUDE_UNTRACKED" -eq 1 ]]; then
  FILES=$(git -C "$REPO_ROOT" ls-files --cached --others --exclude-standard -z | tr '\0' '\n')
else
  FILES=$(git -C "$REPO_ROOT" ls-files -z | tr '\0' '\n')
fi

# shellcheck disable=SC2086
HITS=$(printf '%s\n' "$FILES" \
  | grep -v -E '^(node_modules/|dist/|dist-pkg/|release/|data/|app/build/|app/\.dart_tool/)' \
  | grep -v -E '\.(png|jpg|jpeg|gif|ico|pdf|zip|tar|gz|db|db-wal|db-shm)$' \
  | xargs -I{} sh -c 'grep -nH -E "'"$PATTERNS"'" "$REPO_ROOT/{}" 2>/dev/null' \
)

if [[ -n "$HITS" ]]; then
  echo "ERROR: hardcoded RetrySight Lite secret(s) found:" >&2
  echo "$HITS" >&2
  echo "Remove the tokens (use env vars or the data/ dir) before committing." >&2
  exit 1
fi

echo "OK: no hardcoded secrets found."
exit 0
