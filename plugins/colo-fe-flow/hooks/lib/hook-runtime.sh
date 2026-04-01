#!/usr/bin/env bash

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$LIB_DIR/common.sh"
# shellcheck source=./state.sh
source "$LIB_DIR/state.sh"
# shellcheck source=./log.sh
source "$LIB_DIR/log.sh"

cff_hook_json_query() {
  local payload="$1"
  local json_path="$2"
  local default_value="${3-__CFF_NO_DEFAULT__}"

  python3 - "$payload" "$json_path" "$default_value" <<'PY'
import json
import sys

payload, json_path, default_value = sys.argv[1:4]
sentinel = "__CFF_NO_DEFAULT__"

if not payload.strip():
    data = {}
else:
    data = json.loads(payload)

current = data
try:
    for part in json_path.split("."):
        if isinstance(current, list):
            current = current[int(part)]
        else:
            current = current[part]
except (KeyError, IndexError, ValueError, TypeError):
    if default_value != sentinel:
        print(default_value)
        raise SystemExit(0)
    raise

if current is None:
    print("null")
elif isinstance(current, bool):
    print("true" if current else "false")
elif isinstance(current, (dict, list)):
    print(json.dumps(current, ensure_ascii=True, separators=(",", ":")))
else:
    print(str(current))
PY
}

cff_hook_project_root() {
  local payload="$1"
  local cwd

  if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
    printf '%s\n' "$CLAUDE_PROJECT_DIR"
    return 0
  fi

  cwd="$(cff_hook_json_query "$payload" "cwd" "")"
  if [[ -n "$cwd" && "$cwd" != "null" ]]; then
    printf '%s\n' "$cwd"
  else
    pwd
  fi
}

cff_hook_tool_name() {
  local payload="$1"
  local value

  value="$(cff_hook_json_query "$payload" "tool_name" "")"
  if [[ -n "$value" ]]; then
    printf '%s\n' "$value"
    return 0
  fi
  cff_hook_json_query "$payload" "tool" ""
}

cff_hook_tool_file_path() {
  local payload="$1"
  local value

  value="$(cff_hook_json_query "$payload" "tool_input.file_path" "")"
  if [[ -n "$value" ]]; then
    printf '%s\n' "$value"
    return 0
  fi

  value="$(cff_hook_json_query "$payload" "tool_input.path" "")"
  if [[ -n "$value" ]]; then
    printf '%s\n' "$value"
    return 0
  fi

  value="$(cff_hook_json_query "$payload" "input.file_path" "")"
  if [[ -n "$value" ]]; then
    printf '%s\n' "$value"
    return 0
  fi

  cff_hook_json_query "$payload" "input.path" ""
}

cff_hook_tool_command() {
  local payload="$1"
  local value

  value="$(cff_hook_json_query "$payload" "tool_input.command" "")"
  if [[ -n "$value" ]]; then
    printf '%s\n' "$value"
    return 0
  fi

  cff_hook_json_query "$payload" "input.command" ""
}

cff_hook_agent_name() {
  local payload="$1"
  local value

  value="$(cff_hook_json_query "$payload" "agent_name" "")"
  if [[ -n "$value" ]]; then
    printf '%s\n' "$value"
    return 0
  fi

  cff_hook_json_query "$payload" "agent" ""
}

cff_hook_absolute_path() {
  local project_root="$1"
  local file_path="$2"

  if [[ "$file_path" = /* ]]; then
    printf '%s\n' "$file_path"
  else
    printf '%s/%s\n' "$project_root" "$file_path"
  fi
}

cff_hook_infer_ticket_and_artifact() {
  local file_path="$1"

  if [[ "$file_path" =~ docs/specs/([A-Z][A-Z0-9]+-[0-9]+)/([a-z-]+)\.md$ ]]; then
    printf '%s|%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    return 0
  fi

  if [[ "$file_path" =~ docs/specs/([A-Z][A-Z0-9]+-[0-9]+)/tasks\.json$ ]]; then
    printf '%s|tasks\n' "${BASH_REMATCH[1]}"
    return 0
  fi

  printf '|\n'
}

cff_hook_emit_block() {
  local reason="$1"

  python3 - "$reason" <<'PY'
import json
import sys
print(json.dumps({"decision": "block", "reason": sys.argv[1]}, ensure_ascii=True))
PY
}
