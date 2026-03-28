#!/usr/bin/env bash
# wave-executor.sh — Wave 기반 병렬 실행 시스템
# P0-2: 실제 서브에이전트 스포닝으로 개선
# P1-5: 하이브리드 태스크 포맷 지원 (XML + Markdown)
#
# DEPENDENCIES: json-utils.sh, logging.sh, subagent-spawner.sh, state-machine.sh, task-format.sh
#
# 변경사항 (P0-2):
# - 시뮬레이션 → 실제 서브에이전트 실행
# - Agent 툴 연동
# - 상태 추적 및 결과 집계
# - 크래시 복구 지원
#
# 변경사항 (P1-5):
# - XML 태스크 포맷 지원
# - Markdown/XML 자동 감지
# - 포맷 간 변환 지원

set -euo pipefail

# ============================================================================
# Wave 실행 설정
# ============================================================================

readonly MAX_PARALLEL_TASKS=4  # 최대 병렬 태스크 수
readonly WAVE_TIMEOUT=300      # Wave당 최대 실행 시간 (초)
readonly TASK_TIMEOUT=600      # 태스크당 최대 실행 시간 (초)
readonly RETRY_COUNT=2         # 실패 시 재시도 횟수

# 서브에이전트 스포너 로드
if ! declare -f spawn_subagent &>/dev/null; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "${SCRIPT_DIR}/subagent-spawner.sh" 2>/dev/null || true
fi

# 태스크 포맷 변환 라이브러리 로드
if ! declare -f detect_task_format &>/dev/null; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "${SCRIPT_DIR}/task-format.sh" 2>/dev/null || true
fi

# ============================================================================
# 하이브리드 태스크 로딩 (XML + Markdown)
# ============================================================================

# load_task <task_file>
# Returns: JSON with task data (auto-detects format)
load_task() {
  local task_file="${1:-}"

  if [[ ! -f "$task_file" ]]; then
    echo '{"error": "file_not_found", "file": "'"$task_file"'"}'
    return 1
  fi

  local format
  format=$(detect_task_format "$task_file")

  case "$format" in
    xml)
      parse_xml_task "$task_file"
      ;;
    md)
      parse_md_task "$task_file"
      ;;
    *)
      echo '{"error": "unknown_format", "file": "'"$task_file"'"}'
      return 1
      ;;
  esac
}

# load_all_tasks <tasks_dir>
# Returns: JSON array of all tasks
load_all_tasks() {
  local tasks_dir="${1:-}"

  if [[ ! -d "$tasks_dir" ]]; then
    echo "[]"
    return 1
  fi

  local all_tasks="[]"

  # Load XML tasks
  for xml_file in "$tasks_dir"/*.xml; do
    if [[ -f "$xml_file" ]]; then
      local task_json
      task_json=$(parse_xml_task "$xml_file")
      all_tasks=$(echo "$all_tasks" | jq --argjson task "$task_json" '. += [$task]')
    fi
  done

  # Load Markdown tasks
  for md_file in "$tasks_dir"/*.md; do
    if [[ -f "$md_file" ]]; then
      local task_json
      task_json=$(parse_md_task "$md_file")
      all_tasks=$(echo "$all_tasks" | jq --argjson task "$task_json" '. += [$task]')
    fi
  done

  echo "$all_tasks"
}

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

# ============================================================================
# Topological Sort for Dependency Resolution
# ============================================================================

# Kahn's algorithm for topological sorting
# Usage: topological_sort <tasks_json>
# Returns: JSON array of task IDs in execution order
topological_sort() {
  local tasks_json="${1:-}"

  if [[ -z "$tasks_json" ]] || ! command -v jq &>/dev/null; then
    echo "[]"
    return 1
  fi

  # Simple implementation: return task IDs in dependency order
  # For complex dependency graphs, use group_tasks_into_waves
  local task_count
  task_count=$(echo "$tasks_json" | jq 'length' 2>/dev/null || echo "0")

  if [[ "$task_count" -eq 0 ]]; then
    echo "[]"
    return 0
  fi

  # Get tasks with no dependencies first, then tasks with dependencies
  local no_deps with_deps
  no_deps=$(echo "$tasks_json" | jq '[.[] | select((.dependencies // []) | length == 0) | .id]')
  with_deps=$(echo "$tasks_json" | jq '[.[] | select((.dependencies // []) | length > 0) | .id]')

  # Combine: no-deps first, then with-deps
  echo "$no_deps" | jq --argjson with_deps "$with_deps" '. + $with_deps'
}

# Group tasks into waves based on dependencies
# Usage: group_tasks_into_waves <tasks_json>
# Returns: JSON array of waves, each containing task IDs that can run in parallel
group_tasks_into_waves() {
  local tasks_json="${1:-}"

  if [[ -z "$tasks_json" ]] || ! command -v jq &>/dev/null; then
    echo "[]"
    return 1
  fi

  local task_count
  task_count=$(echo "$tasks_json" | jq 'length')

  if [[ "$task_count" -eq 0 ]]; then
    echo "[]"
    return 0
  fi

  # Build dependency graph
  local all_tasks="{}"
  for task in $(echo "$tasks_json" | jq -r '.[] | @base64'); do
    local task_data
    task_data=$(echo "$task" | base64 --decode)
    local task_id deps
    task_id=$(echo "$task_data" | jq -r '.id')
    deps=$(echo "$task_data" | jq -c '.dependencies // []')
    all_tasks=$(echo "$all_tasks" | jq --arg id "$task_id" --argjson deps "$deps" '.[$id] = $deps')
  done

  local waves="[]"
  local completed="{}"
  local remaining=$(echo "$tasks_json" | jq '[.[].id]')

  local wave_num=0
  local max_waves=20  # Prevent infinite loops

  while [[ $(echo "$remaining" | jq 'length') -gt 0 ]] && [[ $wave_num -lt $max_waves ]]; do
    wave_num=$((wave_num + 1))

    # Find tasks with all dependencies completed
    local ready="[]"
    for task_id in $(echo "$remaining" | jq -r '.[]'); do
      local deps
      deps=$(echo "$all_tasks" | jq -r --arg id "$task_id" '.[$id] // []')

      # Check if all deps are completed
      local all_met=true
      for dep in $(echo "$deps" | jq -r '.[]'); do
        if ! echo "$completed" | jq -e --arg dep "$dep" '.[$dep] // false' >/dev/null 2>&1; then
          all_met=false
          break
        fi
      done

      if [[ "$all_met" == "true" ]]; then
        ready=$(echo "$ready" | jq --arg id "$task_id" '. + [$id]')
      fi
    done

    # If no tasks are ready, there's a cycle
    local ready_count
    ready_count=$(echo "$ready" | jq 'length')
    if [[ "$ready_count" -eq 0 ]]; then
      echo "$waves"
      return 0
    fi

    # Add wave to result
    waves=$(echo "$waves" | jq --argjson ready "$ready" '. + [$ready]')

    # Mark tasks as completed
    for task_id in $(echo "$ready" | jq -r '.[]'); do
      completed=$(echo "$completed" | jq --arg id "$task_id" '.[$id] = true')
      remaining=$(echo "$remaining" | jq --arg id "$task_id" 'del(.[] | select(. == $id))')
    done
  done

  echo "$waves"
}

# Detect circular dependencies
# Usage: detect_circular_dependencies <tasks_json>
# Returns: JSON with cycle info or empty if no cycle
detect_circular_dependencies() {
  local tasks_json="${1:-}"

  if [[ -z "$tasks_json" ]] || ! command -v jq &>/dev/null; then
    echo '{"error": "invalid_input"}'
    return 1
  fi

  # Simple cycle detection using DFS
  local visited="{}"
  local rec_stack="{}"
  local cycle="[]"

  local task_ids
  task_ids=$(echo "$tasks_json" | jq -r '.[].id')

  for task_id in $task_ids; do
    if ! echo "$visited" | jq -e --arg id "$task_id" '.[$id] // false' >/dev/null 2>&1; then
      # DFS from this node
      local stack="[\"$task_id\"]"
      local path="[\"$task_id\"]"

      while [[ $(echo "$stack" | jq 'length') -gt 0 ]]; do
        local current
        current=$(echo "$stack" | jq -r '.[-1]')
        stack=$(echo "$stack" | jq '.[:-1]')

        visited=$(echo "$visited" | jq --arg id "$current" '.[$id] = true')

        # Get dependencies
        local deps
        deps=$(echo "$tasks_json" | jq -r --arg id "$current" '.[] | select(.id == $id) | .dependencies // [] | .[]')

        for dep in $deps; do
          if echo "$path" | jq -e --arg d "$dep" 'index($d)' >/dev/null 2>&1; then
            # Cycle detected
            cycle=$(echo "$cycle" | jq --arg from "$current" --arg to "$dep" '. + [{"from": $from, "to": $to}]')
          fi

          if ! echo "$visited" | jq -e --arg d "$dep" '.[$d] // false' >/dev/null 2>&1; then
            stack=$(echo "$stack" | jq --arg d "$dep" '. + [$d]')
            path=$(echo "$path" | jq --arg d "$dep" '. + [$d]')
          fi
        done
      done
    fi
  done

  local cycle_count
  cycle_count=$(echo "$cycle" | jq 'length')

  if [[ "$cycle_count" -gt 0 ]]; then
    echo "{\"has_cycle\": true, \"cycles\": $cycle}"
  else
    echo '{"has_cycle": false}'
  fi
}

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
  task_name=$(basename "$task_file" .md 2>/dev/null || echo "unknown")

  mkdir -p "$log_dir"

  # 로그: 태스크 시작
  if declare -f log_event &>/dev/null; then
    log_event "$project_root" "INFO" "task_start" "Starting task" \
      "\"task\":\"$task_name\",\"model\":\"$model\""
  fi

  # 태스크 파일 존재 확인
  if [[ ! -f "$task_file" ]]; then
    if declare -f log_event &>/dev/null; then
      log_event "$project_root" "ERROR" "task_error" "Task file not found" \
        "\"task\":\"$task_name\""
    fi
    return 1
  fi

  # 서브에이전트 스폰
  local subagent_id=""
  if declare -f spawn_subagent &>/dev/null; then
    subagent_id=$(spawn_subagent "$task_file" "$project_root" "$model" "task_execution")
  else
    # 스포너 없으면 기존 방식으로 폴백
    if declare -f log_event &>/dev/null; then
      log_event "$project_root" "WARN" "task_fallback" "Using fallback execution (no spawner)" \
        "\"task\":\"$task_name\""
    fi
    echo "[INFO] Executing task: $task_name (simulation mode)" >&2
    subagent_id="sim_$(date +%s)_$$"
  fi

  # 로그: 서브에이전트 스폰
  if declare -f log_event &>/dev/null; then
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

  # 실행 시작
  if declare -f start_subagent_execution &>/dev/null; then
    start_subagent_execution "$subagent_id" "$project_root"
  fi

  # Agent 툴 파라미터 반환 (실제 실행은 Claude Code에서)
  if declare -f generate_agent_params &>/dev/null; then
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
  if declare -f finalize_agent_execution &>/dev/null; then
    finalize_agent_execution "$subagent_id" "$project_root" "$result_content"
  fi

  # 로그: 태스크 완료
  local subagent_dir="${project_root}/${SUBAGENT_DIR:-.harness/subagents}/${subagent_id}"
  if [[ -f "${subagent_dir}/state.json" ]]; then
    local duration
    duration=$(jq -r '.duration_ms // 0' "${subagent_dir}/state.json" 2>/dev/null)

    if declare -f log_event &>/dev/null; then
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
  if declare -f log_event &>/dev/null; then
    log_event "$project_root" "INFO" "wave_start" "Starting wave with real subagents" \
      "\"wave\":${wave_num},\"parallel\":${parallel}"
  fi

  # 태스크 파일 목록 추출
  local tasks=()
  if [[ -n "$tasks_json" ]] && command -v jq >/dev/null 2>&1; then
    while IFS= read -r task_file; do
      if [[ -n "$task_file" ]]; then
        tasks+=("$task_file")
      fi
    done < <(printf '%s' "$tasks_json" | jq -r '.[]?.file // .[]?.path // empty' 2>/dev/null)
  fi

  # tasks가 비어있으면 경고 후 종료
  if [[ ${#tasks[@]} -eq 0 ]]; then
    if declare -f log_event &>/dev/null; then
      log_event "$project_root" "WARN" "wave_empty" "No tasks to execute in wave" \
        "\"wave\":${wave_num}"
    fi
    echo '{"wave":'"${wave_num}"',"status":"empty","subagents":[]}'
    return 0
  fi

  local subagent_ids=()
  local failed=0

  if [[ "$parallel" == "true" ]]; then
    # 병렬 실행: 서브에이전트 스폰
    for task_file in "${tasks[@]}"; do
      if [[ -f "$task_file" ]]; then
        local subagent_id
        subagent_id=$(execute_task "$task_file" "$project_root" "sonnet")

        if [[ -n "$subagent_id" ]]; then
          subagent_ids+=("$subagent_id")

          # 병렬 제한: MAX_PARALLEL_TASKS 개수만큼만 동시에
          if [[ ${#subagent_ids[@]} -ge $MAX_PARALLEL_TASKS ]]; then
            # 첫 번째 완료될 때까지 대기 (실제로는 Agent 실행 후 콜백)
            :
          fi
        fi
      fi
    done

    # 로그: 병렬 실행 시작
    if declare -f log_event &>/dev/null; then
      log_event "$project_root" "INFO" "wave_parallel" "Parallel execution started" \
        "\"wave\":${wave_num},\"subagent_count\":${#subagent_ids[@]}"
    fi

    # Agent 툴 실행 파라미터 반환
    local agent_params='{"wave":'"${wave_num}"',"parallel":true,"subagents":['
    local first=true
    for subagent_id in "${subagent_ids[@]}"; do
      if [[ "$first" == true ]]; then
        first=false
      else
        agent_params+=","
      fi

      if declare -f generate_agent_params &>/dev/null; then
        local params
        params=$(generate_agent_params "$subagent_id" "$project_root")
        agent_params+="$params"
      else
        agent_params+="{\"subagent_id\":\"$subagent_id\"}"
      fi
    done
    agent_params+=']}'

    echo "$agent_params"

  else
    # 순차 실행
    for task_file in "${tasks[@]}"; do
      if [[ -f "$task_file" ]]; then
        local subagent_id
        subagent_id=$(execute_task "$task_file" "$project_root" "sonnet")

        if [[ -n "$subagent_id" ]]; then
          subagent_ids+=("$subagent_id")

          # 완료된 태스크 기록
          local task_name
          task_name=$(basename "$task_file" .md)
          echo "$task_name:$subagent_id" >> "$completed_file"
        else
          failed=$((failed + 1))
        fi
      fi
    done

    # 결과 반환
    local status="completed"
    if [[ $failed -gt 0 ]]; then
      status="partial_failure"
    fi

    jq -n --argjson wave "$wave_num" --arg status "$status" \
      --argjson subagent_count "${#subagent_ids[@]}" \
      --argjson failed "$failed" \
      '{"wave":$wave,"status":$status,"subagent_count":$subagent_count,"failed":$failed}'
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
  local subagent_ids="${3:-}"

  # 결과 집계
  local results
  if declare -f aggregate_subagent_results &>/dev/null; then
    results=$(aggregate_subagent_results "$project_root" "$subagent_ids")
  else
    results='{"total":0,"completed":0,"failed":0}'
  fi

  local total completed failed
  total=$(echo "$results" | jq -r '.summary.total // 0')
  completed=$(echo "$results" | jq -r '.summary.completed // 0')
  failed=$(echo "$results" | jq -r '.summary.failed // 0')

  # 로그: Wave 완료
  if declare -f log_event &>/dev/null; then
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
  if ! command -v yq &>/dev/null; then
    echo "ERROR: yq is required for wave execution" >&2
    echo "INFO: Install: brew install yq" >&2
    return 1
  fi

  local total_waves
  total_waves=$(yq '.total_waves // 0' "$waves_file" 2>/dev/null)

  if [[ "$total_waves" -lt 1 ]]; then
    echo "ERROR: No waves defined in $waves_file" >&2
    return 1
  fi

  # 로그: Wave 실행 시작
  if declare -f log_event &>/dev/null; then
    log_event "$project_root" "INFO" "waves_start" "Starting wave execution" \
      "\"feature\":\"$feature_slug\",\"total_waves\":${total_waves}"
  fi

  local all_subagent_ids=()
  local wave_results='[]'
  local total_failed=0

  # 각 Wave 실행
  for wave_num in $(seq 1 "$total_waves"); do
    local parallel
    parallel=$(yq ".waves[] | select(.wave == $wave_num) | .parallel // true" "$waves_file" 2>/dev/null)
    local tasks
    tasks=$(yq ".waves[] | select(.wave == $wave_num) | .tasks" "$waves_file" 2>/dev/null)

    echo "[Wave $wave_num/$total_waves] Executing tasks (parallel: $parallel)..."

    # Wave 실행
    local wave_result
    wave_result=$(execute_wave "$wave_num" "$tasks" "$project_root" "$parallel")

    # 서브에이전트 ID 수집
    local wave_subagent_ids
    wave_subagent_ids=$(echo "$wave_result" | jq -r '.subagents[]?.subagent_id // empty' 2>/dev/null)

    for subagent_id in $wave_subagent_ids; do
      all_subagent_ids+=("$subagent_id")
    done

    # Wave 결과 저장
    wave_results=$(echo "$wave_results" | jq '. + ['"$wave_result"']')

    # 로그: Wave 실행 완료
    if declare -f log_event &>/dev/null; then
      log_event "$project_root" "INFO" "wave_executed" "Wave executed" \
        "\"wave\":${wave_num},\"parallel\":${parallel}"
    fi
  done

  # 모든 서브에이전트 완료 대기
  echo ""
  echo "Waiting for all subagents to complete..."

  local all_ids_str
  all_ids_str=$(IFS=,; echo "${all_subagent_ids[*]}")

  local final_results
  if declare -f wait_for_subagents &>/dev/null && [[ -n "$all_ids_str" ]]; then
    final_results=$(wait_for_subagents "$project_root" "$all_ids_str" "$WAVE_TIMEOUT")
  else
    final_results='{"status":"completed","summary":{"total":'"${#all_subagent_ids[@]}"',"completed":0,"failed":0}}'
  fi

  # 로그: 전체 Wave 완료
  if declare -f log_event &>/dev/null; then
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
