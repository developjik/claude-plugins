#!/usr/bin/env bash
# state-store.sh — state-machine state persistence helpers

set -euo pipefail

state_store_init_state_machine() {
  local project_root="${1:-}"
  local feature_slug="${2:-}"

  local engine_path
  engine_path=$(engine_dir "$project_root")
  local snapshots_path
  snapshots_path=$(snapshots_dir "$project_root")

  mkdir -p "$engine_path" "$snapshots_path"

  local state_path
  state_path=$(state_file "$project_root")

  if [[ ! -f "$state_path" ]]; then
    local timestamp
    timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

    cat > "$state_path" << EOF
{
  "version": "1.0",
  "feature_slug": "$feature_slug",
  "phase": "clarify",
  "previous_phase": null,
  "status": "active",
  "entered_at": "$timestamp",
  "last_transition_at": "$timestamp",
  "actor": null,
  "iteration_count": 0,
  "check_results": null,
  "snapshots": [],
  "metadata": {
    "created_at": "$timestamp",
    "updated_at": "$timestamp"
  }
}
EOF

    state_store_log_transition "$project_root" "init" "null" "clarify" "State machine initialized"
    echo "✅ State machine initialized for: $feature_slug"
  else
    echo "ℹ️  State machine already exists"
  fi
}

state_store_jq_update() {
  local project_root="${1:-}"
  shift

  local state_path
  state_path=$(state_file "$project_root")

  if [[ ! -f "$state_path" ]] || ! command -v jq > /dev/null 2>&1; then
    return 1
  fi

  local tmp="${state_path}.tmp"
  jq "$@" "$state_path" > "$tmp" && mv "$tmp" "$state_path"
}

state_store_get_state() {
  local project_root="${1:-}"
  local state_path
  state_path=$(state_file "$project_root")

  if [[ -f "$state_path" ]]; then
    cat "$state_path"
  else
    echo '{"error": "state_not_initialized", "phase": null}'
  fi
}

state_store_get_current_phase() {
  local project_root="${1:-}"
  state_store_get_state "$project_root" | jq -r '.phase // "unknown"'
}

state_store_get_feature_slug() {
  local project_root="${1:-}"
  state_store_get_state "$project_root" | jq -r '.feature_slug // empty'
}

state_store_set_feature_slug() {
  local project_root="${1:-}"
  local feature_slug="${2:-}"

  if [[ ! -f "$(state_file "$project_root")" ]]; then
    state_store_init_state_machine "$project_root" "$feature_slug" > /dev/null 2>&1
  fi

  local timestamp
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  state_store_jq_update "$project_root" \
    --arg feature "$feature_slug" \
    --arg ts "$timestamp" \
    '.feature_slug = $feature |
     .metadata.updated_at = $ts' || return 1

  sync_runtime_cache "$project_root" > /dev/null 2>&1 || true
  printf '%s\n' "$feature_slug"
}

state_store_log_transition() {
  local project_root="${1:-}"
  local event="${2:-}"
  local from="${3:-}"
  local to="${4:-}"
  local reason="${5:-}"

  local transitions_path
  transitions_path=$(transitions_file "$project_root")
  mkdir -p "$(dirname "$transitions_path")"

  local entry
  entry=$(jq -cn \
    --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    --arg event "$event" \
    --arg from "$from" \
    --arg to "$to" \
    --arg reason "$reason" \
    '{timestamp: $ts, event: $event, from: $from, to: $to, reason: $reason}')

  echo "$entry" >> "$transitions_path"
}

state_store_get_transition_history() {
  local project_root="${1:-}"
  local limit="${2:-10}"
  local transitions_path
  transitions_path=$(transitions_file "$project_root")

  if [[ ! -f "$transitions_path" ]]; then
    echo "[]"
    return 0
  fi

  tail -n "$limit" "$transitions_path" | jq -s '. | reverse'
}

state_store_save_check_results() {
  local project_root="${1:-}"
  local match_rate="${2:-0}"
  local details="${3:-"{}"}"

  local state_path
  state_path=$(state_file "$project_root")

  if command -v jq > /dev/null 2>&1; then
    local tmp="${state_path}.tmp"
    jq --argjson rate "$match_rate" \
      --argjson details "$details" \
      '.check_results = {match_rate: $rate, details: $details}' \
      "$state_path" > "$tmp" && mv "$tmp" "$state_path"
  fi
}
