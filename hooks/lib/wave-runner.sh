#!/usr/bin/env bash
# wave-runner.sh — Wave execution orchestration helpers

set -euo pipefail

: "${WAVE_TIMEOUT:=300}"

if [[ -z "${WAVE_RUNNER_LIB_DIR:-}" ]]; then
  WAVE_RUNNER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

if ! declare -f group_tasks_into_waves &> /dev/null; then
  # shellcheck source=hooks/lib/wave-graph.sh
  source "${WAVE_RUNNER_LIB_DIR}/wave-graph.sh"
fi

if ! declare -f spawn_subagent &> /dev/null; then
  # shellcheck source=hooks/lib/subagent-spawner.sh
  source "${WAVE_RUNNER_LIB_DIR}/subagent-spawner.sh"
fi

# ============================================================================
# 단일 태스크 실행 (실제 서브에이전트 사용)
# Usage: execute_task <task_file> <project_root> [model]
# Returns: subagent_id on success, empty on failure
# ============================================================================
execute_task() {
  local task_file="${1:-}"
  local project_root="${2:-}"
  local model="${3:-sonnet}"

  local log_dir="${project_root}/.harness/logs"
  local task_name
  task_name=$(basename "$task_file" .md 2> /dev/null || echo "unknown")

  mkdir -p "$log_dir"

  # 로그: 태스크 시작
  if declare -f log_event &> /dev/null; then
    log_event "$project_root" "INFO" "task_start" "Starting task" \
      "\"task\":\"$task_name\",\"model\":\"$model\""
  fi

  # 태스크 파일 존재 확인
  if [[ ! -f "$task_file" ]]; then
    if declare -f log_event &> /dev/null; then
      log_event "$project_root" "ERROR" "task_error" "Task file not found" \
        "\"task\":\"$task_name\""
    fi
    return 1
  fi

  # 서브에이전트 스폰
  local subagent_id=""
  if declare -f spawn_subagent &> /dev/null; then
    subagent_id=$(spawn_subagent "$task_file" "$project_root" "$model" "task_execution")
  else
    # 스포너 없으면 기존 방식으로 폴백
    if declare -f log_event &> /dev/null; then
      log_event "$project_root" "WARN" "task_fallback" "Using fallback execution (no spawner)" \
        "\"task\":\"$task_name\""
    fi
    echo "[INFO] Executing task: $task_name (simulation mode)" >&2
    subagent_id="sim_$(date +%s)_$$"
  fi

  # 로그: 서브에이전트 스폰
  if declare -f log_event &> /dev/null; then
    log_event "$project_root" "INFO" "subagent_spawned" "Subagent spawned for task" \
      "\"task\":\"$task_name\",\"subagent_id\":\"$subagent_id\""
  fi

  echo "$subagent_id"
}

# ============================================================================
# 태스크 실행 및 결과 대기 (Agent 툴 연동용)
# Usage: execute_task_sync <task_file> <project_root> [model]
# Returns: JSON with subagent_id and status
# ============================================================================
execute_task_sync() {
  local task_file="${1:-}"
  local project_root="${2:-}"
  local model="${3:-sonnet}"

  local subagent_id
  subagent_id=$(execute_task "$task_file" "$project_root" "$model")

  if [[ -z "$subagent_id" ]]; then
    echo '{"error": "spawn_failed", "status": "failed"}'
    return 1
  fi

  # 실행 계약 준비
  if declare -f prepare_for_agent_execution &> /dev/null; then
    prepare_for_agent_execution "$subagent_id" "$project_root" > /dev/null
  fi

  # 실행 시작
  if declare -f start_subagent_execution &> /dev/null; then
    start_subagent_execution "$subagent_id" "$project_root"
  fi

  # Agent 툴 파라미터 반환 (실제 실행은 Claude Code에서)
  if declare -f generate_agent_params &> /dev/null; then
    generate_agent_params "$subagent_id" "$project_root"
  else
    jq -n --arg id "$subagent_id" \
      '{"subagent_id": $id, "status": "ready_for_execution"}'
  fi
}

# ============================================================================
# 태스크 완료 처리 (Agent 실행 후 호출)
# Usage: complete_task <subagent_id> <project_root> <result_content>
# ============================================================================
complete_task() {
  local subagent_id="${1:-}"
  local project_root="${2:-}"
  local result_content="${3:-}"

  local status="completed"

  # 결과 내용으로 성공/실패 판단
  if echo "$result_content" | grep -qiE "error|failed|exception"; then
    status="failed"
  fi

  # 서브에이전트 완료 처리
  if declare -f finalize_agent_execution &> /dev/null; then
    finalize_agent_execution "$subagent_id" "$project_root" "$result_content"
  fi

  # 로그: 태스크 완료
  local subagent_dir="${project_root}/${SUBAGENT_DIR:-.harness/subagents}/${subagent_id}"
  if [[ -f "${subagent_dir}/state.json" ]]; then
    local duration
    duration=$(jq -r '.duration_ms // 0' "${subagent_dir}/state.json" 2> /dev/null)

    if declare -f log_event &> /dev/null; then
      log_event "$project_root" "INFO" "task_complete" "Task completed" \
        "\"subagent_id\":\"$subagent_id\",\"status\":\"$status\",\"duration_ms\":${duration}"
    fi
  fi
}

# Wave 실행 (병렬 또는 순차) - 개선된 버전
# Usage: execute_wave <wave_num> <tasks_json> <project_root> [parallel]
# Returns: JSON with wave results
execute_wave() {
  local wave_num="${1:-}"
  local tasks_json="${2:-}"
  local project_root="${3:-}"
  local parallel="${4:-true}"

  local state_dir="${project_root}/.harness/state"
  local completed_file="${state_dir}/completed-tasks.txt"
  local log_dir="${project_root}/.harness/logs"

  mkdir -p "$state_dir" "$log_dir"

  # 로그: Wave 시작
  if declare -f log_event &> /dev/null; then
    log_event "$project_root" "INFO" "wave_start" "Starting wave with real subagents" \
      "\"wave\":${wave_num},\"parallel\":${parallel}"
  fi

  # 태스크 메타데이터 추출
  local task_entries="[]"
  local tasks=()
  local has_dependency_metadata="false"
  if [[ -n "$tasks_json" ]] && command -v jq > /dev/null 2>&1; then
    task_entries=$(printf '%s' "$tasks_json" | jq -c '.' 2> /dev/null || echo "[]")

    while IFS= read -r task_file; do
      if [[ -n "$task_file" ]]; then
        tasks+=("$task_file")
      fi
    done < <(printf '%s' "$task_entries" | jq -r '.[]?.file // .[]?.path // empty' 2> /dev/null)

    if printf '%s' "$task_entries" | jq -e 'type == "array" and (length == 0 or all(.[]; (.id // "") != ""))' > /dev/null 2>&1; then
      has_dependency_metadata="true"
    fi
  fi

  # tasks가 비어있으면 경고 후 종료
  if [[ ${#tasks[@]} -eq 0 ]]; then
    if declare -f log_event &> /dev/null; then
      log_event "$project_root" "WARN" "wave_empty" "No tasks to execute in wave" \
        "\"wave\":${wave_num}"
    fi
    echo '{"wave":'"${wave_num}"',"status":"empty","subagents":[]}'
    return 0
  fi

  local subagent_ids=()
  local failed=0
  local skipped=0

  if [[ "$parallel" == "true" ]]; then
    local dependency_waves='[]'
    if [[ "$has_dependency_metadata" == "true" ]]; then
      if ! dependency_waves=$(group_tasks_into_waves "$task_entries"); then
        if declare -f log_event &> /dev/null; then
          log_event "$project_root" "ERROR" "wave_dependency_error" "Dependency graph invalid for parallel wave" \
            "\"wave\":${wave_num}"
        fi
        jq -n \
          --argjson wave "$wave_num" \
          --arg status "dependency_error" \
          --argjson details "$dependency_waves" \
          '{"wave": $wave, "status": $status, "error": $details}'
        return 0
      fi
    else
      dependency_waves=$(jq -n --argjson task_files "$(printf '%s\n' "${tasks[@]}" | jq -R . | jq -s .)" '[ $task_files ]')
    fi

    local dependency_plan='[]'
    local flat_subagents='[]'
    local wave_ids
    for wave_ids in $(echo "$dependency_waves" | jq -r '.[] | @base64'); do
      local planned_wave='[]'
      local wave_task_ids
      wave_task_ids=$(echo "$wave_ids" | base64 --decode)

      while IFS= read -r task_ref; do
        [[ -n "$task_ref" ]] || continue

        local task_file
        local task_id=""
        if [[ "$has_dependency_metadata" == "true" ]]; then
          task_id="$task_ref"
          task_file=$(printf '%s' "$task_entries" | jq -r --arg id "$task_id" '.[] | select(.id == $id) | .file // .path // empty' | head -1)
        else
          task_file="$task_ref"
        fi

        local resolved_task_file="$task_file"
        if [[ ! -f "$resolved_task_file" && -f "${project_root}/${task_file}" ]]; then
          resolved_task_file="${project_root}/${task_file}"
        fi

        if [[ -f "$resolved_task_file" ]]; then
          local subagent_id
          subagent_id=$(execute_task "$resolved_task_file" "$project_root" "sonnet")

          if [[ -n "$subagent_id" ]]; then
            subagent_ids+=("$subagent_id")

            local params='{}'
            if declare -f generate_agent_params &> /dev/null; then
              params=$(generate_agent_params "$subagent_id" "$project_root")
            fi
            params=$(echo "$params" | jq --arg id "$subagent_id" --arg task_id "$task_id" '. + {subagent_id: $id} + (if $task_id != "" then {task_id: $task_id} else {} end)')

            planned_wave=$(echo "$planned_wave" | jq --argjson params "$params" '. + [$params]')
            flat_subagents=$(echo "$flat_subagents" | jq --argjson params "$params" '. + [$params]')
          else
            failed=$((failed + 1))
          fi
        else
          failed=$((failed + 1))
        fi
      done < <(echo "$wave_task_ids" | jq -r '.[]')

      dependency_plan=$(echo "$dependency_plan" | jq --argjson planned_wave "$planned_wave" '. + [$planned_wave]')
    done

    # 로그: 병렬 실행 시작
    if declare -f log_event &> /dev/null; then
      log_event "$project_root" "INFO" "wave_parallel" "Parallel execution started" \
        "\"wave\":${wave_num},\"subagent_count\":${#subagent_ids[@]}"
    fi

    jq -n \
      --argjson wave "$wave_num" \
      --arg status "planned" \
      --argjson failed "$failed" \
      --argjson subagents "$flat_subagents" \
      --argjson dependency_plan "$dependency_plan" \
      '{
        wave: $wave,
        status: $status,
        parallel: true,
        failed: $failed,
        dependency_waves: $dependency_plan,
        subagents: $subagents
      }'

  else
    local ordered_task_ids='[]'
    if [[ "$has_dependency_metadata" == "true" ]]; then
      if ! ordered_task_ids=$(topological_sort "$task_entries"); then
        if declare -f log_event &> /dev/null; then
          log_event "$project_root" "ERROR" "wave_dependency_error" "Dependency graph invalid for sequential wave" \
            "\"wave\":${wave_num}"
        fi
        jq -n \
          --argjson wave "$wave_num" \
          --arg status "dependency_error" \
          --argjson details "$ordered_task_ids" \
          '{"wave": $wave, "status": $status, "error": $details}'
        return 0
      fi
    fi

    # 순차 실행
    local task_iter_refs='[]'
    if [[ "$has_dependency_metadata" == "true" ]]; then
      task_iter_refs="$ordered_task_ids"
    else
      task_iter_refs=$(printf '%s\n' "${tasks[@]}" | jq -R . | jq -s .)
    fi

    while IFS= read -r task_ref; do
      [[ -n "$task_ref" ]] || continue

      local task_file
      local task_id=""
      local deps='[]'
      if [[ "$has_dependency_metadata" == "true" ]]; then
        task_id="$task_ref"
        task_file=$(printf '%s' "$task_entries" | jq -r --arg id "$task_id" '.[] | select(.id == $id) | .file // .path // empty' | head -1)
        deps=$(printf '%s' "$task_entries" | jq -c --arg id "$task_id" '.[] | select(.id == $id) | .dependencies // []' | head -1)
      else
        task_file="$task_ref"
      fi

      local resolved_task_file="$task_file"
      if [[ ! -f "$resolved_task_file" && -f "${project_root}/${task_file}" ]]; then
        resolved_task_file="${project_root}/${task_file}"
      fi

      local completed_key="$task_id"
      if [[ -z "$completed_key" ]]; then
        completed_key=$(basename "$resolved_task_file" .md)
      fi

      if ! check_dependencies_met "$completed_key" "$completed_file" "$deps"; then
        skipped=$((skipped + 1))
        continue
      fi

      if [[ -f "$resolved_task_file" ]]; then
        local subagent_id
        subagent_id=$(execute_task "$resolved_task_file" "$project_root" "sonnet")

        if [[ -n "$subagent_id" ]]; then
          subagent_ids+=("$subagent_id")
          echo "$completed_key" >> "$completed_file"
        else
          failed=$((failed + 1))
        fi
      else
        failed=$((failed + 1))
      fi
    done < <(echo "$task_iter_refs" | jq -r '.[]')

    # 결과 반환
    local status="completed"
    if [[ $failed -gt 0 || $skipped -gt 0 ]]; then
      status="partial_failure"
    fi

    jq -n --argjson wave "$wave_num" --arg status "$status" \
      --argjson subagent_count "${#subagent_ids[@]}" \
      --argjson failed "$failed" \
      --argjson skipped "$skipped" \
      '{"wave":$wave,"status":$status,"subagent_count":$subagent_count,"failed":$failed,"skipped":$skipped}'
  fi
}

# ============================================================================
# Wave 완료 확인 및 결과 집계
# Usage: finalize_wave <wave_num> <project_root> <subagent_ids_comma>
# Returns: JSON with wave summary
# ============================================================================
finalize_wave() {
  local wave_num="${1:-}"
  local project_root="${2:-}"
  local subagent_ids_csv="${3:-}"

  # 결과 집계
  local results
  if declare -f aggregate_subagent_results &> /dev/null; then
    results=$(aggregate_subagent_results "$project_root" "$subagent_ids_csv")
  else
    results='{"total":0,"completed":0,"failed":0}'
  fi

  local total completed failed
  total=$(echo "$results" | jq -r '.summary.total // 0')
  completed=$(echo "$results" | jq -r '.summary.completed // 0')
  failed=$(echo "$results" | jq -r '.summary.failed // 0')

  # 로그: Wave 완료
  if declare -f log_event &> /dev/null; then
    log_event "$project_root" "INFO" "wave_complete" "Wave completed" \
      "\"wave\":${wave_num},\"total\":${total},\"completed\":${completed},\"failed\":${failed}"
  fi

  # 결과 반환
  echo "$results" | jq '. + {"wave":'"${wave_num}"'}'
}

# ============================================================================
# 전체 Wave 실행 (개선된 버전)
# Usage: execute_all_waves <feature_slug> <project_root>
# Returns: JSON with overall execution summary
# ============================================================================
execute_all_waves() {
  local feature_slug="${1:-}"
  local project_root="${2:-}"
  local waves_file="${project_root}/docs/specs/${feature_slug}/waves.yaml"

  if [[ ! -f "$waves_file" ]]; then
    echo "ERROR: waves.yaml not found: $waves_file" >&2
    return 1
  fi

  local state_dir="${project_root}/.harness/state"
  local completed_file="${state_dir}/completed-tasks.txt"

  # 상태 초기화
  mkdir -p "$state_dir"
  : > "$completed_file"

  # yq 필요
  if ! command -v yq &> /dev/null; then
    echo "ERROR: yq is required for wave execution" >&2
    echo "INFO: Install: brew install yq" >&2
    return 1
  fi

  local total_waves
  total_waves=$(yq '.total_waves // 0' "$waves_file" 2> /dev/null)

  if [[ "$total_waves" -lt 1 ]]; then
    echo "ERROR: No waves defined in $waves_file" >&2
    return 1
  fi

  # 로그: Wave 실행 시작
  if declare -f log_event &> /dev/null; then
    log_event "$project_root" "INFO" "waves_start" "Starting wave execution" \
      "\"feature\":\"$feature_slug\",\"total_waves\":${total_waves}"
  fi

  local all_subagent_ids=()
  local wave_results='[]'
  local total_failed=0

  # 각 Wave 실행
  for wave_num in $(seq 1 "$total_waves"); do
    local parallel
    parallel=$(yq ".waves[] | select(.wave == $wave_num) | .parallel // true" "$waves_file" 2> /dev/null)
    local tasks
    tasks=$(yq ".waves[] | select(.wave == $wave_num) | .tasks" "$waves_file" 2> /dev/null)

    echo "[Wave $wave_num/$total_waves] Executing tasks (parallel: $parallel)..."

    # Wave 실행
    local wave_result
    wave_result=$(execute_wave "$wave_num" "$tasks" "$project_root" "$parallel")

    # 서브에이전트 ID 수집
    local wave_subagent_ids
    wave_subagent_ids=$(echo "$wave_result" | jq -r '.subagents[]?.subagent_id // empty' 2> /dev/null)

    for subagent_id in $wave_subagent_ids; do
      all_subagent_ids+=("$subagent_id")
    done

    # Wave 결과 저장
    wave_results=$(echo "$wave_results" | jq --argjson wave_result "$wave_result" '. + [$wave_result]')

    local wave_status
    wave_status=$(echo "$wave_result" | jq -r '.status // "unknown"' 2> /dev/null)
    if [[ "$wave_status" == "dependency_error" ]]; then
      total_failed=$((total_failed + 1))
      break
    fi

    # 로그: Wave 실행 완료
    if declare -f log_event &> /dev/null; then
      log_event "$project_root" "INFO" "wave_executed" "Wave executed" \
        "\"wave\":${wave_num},\"parallel\":${parallel}"
    fi
  done

  # 모든 서브에이전트 완료 대기
  echo ""
  echo "Waiting for all subagents to complete..."

  local all_ids_str
  all_ids_str=$(
    IFS=,
    echo "${all_subagent_ids[*]}"
  )

  local final_results
  if declare -f wait_for_subagents &> /dev/null && [[ -n "$all_ids_str" ]]; then
    final_results=$(wait_for_subagents "$project_root" "$all_ids_str" "$WAVE_TIMEOUT")
  else
    final_results='{"status":"completed","summary":{"total":'"${#all_subagent_ids[@]}"',"completed":0,"failed":0}}'
  fi

  # 로그: 전체 Wave 완료
  if declare -f log_event &> /dev/null; then
    log_event "$project_root" "INFO" "waves_complete" "All waves completed" \
      "\"feature\":\"$feature_slug\",\"total_subagents\":${#all_subagent_ids[@]}"
  fi

  # 결과 요약
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Wave Execution Summary"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "Feature: $feature_slug"
  echo "Total Waves: $total_waves"
  echo "Total Subagents: ${#all_subagent_ids[@]}"
  echo ""

  # 결과 반환
  echo "$final_results" | jq '. + {
    "feature": "'"$feature_slug"'",
    "total_waves": '"$total_waves"',
    "wave_results": '"$wave_results"'
  }'

  return 0
}

# ============================================================================
# 드라이런 (계획만 확인)
# ============================================================================

dry_run_waves() {
  local feature_slug="${1:-}"
  local project_root="${2:-}"
  local waves_file="${project_root}/docs/specs/${feature_slug}/waves.yaml"

  if [[ ! -f "$waves_file" ]]; then
    echo "[ERROR] waves.yaml not found: $waves_file" >&2
    return 1
  fi

  if ! command -v yq &> /dev/null; then
    echo "[ERROR] yq is required" >&2
    return 1
  fi

  local total_waves
  total_waves=$(yq '.total_waves // 0' "$waves_file" 2> /dev/null)

  echo "========================================"
  echo "Wave Execution Plan: $feature_slug"
  echo "========================================"
  echo ""

  for wave_num in $(seq 1 "$total_waves"); do
    local parallel
    local task_count
    parallel=$(yq ".waves[] | select(.wave == $wave_num) | .parallel // true" "$waves_file" 2> /dev/null)
    task_count=$(yq ".waves[] | select(.wave == $wave_num) | .tasks | length" "$waves_file" 2> /dev/null)

    echo "Wave $wave_num (parallel: $parallel)"
    echo "  Tasks: $task_count"

    # 태스크 이름 출력
    yq ".waves[] | select(.wave == $wave_num) | .tasks[].name" "$waves_file" 2> /dev/null | while read -r name; do
      echo "    - $name"
    done

    echo ""
  done

  echo "========================================"
  echo "Run without --dry-run to execute"
  echo "========================================"
}
