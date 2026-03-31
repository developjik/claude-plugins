#!/usr/bin/env bash
# subagent-collect.sh — subagent collection/status helpers

set -euo pipefail

: "${SUBAGENT_DIR:=.harness/subagents}"
: "${SUBAGENT_STATE_FILE:=state.json}"
: "${SUBAGENT_ADAPTER_RESULT_FILE:=adapter-result.json}"
: "${SUBAGENT_COLLECTED_RESULT_FILE:=collected-result.json}"
: "${SUBAGENT_TIMEOUT:=600}"

subagent_collect_execution_result() {
  local subagent_id="${1:-}"
  local project_root="${2:-}"
  local payload_input="${3:-}"
  local subagent_dir
  subagent_dir=$(get_subagent_dir_path "$subagent_id" "$project_root")

  if [[ ! -d "$subagent_dir" ]]; then
    echo '{"error": "subagent_not_found"}'
    return 1
  fi

  local state_file="${subagent_dir}/${SUBAGENT_STATE_FILE}"
  local adapter_result_file="${subagent_dir}/${SUBAGENT_ADAPTER_RESULT_FILE}"
  local collected_result_file="${subagent_dir}/${SUBAGENT_COLLECTED_RESULT_FILE}"
  local collected_at
  collected_at=$(subagent_now_utc)

  local raw_payload
  if [[ -z "$payload_input" && -f "$adapter_result_file" ]]; then
    raw_payload=$(cat "$adapter_result_file")
  else
    raw_payload=$(resolve_subagent_result_payload "$payload_input")
  fi

  echo "$raw_payload" | jq '.' > "$adapter_result_file"

  local normalized_result
  normalized_result=$(jq -n \
    --argjson raw "$raw_payload" \
    --arg subagent_id "$subagent_id" \
    --arg ts "$collected_at" \
    '
    def normalized_status:
      if (($raw.status // "") | ascii_downcase) == "timeout" then
        "timeout"
      elif (($raw.status // "") | ascii_downcase) == "failed" then
        "failed"
      elif (($raw.status // "") | ascii_downcase) == "completed" then
        "completed"
      elif ($raw.failure_reason // $raw.error) != null then
        "failed"
      elif (($raw.result_content // $raw.result // $raw.content // $raw.output // "") | test("(error|failed|exception)"; "i")) then
        "failed"
      else
        "completed"
      end;
    def normalize_failure($status):
      if ($raw.failure_reason // $raw.error) == null then
        if $status == "timeout" then
          {code: "timeout", message: "Execution timed out", details: null}
        else
          null
        end
      elif (($raw.failure_reason // $raw.error) | type) == "string" then
        {
          code: (if $status == "timeout" then "timeout" else "execution_failed" end),
          message: ($raw.failure_reason // $raw.error),
          details: null
        }
      elif (($raw.failure_reason // $raw.error) | type) == "object" then
        {
          code: (($raw.failure_reason // $raw.error).code // ($raw.failure_reason // $raw.error).type // (if $status == "timeout" then "timeout" else "execution_failed" end)),
          message: (($raw.failure_reason // $raw.error).message // ($raw.failure_reason // $raw.error).error // ($raw.failure_reason // $raw.error).reason // (if $status == "timeout" then "Execution timed out" else "Execution failed" end)),
          details: (($raw.failure_reason // $raw.error).details // ($raw.failure_reason // $raw.error).context // ($raw.failure_reason // $raw.error).metadata // null)
        }
      else
        {
          code: (if $status == "timeout" then "timeout" else "execution_failed" end),
          message: (($raw.failure_reason // $raw.error) | tostring),
          details: null
        }
      end;
    (normalized_status) as $status |
    {
      contract_version: 1,
      subagent_id: $subagent_id,
      status: $status,
      result_content: ($raw.result_content // $raw.result // $raw.content // $raw.output // ""),
      failure_reason: normalize_failure($status),
      executor: (
        if ($raw.executor // null) == null then
          null
        elif ($raw.executor | type) == "object" then
          {
            name: ($raw.executor.name // $raw.executor.adapter // $raw.executor.type // null),
            run_id: ($raw.executor.run_id // $raw.executor.id // null),
            metadata: ($raw.executor.metadata // {})
          }
        else
          {name: ($raw.executor | tostring), run_id: null, metadata: {}}
        end
      ),
      collected_at: $ts,
      raw: $raw
    }')

  echo "$normalized_result" | jq '.' > "$collected_result_file"

  if command -v jq > /dev/null 2>&1; then
    local tmp="${subagent_dir}/state.tmp"
    jq --arg ts "$collected_at" \
      --argjson normalized "$normalized_result" \
      '
       .status = "collected"
       | .lifecycle.collected_at = $ts
       | .result = {
           status: $normalized.status,
           result_file: .artifacts.result_file,
           adapter_result_file: .artifacts.adapter_result_file,
           collected_result_file: .artifacts.collected_result_file,
           failure_file: (if $normalized.failure_reason == null then null else .artifacts.failure_file end)
         }
       | .error = $normalized.failure_reason
       | .executor = (
           if $normalized.executor == null then
             .executor
           else
             (.executor // {name: null, run_id: null, request_file: null, metadata: {}})
             | .name = ($normalized.executor.name // .name)
             | .run_id = ($normalized.executor.run_id // .run_id)
             | .metadata = ((.metadata // {}) + ($normalized.executor.metadata // {}))
           end
         )
       ' "$state_file" > "$tmp" && mv "$tmp" "$state_file"
  fi

  echo "$normalized_result"
}

subagent_collect_get_status() {
  local subagent_id="${1:-}"
  local project_root="${2:-}"
  local state_file
  state_file="$(get_subagent_dir_path "$subagent_id" "$project_root")/${SUBAGENT_STATE_FILE}"

  if [[ -f "$state_file" ]]; then
    cat "$state_file"
  else
    echo "{\"error\": \"subagent_not_found\", \"id\": \"$subagent_id\"}"
  fi
}

subagent_collect_list_active() {
  local project_root="${1:-}"
  local subagents_dir="${project_root}/${SUBAGENT_DIR}"

  if [[ ! -d "$subagents_dir" ]]; then
    echo "[]"
    return 0
  fi

  local active_ids=()
  local subagent_dir state_file status
  for subagent_dir in "$subagents_dir"/subagent_*; do
    if [[ -d "$subagent_dir" ]]; then
      state_file="${subagent_dir}/${SUBAGENT_STATE_FILE}"
      if [[ -f "$state_file" ]]; then
        status=$(jq -r '.status // "unknown"' "$state_file" 2> /dev/null)
        if [[ "$status" == "pending" || "$status" == "ready" || "$status" == "running" || "$status" == "collected" ]]; then
          active_ids+=("$(basename "$subagent_dir")")
        fi
      fi
    fi
  done

  if [[ ${#active_ids[@]} -eq 0 ]]; then
    echo "[]"
  else
    printf '%s\n' "${active_ids[@]}" | jq -R . | jq -s .
  fi
}

subagent_collect_aggregate_results() {
  local project_root="${1:-}"
  local subagent_ids="${2:-}"

  local results_dir="${project_root}/.harness/results"
  mkdir -p "$results_dir"

  local total=0
  local completed=0
  local failed=0
  local total_duration=0
  local subagent_results="[]"
  local subagent_id

  for subagent_id in $(echo "$subagent_ids" | tr ',' ' '); do
    local subagent_dir="${project_root}/${SUBAGENT_DIR}/${subagent_id}"
    if [[ -d "$subagent_dir" ]]; then
      local state_file="${subagent_dir}/${SUBAGENT_STATE_FILE}"
      if [[ -f "$state_file" ]]; then
        local status duration
        status=$(jq -r '.status // "unknown"' "$state_file" 2> /dev/null)
        duration=$(jq -r '.duration_ms // 0' "$state_file" 2> /dev/null)

        total=$((total + 1))
        total_duration=$((total_duration + duration))

        if [[ "$status" == "completed" ]]; then
          completed=$((completed + 1))
        else
          failed=$((failed + 1))
        fi

        local entry
        entry=$(jq -c '{id: .id, status: .status, duration_ms: .duration_ms}' "$state_file" 2> /dev/null)
        subagent_results=$(echo "$subagent_results" | jq --argjson entry "$entry" '. + [$entry]')
      fi
    fi
  done

  local success_rate=0
  if [[ $total -gt 0 ]]; then
    success_rate=$(awk "BEGIN {printf \"%.2f\", $completed / $total}")
  fi

  jq -n \
    --argjson total "$total" \
    --argjson completed "$completed" \
    --argjson failed "$failed" \
    --argjson duration "$total_duration" \
    --arg rate "$success_rate" \
    --argjson subs "$subagent_results" \
    '{
      timestamp: "'"$(date -u '+%Y-%m-%dT%H:%M:%SZ')"'",
      subagents: $subs,
      summary: {
        total: $total,
        completed: $completed,
        failed: $failed,
        total_duration_ms: $duration,
        success_rate: ($rate | tonumber)
      }
    }'
}

subagent_collect_wait_for_subagents() {
  local project_root="${1:-}"
  local subagent_ids="${2:-}"
  local timeout_seconds="${3:-$SUBAGENT_TIMEOUT}"

  if [[ -z "$subagent_ids" ]]; then
    jq -n '{
      status: "completed",
      subagents: [],
      summary: {
        total: 0,
        completed: 0,
        failed: 0,
        running: 0,
        pending: 0,
        timeout: 0
      }
    }'
    return 0
  fi

  local start_epoch
  start_epoch=$(date +%s)

  while true; do
    local snapshot_entries="[]"
    local total=0
    local completed=0
    local failed=0
    local running=0
    local pending=0
    local timed_out=0
    local subagent_id

    for subagent_id in $(echo "$subagent_ids" | tr ',' ' '); do
      [[ -n "$subagent_id" ]] || continue

      total=$((total + 1))

      local state_file="${project_root}/${SUBAGENT_DIR}/${subagent_id}/${SUBAGENT_STATE_FILE}"
      local entry
      local status="missing"

      if [[ -f "$state_file" ]]; then
        status=$(jq -r '.status // "unknown"' "$state_file" 2> /dev/null)
        entry=$(jq -c '{
          id: .id,
          status: .status,
          duration_ms: (.duration_ms // 0),
          started_at: .started_at,
          completed_at: .completed_at
        }' "$state_file" 2> /dev/null)
      else
        entry=$(jq -n --arg id "$subagent_id" '{id: $id, status: "missing", duration_ms: 0}')
      fi

      case "$status" in
        completed)
          completed=$((completed + 1))
          ;;
        running | collected)
          running=$((running + 1))
          ;;
        pending | ready)
          pending=$((pending + 1))
          ;;
        timeout)
          timed_out=$((timed_out + 1))
          failed=$((failed + 1))
          ;;
        *)
          failed=$((failed + 1))
          ;;
      esac

      snapshot_entries=$(echo "$snapshot_entries" | jq --argjson entry "$entry" '. + [$entry]')
    done

    local overall_status="running"
    if [[ $running -eq 0 && $pending -eq 0 ]]; then
      if [[ $failed -gt 0 ]]; then
        overall_status="partial_failure"
      else
        overall_status="completed"
      fi
    else
      local now_epoch elapsed
      now_epoch=$(date +%s)
      elapsed=$((now_epoch - start_epoch))
      if [[ $elapsed -ge $timeout_seconds ]]; then
        overall_status="timeout"
      fi
    fi

    local result
    result=$(jq -n \
      --arg status "$overall_status" \
      --argjson subs "$snapshot_entries" \
      --argjson total "$total" \
      --argjson completed "$completed" \
      --argjson failed "$failed" \
      --argjson running "$running" \
      --argjson pending "$pending" \
      --argjson timeout "$timed_out" \
      '{
        status: $status,
        subagents: $subs,
        summary: {
          total: $total,
          completed: $completed,
          failed: $failed,
          running: $running,
          pending: $pending,
          timeout: $timeout
        }
      }')

    if [[ "$overall_status" == "completed" || "$overall_status" == "partial_failure" || "$overall_status" == "timeout" ]]; then
      echo "$result"
      return 0
    fi

    sleep 1
  done
}
