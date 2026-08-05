#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Installs the repo's git hooks into .git/hooks.
set -eu
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/scripts/git-hooks"

# Locate the git repository (project root or nested manager/).
GIT_DIR=""
for candidate in "$ROOT" "$ROOT/manager"; do
  if git -C "$candidate" rev-parse --git-dir >/dev/null 2>&1; then
    GIT_DIR="$(git -C "$candidate" rev-parse --absolute-git-dir)"
    break
  fi
done

if [[ -z "$GIT_DIR" ]]; then
  echo "ERROR: no git repository found under $ROOT" >&2
  exit 1
fi

mkdir -p "$GIT_DIR/hooks"
for hook in "$SRC"/*; do
  name="$(basename "$hook")"
  cp "$hook" "$GIT_DIR/hooks/$name"
  chmod +x "$GIT_DIR/hooks/$name"
  echo "Installed git hook into $GIT_DIR/hooks: $name"
done
echo "Git hooks installed."
