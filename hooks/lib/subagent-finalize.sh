#!/usr/bin/env bash
# subagent-finalize.sh — subagent finalize/cleanup helpers

set -euo pipefail

: "${SUBAGENT_DIR:=.harness/subagents}"
: "${SUBAGENT_STATE_FILE:=state.json}"
: "${SUBAGENT_COLLECTED_RESULT_FILE:=collected-result.json}"
: "${SUBAGENT_RESULT_FILE:=result.md}"
: "${SUBAGENT_FAILURE_FILE:=failure.json}"

subagent_finalize_complete() {
  local subagent_id="${1:-}"
  local project_root="${2:-}"
  local final_status="${3:-completed}"
  local result_file="${4:-}"
  local failure_reason_input="${5:-null}"
  local subagent_dir
  subagent_dir=$(get_subagent_dir_path "$subagent_id" "$project_root")

  if [[ ! -d "$subagent_dir" ]]; then
    return 1
  fi

  local state_file="${subagent_dir}/${SUBAGENT_STATE_FILE}"
  local end_time
  end_time=$(subagent_now_utc)

  local duration_ms=0
  local start_time
  start_time=$(jq -r '.started_at // empty' "$state_file" 2> /dev/null)

  if [[ -n "$start_time" ]]; then
    local start_epoch end_epoch
    start_epoch=$(iso_timestamp_to_epoch "$start_time")
    end_epoch=$(iso_timestamp_to_epoch "$end_time")
    duration_ms=$(((end_epoch - start_epoch) * 1000))
    if [[ $duration_ms -lt 0 ]]; then
      duration_ms=0
    fi
  fi

  local artifacts_json
  artifacts_json=$(get_subagent_artifact_paths "$subagent_id" "$project_root")
  local adapter_result_file collected_result_file failure_file resolved_result_file
  adapter_result_file=$(echo "$artifacts_json" | jq -r '.adapter_result_file')
  collected_result_file=$(echo "$artifacts_json" | jq -r '.collected_result_file')
  failure_file=$(echo "$artifacts_json" | jq -r '.failure_file')
  resolved_result_file="$result_file"
  if [[ -z "$resolved_result_file" ]]; then
    resolved_result_file=$(echo "$artifacts_json" | jq -r '.result_file')
  fi

  local failure_reason_json
  failure_reason_json=$(normalize_failure_reason_json "$failure_reason_input")
  final_status=$(normalize_terminal_subagent_status "$final_status")

  if command -v jq > /dev/null 2>&1; then
    local tmp="${subagent_dir}/state.tmp"
    jq --arg status "$final_status" \
      --arg ts "$end_time" \
      --argjson duration "$duration_ms" \
      --arg result_file "$resolved_result_file" \
      --arg adapter_result_file "$adapter_result_file" \
      --arg collected_result_file "$collected_result_file" \
      --arg failure_file "$failure_file" \
      --argjson failure_reason "$failure_reason_json" \
      '
       .status = $status
       | .completed_at = $ts
       | .duration_ms = $duration
       | .lifecycle.completed_at = $ts
       | .result = {
           status: $status,
           result_file: (if $result_file == "" then null else $result_file end),
           adapter_result_file: $adapter_result_file,
           collected_result_file: $collected_result_file,
           failure_file: (if $failure_reason == null then null else $failure_file end)
         }
       | .error = $failure_reason
       ' \
      "$state_file" > "$tmp" && mv "$tmp" "$state_file"
  fi

  if declare -f log_event > /dev/null 2>&1; then
    log_event "$project_root" "INFO" "subagent_completed" "Subagent completed" \
      "{\"subagent_id\":\"$subagent_id\",\"status\":\"$final_status\"}"
  fi
}

subagent_finalize_cleanup_completed() {
  local project_root="${1:-}"
  local max_age_hours="${2:-24}"
  local subagents_dir="${project_root}/${SUBAGENT_DIR}"

  if [[ ! -d "$subagents_dir" ]]; then
    return 0
  fi

  local cleaned=0
  local now
  now=$(TZ=UTC date +%s)
  local max_age_seconds=$((max_age_hours * 3600))
  local subagent_dir

  for subagent_dir in "$subagents_dir"/subagent_*; do
    if [[ -d "$subagent_dir" ]]; then
      local state_file="${subagent_dir}/${SUBAGENT_STATE_FILE}"
      if [[ -f "$state_file" ]]; then
        local agent_status completed_at
        agent_status=$(jq -r '.status // "unknown"' "$state_file" 2> /dev/null)
        completed_at=$(jq -r '.completed_at // empty' "$state_file" 2> /dev/null)

        if [[ "$agent_status" == "completed" || "$agent_status" == "failed" || "$agent_status" == "timeout" ]]; then
          if [[ -n "$completed_at" ]]; then
            local completed_epoch age
            completed_epoch=$(iso_timestamp_to_epoch "$completed_at")
            age=$((now - completed_epoch))

            if [[ $age -ge $max_age_seconds ]]; then
              rm -rf "$subagent_dir"
              cleaned=$((cleaned + 1))
            fi
          fi
        fi
      fi
    fi
  done

  echo "$cleaned"
}

subagent_finalize_finalize_execution() {
  local subagent_id="${1:-}"
  local project_root="${2:-}"
  local normalized_result_input="${3:-}"
  local subagent_dir
  subagent_dir=$(get_subagent_dir_path "$subagent_id" "$project_root")

  if [[ ! -d "$subagent_dir" ]]; then
    echo '{"error": "subagent_not_found"}'
    return 1
  fi

  local collected_result_file="${subagent_dir}/${SUBAGENT_COLLECTED_RESULT_FILE}"
  if [[ -z "$normalized_result_input" ]]; then
    if [[ ! -f "$collected_result_file" ]]; then
      echo '{"error": "collected_result_not_found"}'
      return 1
    fi
    normalized_result_input=$(cat "$collected_result_file")
  fi

  local normalized_result
  normalized_result=$(resolve_subagent_result_payload "$normalized_result_input")
  local status
  status=$(echo "$normalized_result" | jq -r '.status // "completed"')
  local result_content
  result_content=$(echo "$normalized_result" | jq -r '.result_content // ""')
  local failure_reason_json
  failure_reason_json=$(echo "$normalized_result" | jq -c '.failure_reason // null')

  printf '%s\n' "$result_content" > "${subagent_dir}/${SUBAGENT_RESULT_FILE}"
  if [[ "$failure_reason_json" != "null" ]]; then
    echo "$failure_reason_json" | jq '.' > "${subagent_dir}/${SUBAGENT_FAILURE_FILE}"
  else
    rm -f "${subagent_dir}/${SUBAGENT_FAILURE_FILE}"
  fi

  subagent_finalize_complete "$subagent_id" "$project_root" "$status" "${subagent_dir}/${SUBAGENT_RESULT_FILE}" "$failure_reason_json"
  echo "$normalized_result"
}

subagent_finalize_finalize_agent_execution() {
  local subagent_id="${1:-}"
  local project_root="${2:-}"
  local result_content="${3:-}"

  local status="completed"
  if echo "$result_content" | grep -qiE "error|failed|exception"; then
    status="failed"
  fi

  local payload_json
  payload_json=$(jq -n \
    --arg status "$status" \
    --arg content "$result_content" \
    '{status: $status, result_content: $content}')

  local normalized_result
  normalized_result=$(subagent_collect_execution_result "$subagent_id" "$project_root" "$payload_json")
  subagent_finalize_finalize_execution "$subagent_id" "$project_root" "$normalized_result"
}
