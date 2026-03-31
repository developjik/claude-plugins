#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MODE="${1:---check}"

if [[ "$MODE" != "--check" && "$MODE" != "--write" ]]; then
  echo "Usage: bash scripts/lint-shell.sh [--check|--write]"
  exit 1
fi

FOUND_PLUGIN=0

for plugin_dir in plugins/*; do
  [[ -d "$plugin_dir" ]] || continue
  FOUND_PLUGIN=1

  if [[ -f "${plugin_dir}/scripts/lint-shell.sh" ]]; then
    echo "Running shell lint for $(basename "$plugin_dir")..."
    bash "${plugin_dir}/scripts/lint-shell.sh" "$MODE"
  else
    echo "Skipping $(basename "$plugin_dir"): scripts/lint-shell.sh not found"
  fi
done

if [[ "$FOUND_PLUGIN" -eq 0 ]]; then
  echo "No plugins found under plugins/"
fi
