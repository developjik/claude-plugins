#!/usr/bin/env bash
# phase-cache.sh — state-machine cache synchronization helpers

set -euo pipefail

phase_cache_iso8601_to_epoch() {
  local timestamp="${1:-}"

  if [[ -z "$timestamp" ]]; then
    return 1
  fi

  if date -j -f "%Y-%m-%dT%H:%M:%SZ" "$timestamp" "+%s" > /dev/null 2>&1; then
    date -j -f "%Y-%m-%dT%H:%M:%SZ" "$timestamp" "+%s"
    return 0
  fi

  if date -d "$timestamp" "+%s" > /dev/null 2>&1; then
    date -d "$timestamp" "+%s"
    return 0
  fi

  return 1
}

phase_cache_sync_runtime_cache() {
  local project_root="${1:-}"
  local state
  state=$(state_store_get_state "$project_root")

  if echo "$state" | jq -e '.error' > /dev/null 2>&1; then
    return 0
  fi

  local state_dir phase_file feature_file agent_file phase_start_file
  if declare -f harness_state_dir_from_root > /dev/null 2>&1; then
    state_dir=$(harness_state_dir_from_root "$project_root")
    phase_file=$(harness_phase_file "$project_root")
    feature_file=$(harness_current_feature_file "$project_root")
    agent_file=$(harness_current_agent_file "$project_root")
    phase_start_file=$(harness_phase_start_file "$project_root")
  else
    state_dir="${project_root}/.harness/state"
    phase_file="${state_dir}/pdca-phase.txt"
    feature_file="${state_dir}/current-feature.txt"
    agent_file="${state_dir}/current-agent.txt"
    phase_start_file="${state_dir}/phase-start-time.txt"
  fi

  mkdir -p "$state_dir"

  local phase feature_slug actor entered_at entered_at_epoch
  phase=$(echo "$state" | jq -r '.phase // "idle"')
  feature_slug=$(echo "$state" | jq -r '.feature_slug // empty')
  actor=$(echo "$state" | jq -r '.actor // empty')
  entered_at=$(echo "$state" | jq -r '.entered_at // empty')
  entered_at_epoch=$(phase_cache_iso8601_to_epoch "$entered_at" 2> /dev/null || true)

  printf '%s\n' "${phase:-idle}" > "$phase_file"
  printf '%s\n' "$feature_slug" > "$feature_file"
  printf '%s\n' "$actor" > "$agent_file"

  if [[ -n "$entered_at_epoch" ]]; then
    printf '%s\n' "$entered_at_epoch" > "$phase_start_file"
  elif [[ ! -f "$phase_start_file" ]]; then
    printf '%s\n' "$(date +%s)" > "$phase_start_file"
  fi
}

phase_cache_init_or_repair_state_machine() {
  local project_root="${1:-}"
  local feature_slug="${2:-}"

  if [[ ! -f "$(state_file "$project_root")" ]]; then
    state_store_init_state_machine "$project_root" "$feature_slug" > /dev/null 2>&1
  fi

  if [[ -n "$feature_slug" ]]; then
    local current_feature
    current_feature=$(state_store_get_feature_slug "$project_root" 2> /dev/null || true)
    if [[ "$current_feature" != "$feature_slug" ]]; then
      state_store_set_feature_slug "$project_root" "$feature_slug" > /dev/null 2>&1 || true
    fi
  fi

  phase_cache_sync_runtime_cache "$project_root" > /dev/null 2>&1 || true
}

phase_cache_record_runtime_phase_state() {
  local project_root="${1:-}"
  local phase="${2:-}"
  local actor="${3:-claude}"
  local reason="${4:-runtime_phase_sync}"

  case "$phase" in
    clarify | plan | design | implement | check | wrapup | complete) ;;
    *) return 0 ;;
  esac

  phase_cache_init_or_repair_state_machine "$project_root" "$(state_store_get_feature_slug "$project_root" 2> /dev/null || true)" > /dev/null 2>&1 || true

  local current_phase timestamp
  current_phase=$(state_store_get_current_phase "$project_root" 2> /dev/null || echo "unknown")
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  state_store_jq_update "$project_root" \
    --arg phase "$phase" \
    --arg actor "$actor" \
    --arg ts "$timestamp" \
    '.previous_phase = (if .phase == $phase then .previous_phase else .phase end) |
     .phase = $phase |
     .entered_at = $ts |
     .last_transition_at = $ts |
     .actor = $actor |
     .metadata.updated_at = $ts' || return 1

  if [[ "$current_phase" != "$phase" ]]; then
    state_store_log_transition "$project_root" "runtime_phase_sync" "$current_phase" "$phase" "$reason"
  fi

  phase_cache_sync_runtime_cache "$project_root" > /dev/null 2>&1 || true
  printf '%s\n' "$phase"
}
