#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib/dependency-check.sh
source "$ROOT_DIR/hooks/lib/dependency-check.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

cat > "$tmp_dir/.mcp.json" <<'JSON'
{
  "mcpServers": {
    "atlassian": {},
    "figma": {}
  }
}
JSON

require_declared_mcp_servers "$tmp_dir" || fail "expected required servers check to pass"

cat > "$tmp_dir/.mcp.json" <<'JSON'
{
  "mcpServers": {
    "atlassian": {}
  }
}
JSON

if require_declared_mcp_servers "$tmp_dir" >/dev/null 2>&1; then
  fail "expected required servers check to fail when figma is missing"
fi

echo "dependency-check.test.sh passed"

