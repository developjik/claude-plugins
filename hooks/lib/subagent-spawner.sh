#!/usr/bin/env bash
# subagent-spawner.sh — 서브에이전트 스포닝 시스템
# P0-2: superpowers/GSD-2 벤치마킹
#
# DEPENDENCIES: json-utils.sh, logging.sh

set -euo pipefail

# ============================================================================
# 상수
# ============================================================================

readonly SUBAGENT_DIR=".harness/subagents"
readonly MAX_PARALLEL_SUBAGENTS=4
readonly SUBAGENT_TIMEOUT=600

# ============================================================================
# 모델 이름 변환
# ============================================================================
get_model_full_name() {
  local model_short="${1:-sonnet}"
  case "$model_short" in
    opus) echo "claude-opus-4-6" ;;
    sonnet) echo "claude-sonnet-4-6" ;;
    haiku) echo "claude-haiku-4-5" ;;
    *) echo "$model_short" ;;
  esac
}

# ============================================================================
# 서브에이전트 스폰
# ============================================================================
spawn_subagent() {
  local task_file="${1:-}"
  local project_root="${2:-}"
  local model="${3:-sonnet}"
  local purpose="${4:-task_execution}"

  local timestamp
  timestamp=$(date +%s)
  local random_suffix
  random_suffix=$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom 2>/dev/null | head -c 6 || echo "rand$$")
  local subagent_id="subagent_${timestamp}_${random_suffix}"

  local subagent_dir="${project_root}/${SUBAGENT_DIR}/${subagent_id}"
  mkdir -p "$subagent_dir"

  # 태스크 파일 복사
  if [[ -f "$task_file" ]]; then
    cp "$task_file" "${subagent_dir}/task.md"
  else
    echo "$task_file" > "${subagent_dir}/task.md"
  fi

  # 컨텍스트 준비
  prepare_subagent_context "$project_root" "$subagent_dir" "$purpose"

  # 상태 파일 생성
  local model_full
  model_full=$(get_model_full_name "$model")

  cat > "${subagent_dir}/state.json" << STATEOF
{
  "id": "$subagent_id",
  "status": "pending",
  "model": "$model_full",
  "model_short": "$model",
  "purpose": "$purpose",
  "task_file": "$(basename "$task_file")",
  "created_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "started_at": null,
  "completed_at": null,
  "duration_ms": null,
  "result": null,
  "error": null
}
STATEOF

  # 로그
  if declare -f log_event &>/dev/null; then
    log_event "$project_root" "INFO" "subagent_spawned" "Subagent created" \
      "{\"subagent_id\":\"$subagent_id\",\"model\":\"$model\"}"
  fi

  echo "$subagent_id"
}

# ============================================================================
# 서브에이전트 컨텍스트 준비
# ============================================================================
prepare_subagent_context() {
  local project_root="${1:-}"
  local subagent_dir="${2:-}"
  local purpose="${3:-task_execution}"

  local context_file="${subagent_dir}/context.md"
  local context=""

  context+="# Subagent Context\n\n"
  context+="## Purpose\n\n$purpose\n\n"

  # PROJECT.md
  if [[ -f "${project_root}/PROJECT.md" ]]; then
    context+="## Project Overview\n\n"
    context+="$(head -100 "${project_root}/PROJECT.md" 2>/dev/null)\n\n"
  fi

  # Purpose별 컨텍스트
  case "$purpose" in
    "code_review")
      if [[ -f "${project_root}/CLAUDE.md" ]]; then
        context+="## Guidelines\n\n"
        context+="$(head -50 "${project_root}/CLAUDE.md" 2>/dev/null)\n\n"
      fi
      ;;
  esac

  # 태스크
  if [[ -f "${subagent_dir}/task.md" ]]; then
    context+="## Task\n\n"
    context+="$(cat "${subagent_dir}/task.md")\n\n"
  fi

  context+="## Output\n\nWrite result to: result.md\n"

  echo -e "$context" > "$context_file"
}

# ============================================================================
# 서브에이전트 실행 시작
# ============================================================================
start_subagent_execution() {
  local subagent_id="${1:-}"
  local project_root="${2:-}"
  local subagent_dir="${project_root}/${SUBAGENT_DIR}/${subagent_id}"

  if [[ ! -d "$subagent_dir" ]]; then
    return 1
  fi

  local state_file="${subagent_dir}/state.json"
  local timestamp
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  if command -v jq &>/dev/null; then
    local tmp="${subagent_dir}/state.tmp"
    jq --arg ts "$timestamp" '.status = "running" | .started_at = $ts' \
      "$state_file" > "$tmp" && mv "$tmp" "$state_file"
  fi
}

# ============================================================================
# 서브에이전트 완료 처리
# ============================================================================
complete_subagent() {
  local subagent_id="${1:-}"
  local project_root="${2:-}"
  local final_status="${3:-completed}"
  local result_file="${4:-}"
  local subagent_dir="${project_root}/${SUBAGENT_DIR}/${subagent_id}"

  if [[ ! -d "$subagent_dir" ]]; then
    return 1
  fi

  local state_file="${subagent_dir}/state.json"
  local end_time
  # Fixed: Use UTC for consistent timestamp generation
  end_time=$(TZ=UTC date -u '+%Y-%m-%dT%H:%M:%SZ')

  # 실행 시간 계산
  local duration_ms=0
  local start_time
  start_time=$(jq -r '.started_at // empty' "$state_file" 2>/dev/null)

  if [[ -n "$start_time" ]]; then
    local start_epoch end_epoch
    # Fixed: Add TZ=UTC for consistent timezone handling across platforms
    start_epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%SZ" "$start_time" +%s 2>/dev/null || echo 0)
    end_epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%SZ" "$end_time" +%s 2>/dev/null || echo 0)
    duration_ms=$(( (end_epoch - start_epoch) * 1000 ))
  fi

  if command -v jq &>/dev/null; then
    local tmp="${subagent_dir}/state.tmp"
    jq --arg status "$final_status" \
       --arg ts "$end_time" \
       --argjson duration "$duration_ms" \
       '.status = $status | .completed_at = $ts | .duration_ms = $duration' \
       "$state_file" > "$tmp" && mv "$tmp" "$state_file"
  fi

  if declare -f log_event &>/dev/null; then
    log_event "$project_root" "INFO" "subagent_completed" "Subagent completed" \
      "{\"subagent_id\":\"$subagent_id\",\"status\":\"$final_status\"}"
  fi
}

# ============================================================================
# 서브에이전트 상태 조회
# ============================================================================
get_subagent_status() {
  local subagent_id="${1:-}"
  local project_root="${2:-}"
  local state_file="${project_root}/${SUBAGENT_DIR}/${subagent_id}/state.json"

  if [[ -f "$state_file" ]]; then
    cat "$state_file"
  else
    echo "{\"error\": \"subagent_not_found\", \"id\": \"$subagent_id\"}"
  fi
}

# ============================================================================
# 활성 서브에이전트 목록
# ============================================================================
list_active_subagents() {
  local project_root="${1:-}"
  local subagents_dir="${project_root}/${SUBAGENT_DIR}"

  if [[ ! -d "$subagents_dir" ]]; then
    echo "[]"
    return 0
  fi

  local active_ids=()

  for subagent_dir in "$subagents_dir"/subagent_*; do
    if [[ -d "$subagent_dir" ]]; then
      local state_file="${subagent_dir}/state.json"
      if [[ -f "$state_file" ]]; then
        local status
        status=$(jq -r '.status // "unknown"' "$state_file" 2>/dev/null)
        if [[ "$status" == "pending" || "$status" == "running" ]]; then
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

# ============================================================================
# 서브에이전트 결과 집계
# ============================================================================
aggregate_subagent_results() {
  local project_root="${1:-}"
  local subagent_ids="${2:-}"

  local results_dir="${project_root}/.harness/results"
  mkdir -p "$results_dir"

  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)

  local total=0
  local completed=0
  local failed=0
  local total_duration=0
  local subagent_results="[]"

  for subagent_id in $(echo "$subagent_ids" | tr ',' ' '); do
    local subagent_dir="${project_root}/${SUBAGENT_DIR}/${subagent_id}"

    if [[ -d "$subagent_dir" ]]; then
      local state_file="${subagent_dir}/state.json"
      if [[ -f "$state_file" ]]; then
        local status duration
        status=$(jq -r '.status // "unknown"' "$state_file" 2>/dev/null)
        duration=$(jq -r '.duration_ms // 0' "$state_file" 2>/dev/null)

        total=$((total + 1))
        total_duration=$((total_duration + duration))

        if [[ "$status" == "completed" ]]; then
          completed=$((completed + 1))
        else
          failed=$((failed + 1))
        fi

        local entry
        entry=$(jq -c '{id: .id, status: .status, duration_ms: .duration_ms}' "$state_file" 2>/dev/null)
        subagent_results=$(echo "$subagent_results" | jq '. + ['"$entry"']')
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

# ============================================================================
# 서브에이전트 완료 대기
# Usage: wait_for_subagents <project_root> <subagent_ids_comma> [timeout_seconds]
# Returns: JSON with overall status and per-subagent summary
# ============================================================================
wait_for_subagents() {
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

      local state_file="${project_root}/${SUBAGENT_DIR}/${subagent_id}/state.json"
      local entry
      local status="missing"

      if [[ -f "$state_file" ]]; then
        status=$(jq -r '.status // "unknown"' "$state_file" 2>/dev/null)
        entry=$(jq -c '{
          id: .id,
          status: .status,
          duration_ms: (.duration_ms // 0),
          started_at: .started_at,
          completed_at: .completed_at
        }' "$state_file" 2>/dev/null)
      else
        entry=$(jq -n --arg id "$subagent_id" '{id: $id, status: "missing", duration_ms: 0}')
      fi

      case "$status" in
        completed)
          completed=$((completed + 1))
          ;;
        running)
          running=$((running + 1))
          ;;
        pending)
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

      snapshot_entries=$(echo "$snapshot_entries" | jq '. + ['"$entry"']')
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

# ============================================================================
# 서브에이전트 정리
# ============================================================================
cleanup_completed_subagents() {
  local project_root="${1:-}"
  local max_age_hours="${2:-24}"
  local subagents_dir="${project_root}/${SUBAGENT_DIR}"

  if [[ ! -d "$subagents_dir" ]]; then
    return 0
  fi

  local cleaned=0
  local now
  # Fixed: Use UTC for consistent time comparison
  now=$(TZ=UTC date +%s)
  local max_age_seconds=$((max_age_hours * 3600))

  for subagent_dir in "$subagents_dir"/subagent_*; do
    if [[ -d "$subagent_dir" ]]; then
      local state_file="${subagent_dir}/state.json"
      if [[ -f "$state_file" ]]; then
        local agent_status completed_at
        agent_status=$(jq -r '.status // "unknown"' "$state_file" 2>/dev/null)
        completed_at=$(jq -r '.completed_at // empty' "$state_file" 2>/dev/null)

        if [[ "$agent_status" == "completed" || "$agent_status" == "failed" || "$agent_status" == "timeout" ]]; then
          if [[ -n "$completed_at" ]]; then
            local completed_epoch
            # Fixed: Use correct format matching (with or without Z suffix)
            completed_epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "${completed_at%Z}" +%s 2>/dev/null || echo 0)
            local age=$((now - completed_epoch))

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

# ============================================================================
# Agent 툴 파라미터 생성
# ============================================================================
generate_agent_params() {
  local subagent_id="${1:-}"
  local project_root="${2:-}"
  local subagent_dir="${project_root}/${SUBAGENT_DIR}/${subagent_id}"

  if [[ ! -d "$subagent_dir" ]]; then
    echo '{"error": "subagent_not_found"}'
    return 1
  fi

  local state_file="${subagent_dir}/state.json"
  local model purpose
  model=$(jq -r '.model // "claude-sonnet-4-6"' "$state_file" 2>/dev/null)
  purpose=$(jq -r '.purpose // "task_execution"' "$state_file" 2>/dev/null)

  local context_file="${subagent_dir}/context.md"
  local prompt=""
  if [[ -f "$context_file" ]]; then
    prompt=$(cat "$context_file")
  fi

  jq -n \
    --arg prompt "$prompt" \
    --arg model "$model" \
    --arg subagent_id "$subagent_id" \
    '{
      subagent_type: "general-purpose",
      description: $subagent_id,
      model: $model,
      prompt: $prompt
    }'
}

# ============================================================================
# 실행 준비
# ============================================================================
prepare_for_agent_execution() {
  local subagent_id="${1:-}"
  local project_root="${2:-}"

  start_subagent_execution "$subagent_id" "$project_root"
  generate_agent_params "$subagent_id" "$project_root"
}

# ============================================================================
# 실행 완료 처리
# ============================================================================
finalize_agent_execution() {
  local subagent_id="${1:-}"
  local project_root="${2:-}"
  local result_content="${3:-}"
  local subagent_dir="${project_root}/${SUBAGENT_DIR}/${subagent_id}"

  echo "$result_content" > "${subagent_dir}/result.md"

  local status="completed"
  if echo "$result_content" | grep -qiE "error|failed"; then
    status="failed"
  fi

  complete_subagent "$subagent_id" "$project_root" "$status" "${subagent_dir}/result.md"
}
