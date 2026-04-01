#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

for file in hooks/*.sh hooks/lib/*.sh scripts/*.sh; do
  bash -n "$file"
done

echo "shell syntax check passed"
