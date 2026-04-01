#!/usr/bin/env bash

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$LIB_DIR/common.sh"

CFF_REQUIRED_MCP_SERVERS=(
  atlassian
  figma
)

cff_declared_mcp_servers() {
  local project_root="$1"
  local mcp_path="$project_root/.mcp.json"

  python3 - "$mcp_path" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    data = json.load(handle)

for key in sorted(data.get("mcpServers", {}).keys()):
    print(key)
PY
}

cff_is_mcp_declared() {
  local project_root="$1"
  local server_name="$2"

  cff_declared_mcp_servers "$project_root" | grep -Fxq "$server_name"
}

require_declared_mcp_servers() {
  local project_root="$1"
  local missing=()
  local server

  for server in "${CFF_REQUIRED_MCP_SERVERS[@]}"; do
    if ! cff_is_mcp_declared "$project_root" "$server"; then
      missing+=("$server")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    printf 'missing required mcp servers: %s\n' "${missing[*]}" >&2
    return 1
  fi

  return 0
}

