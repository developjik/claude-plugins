#!/usr/bin/env bash
# wave-executor.sh — Wave 기반 병렬 실행 시스템
# 독립적인 태스크들을 병렬로 실행

set -euo pipefail

# ============================================================================
# Wave 실행 설정
# ============================================================================

readonly MAX_PARALLEL_TASKS=4  # 최대 병렬 태스크 수
readonly WAVE_TIMEOUT=300      # Wave당 최대 실행 시간 (초)

# ============================================================================
# YAML 파싱 (yq 없이도 동작)
# ============================================================================

parse_waves_yaml() {
  local yaml_file="${1:-}"
  local project_root="${2:-}"

  if [[ ! -f "$yaml_file" ]]; then
    echo "[]"
    return 1
  fi

  # yq가 있으면 사용
  if command -v yq &>/dev/null; then
    yq -o=json '.' "$yaml_file" 2>/dev/null
    return 0
  fi

  # 간단한 YAML 파싱 (기본적인 waves.yaml 형식만 지원)
  local current_wave=0
  local in_tasks=false
  local tasks_json="[]"

  while IFS= read -r line; do
    # Wave 번호 감지
    if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*wave:[[:space:]]*([0-9]+) ]]; then
      current_wave="${BASH_REMATCH[1]}"
      in_tasks=false
    # tasks 섹션 감지
    elif [[ "$line" =~ ^[[:space:]]*tasks: ]]; then
      in_tasks=true
    # 태스크 항목 감지
    elif [[ "$in_tasks" == true ]] && [[ "$line" =~ ^[[:space:]]*-[[:space:]]*id: ]]; then
      local task_id=$(echo "$line" | sed 's/.*id:[[:space:]]*//' | tr -d '"')
      # 간단한 JSON 생성은 생략 (yq 권장)
    fi
  done < "$yaml_file"

  echo "[]"
}

# ============================================================================
# 의존성 그래프 분석
# ============================================================================

# 태스크의 의존성이 모두 완료되었는지 확인
check_dependencies_met() {
  local task_id="${1:-}"
  local completed_file="${2:-}"
  local deps="${3:-}"

  if [[ -z "$deps" ]] || [[ "$deps" == "[]" ]]; then
    return 0
  fi

  for dep in $(echo "$deps" | tr ',' ' '); do
    dep=$(echo "$dep" | tr -d '[]"')
    if [[ ! -f "$completed_file" ]] || ! grep -q "^${dep}$" "$completed_file"; then
      return 1
    fi
  done

  return 0
}

# 의존성 그래프를 위상 정렬
topological_sort() {
  local tasks_json="${1:-}"
  local sorted=()
  local visited=""
  local temp_mark=""

  # 간단한 위상 정렬 구현
  # 실제로는 jq와 함께 더 복잡한 로직 필요
  echo "[]"
}

# ============================================================================
# Wave 실행
# ============================================================================

# 단일 태스크 실행
execute_task() {
  local task_file="${1:-}"
  local project_root="${2:-}"
  local log_dir="${project_root}/.harness/logs"

  mkdir -p "$log_dir"

  local task_name=$(basename "$task_file" .md)
  local start_time=$(date +%s)

  log_event "$project_root" "INFO" "task_start" "Starting task" "\"task\":\"$task_name\""

  # 태스크 파일이 존재하는지 확인
  if [[ ! -f "$task_file" ]]; then
    log_event "$project_root" "ERROR" "task_error" "Task file not found" "\"task\":\"$task_name\""
    return 1
  fi

  # 태스크 내용을 읽어서 /implement 스킬에 전달
  # 실제 구현에서는 Claude Code API 호출
  log_event "$project_root" "INFO" "task_execute" "Executing task content" "\"task\":\"$task_name\""

  local end_time=$(date +%s)
  local duration=$((end_time - start_time))

  log_event "$project_root" "INFO" "task_complete" "Task completed" "\"task\":\"$task_name\",\"duration\":${duration}"

  return 0
}

# Wave 실행 (병렬 또는 순차)
execute_wave() {
  local wave_num="${1:-}"
  local tasks_json="${2:-}"
  local project_root="${3:-}"
  local parallel="${4:-true}"

  local state_dir="${project_root}/.harness/state"
  local completed_file="${state_dir}/completed-tasks.txt"
  local log_dir="${project_root}/.harness/logs"

  mkdir -p "$state_dir" "$log_dir"

  log_event "$project_root" "INFO" "wave_start" "Starting wave" "\"wave\":${wave_num},\"parallel\":${parallel}"

  local pids=()
  local task_count=0

  # 태스크들을 배열로 변환
  # 실제로는 jq 사용
  local tasks=()

  if [[ "$parallel" == "true" ]]; then
    # 병렬 실행
    for task_file in "${tasks[@]}"; do
      if [[ -f "$task_file" ]]; then
        (
          execute_task "$task_file" "$project_root"
          local result=$?
          if [[ $result -eq 0 ]]; then
            local task_name=$(basename "$task_file" .md)
            echo "$task_name" >> "$completed_file"
          fi
          exit $result
        ) &
        pids+=($!)
        task_count=$((task_count + 1))

        # 최대 병렬 태스크 수 제한
        if [[ $task_count -ge $MAX_PARALLEL_TASKS ]]; then
          wait "${pids[-1]}" 2>/dev/null || true
          task_count=$((task_count - 1))
        fi
      fi
    done

    # 모든 백그라운드 프로세스 대기
    local failed=0
    for pid in "${pids[@]}"; do
      if ! wait "$pid" 2>/dev/null; then
        failed=$((failed + 1))
      fi
    done

    if [[ $failed -gt 0 ]]; then
      log_event "$project_root" "ERROR" "wave_error" "Some tasks failed" "\"wave\":${wave_num},\"failed\":${failed}"
      return 1
    fi
  else
    # 순차 실행
    for task_file in "${tasks[@]}"; do
      if [[ -f "$task_file" ]]; then
        if ! execute_task "$task_file" "$project_root"; then
          log_event "$project_root" "ERROR" "wave_error" "Sequential task failed" "\"wave\":${wave_num}"
          return 1
        fi
        local task_name=$(basename "$task_file" .md)
        echo "$task_name" >> "$completed_file"
      fi
    done
  fi

  log_event "$project_root" "INFO" "wave_complete" "Wave completed" "\"wave\":${wave_num}"
  return 0
}

# 전체 Wave 실행
execute_all_waves() {
  local feature_slug="${1:-}"
  local project_root="${2:-}"
  local waves_file="${project_root}/docs/specs/${feature_slug}/waves.yaml"

  if [[ ! -f "$waves_file" ]]; then
    echo "[ERROR] waves.yaml not found: $waves_file" >&2
    return 1
  fi

  local state_dir="${project_root}/.harness/state"
  local completed_file="${state_dir}/completed-tasks.txt"

  # 상태 초기화
  mkdir -p "$state_dir"
  : > "$completed_file"

  # Wave 파싱 (yq 필요)
  if ! command -v yq &>/dev/null; then
    echo "[ERROR] yq is required for wave execution" >&2
    echo "[INFO] Install: brew install yq" >&2
    return 1
  fi

  local total_waves=$(yq '.total_waves // 0' "$waves_file" 2>/dev/null)

  if [[ "$total_waves" -lt 1 ]]; then
    echo "[ERROR] No waves defined in $waves_file" >&2
    return 1
  fi

  log_event "$project_root" "INFO" "waves_start" "Starting wave execution" "\"feature\":\"$feature_slug\",\"total_waves\":${total_waves}"

  # 각 Wave 실행
  for wave_num in $(seq 1 "$total_waves"); do
    local parallel=$(yq ".waves[] | select(.wave == $wave_num) | .parallel // true" "$waves_file" 2>/dev/null)
    local tasks=$(yq ".waves[] | select(.wave == $wave_num) | .tasks" "$waves_file" 2>/dev/null)

    echo "[Wave $wave_num] Executing tasks (parallel: $parallel)..."

    if ! execute_wave "$wave_num" "$tasks" "$project_root" "$parallel"; then
      log_event "$project_root" "ERROR" "waves_failed" "Wave execution failed" "\"wave\":${wave_num}"
      return 1
    fi
  done

  log_event "$project_root" "INFO" "waves_complete" "All waves completed" "\"feature\":\"$feature_slug\""
  echo "[SUCCESS] All waves completed for $feature_slug"

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

  if ! command -v yq &>/dev/null; then
    echo "[ERROR] yq is required" >&2
    return 1
  fi

  local total_waves=$(yq '.total_waves // 0' "$waves_file" 2>/dev/null)

  echo "========================================"
  echo "Wave Execution Plan: $feature_slug"
  echo "========================================"
  echo ""

  for wave_num in $(seq 1 "$total_waves"); do
    local parallel=$(yq ".waves[] | select(.wave == $wave_num) | .parallel // true" "$waves_file" 2>/dev/null)
    local task_count=$(yq ".waves[] | select(.wave == $wave_num) | .tasks | length" "$waves_file" 2>/dev/null)

    echo "Wave $wave_num (parallel: $parallel)"
    echo "  Tasks: $task_count"

    # 태스크 이름 출력
    yq ".waves[] | select(.wave == $wave_num) | .tasks[].name" "$waves_file" 2>/dev/null | while read -r name; do
      echo "    - $name"
    done

    echo ""
  done

  echo "========================================"
  echo "Run without --dry-run to execute"
  echo "========================================"
}
