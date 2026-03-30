#!/usr/bin/env bash
# browser-state.sh — browser-controller state helpers

set -euo pipefail

browser_state_dir() {
  local project_root="${1:-$(pwd)}"
  echo "${project_root}/${BROWSER_STATE_SUBDIR}"
}

browser_session_file() {
  local project_root="${1:-$(pwd)}"
  echo "$(browser_state_dir "$project_root")/session.json"
}

browser_ws_endpoint_file() {
  local project_root="${1:-$(pwd)}"
  echo "$(browser_state_dir "$project_root")/ws-endpoint.txt"
}

browser_runtime_script_file() {
  local project_root="${1:-$(pwd)}"
  local script_name="${2:-runtime.js}"
  echo "$(browser_state_dir "$project_root")/${script_name}"
}

browser_screenshot_dir() {
  local project_root="${1:-$(pwd)}"
  echo "$(browser_state_dir "$project_root")/screenshots"
}

# 브라우저 상태 초기화
_init_browser_state() {
  local project_root="${1:-$(pwd)}"
  local state_dir session_file
  state_dir=$(browser_state_dir "$project_root")
  session_file=$(browser_session_file "$project_root")

  mkdir -p "$state_dir"

  if [[ ! -f "$session_file" ]]; then
    cat > "$session_file" << 'EOF'
{
  "connected": false,
  "mode": "headless",
  "browser": null,
  "page": null,
  "url": null,
  "last_action": null,
  "actions_count": 0
}
EOF
  fi
}

# 상태 업데이트
_update_browser_state() {
  local project_root="${1:-$(pwd)}"
  local key="${2:-}"
  local value="${3:-}"

  _init_browser_state "$project_root"

  local state_file tmp_file
  state_file=$(browser_session_file "$project_root")
  tmp_file="${state_file}.tmp"

  if [[ -n "$key" ]] && command -v jq &> /dev/null; then
    jq --arg key "$key" --argjson val "$value" '.[$key] = $val' "$state_file" > "$tmp_file" \
      && mv "$tmp_file" "$state_file"
  fi
}

# 상태 조회
_get_browser_state() {
  local project_root="${1:-$(pwd)}"
  local key="${2:-}"

  _init_browser_state "$project_root"

  local state_file
  state_file=$(browser_session_file "$project_root")

  if [[ -n "$key" ]]; then
    jq -r ".$key // null" "$state_file" 2> /dev/null || echo "null"
  else
    cat "$state_file"
  fi
}

# browser_status — 현재 브라우저 상태
# Usage: browser_status [project_root]
browser_status() {
  local project_root="${1:-$(pwd)}"

  _init_browser_state "$project_root"
  cat "$(browser_session_file "$project_root")"
}

# browser_is_connected — 연결 여부 확인
# Usage: browser_is_connected [project_root]
browser_is_connected() {
  local project_root="${1:-$(pwd)}"
  local connected

  connected=$(_get_browser_state "$project_root" "connected")

  [[ "$connected" == "true" ]]
}
