#!/usr/bin/env bash
# wave-graph.sh — Wave dependency graph helpers

set -euo pipefail

if [[ -z "${WAVE_GRAPH_LIB_DIR:-}" ]]; then
  WAVE_GRAPH_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

wave_planner_mode() {
  local requested="${HARNESS_WAVE_PLANNER:-auto}"

  case "$requested" in
    auto | bash | python) echo "$requested" ;;
    *) echo "auto" ;;
  esac
}

wave_planner_python_bin() {
  echo "${HARNESS_WAVE_PYTHON_BIN:-python3}"
}

wave_planner_script_path() {
  echo "${HARNESS_WAVE_PLANNER_SCRIPT:-${WAVE_GRAPH_LIB_DIR}/../../scripts/runtime/wave_plan.py}"
}

can_use_python_wave_planner() {
  local python_bin
  local planner_script

  python_bin=$(wave_planner_python_bin)
  planner_script=$(wave_planner_script_path)

  command -v "$python_bin" > /dev/null 2>&1 && [[ -f "$planner_script" ]]
}

wave_planner_is_contract_error() {
  local error_type="${1:-}"

  case "$error_type" in
    invalid_input | invalid_dependency_graph | circular_dependency) return 0 ;;
    *) return 1 ;;
  esac
}

wave_planner_should_fallback() {
  local planner_status="${1:-1}"
  local planner_output="${2:-}"
  local error_type=""

  if [[ "$planner_status" -eq 0 ]]; then
    return 1
  fi

  if [[ -z "$planner_output" ]] || ! command -v jq > /dev/null 2>&1; then
    return 0
  fi

  if ! echo "$planner_output" | jq -e . > /dev/null 2>&1; then
    return 0
  fi

  error_type=$(echo "$planner_output" | jq -r '.error // ""' 2> /dev/null)
  if wave_planner_is_contract_error "$error_type"; then
    return 1
  fi

  return 0
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

validate_task_dependency_graph() {
  local tasks_json="${1:-}"

  if [[ -z "$tasks_json" ]] || ! command -v jq > /dev/null 2>&1; then
    echo '{"valid": false, "error": "invalid_input", "duplicate_ids": [], "missing_dependencies": []}'
    return 1
  fi

  jq -n \
    --argjson tasks "$tasks_json" \
    '
    ($tasks | map(.id)) as $ids |
    {
      valid: true,
      duplicate_ids: ($ids | group_by(.) | map(select(length > 1) | .[0])),
      missing_dependencies: [
        $tasks[] as $task
        | (($task.dependencies // [])[]) as $dep
        | select(($ids | index($dep)) == null)
        | {task_id: $task.id, dependency: $dep}
      ]
    }
    | .valid = ((.duplicate_ids | length) == 0 and (.missing_dependencies | length) == 0)
    '
}

# Internal backend: prefer resolve_task_dependency_layers() unless you are
# implementing fallback logic or planner parity tests.
resolve_task_dependency_layers_bash() {
  local tasks_json="${1:-}"

  if [[ -z "$tasks_json" ]] || ! command -v jq > /dev/null 2>&1; then
    echo '{"ok": false, "error": "invalid_input"}'
    return 1
  fi

  local task_count
  task_count=$(echo "$tasks_json" | jq 'length' 2> /dev/null || echo "0")
  if [[ "$task_count" -eq 0 ]]; then
    echo '{"ok": true, "order": [], "waves": [], "validation": {"valid": true, "duplicate_ids": [], "missing_dependencies": []}, "unresolved": []}'
    return 0
  fi

  local validation
  validation=$(validate_task_dependency_graph "$tasks_json")
  local is_valid
  is_valid=$(echo "$validation" | jq -r '.valid // false' 2> /dev/null)
  if [[ "$is_valid" != "true" ]]; then
    jq -n \
      --argjson validation "$validation" \
      '{
        ok: false,
        error: "invalid_dependency_graph",
        duplicate_ids: ($validation.duplicate_ids // []),
        missing_dependencies: ($validation.missing_dependencies // [])
      }'
    return 1
  fi

  local indegree="{}"
  local adjacency="{}"
  local task

  for task in $(echo "$tasks_json" | jq -r '.[] | @base64'); do
    local task_data task_id deps dep_count
    task_data=$(echo "$task" | base64 --decode)
    task_id=$(echo "$task_data" | jq -r '.id')
    deps=$(echo "$task_data" | jq -c '.dependencies // []')
    dep_count=$(echo "$deps" | jq 'length')
    indegree=$(echo "$indegree" | jq --arg id "$task_id" --argjson count "$dep_count" '.[$id] = $count')
    adjacency=$(echo "$adjacency" | jq --arg id "$task_id" '.[$id] = (.[$id] // [])')
  done

  for task in $(echo "$tasks_json" | jq -r '.[] | @base64'); do
    local task_data task_id
    task_data=$(echo "$task" | base64 --decode)
    task_id=$(echo "$task_data" | jq -r '.id')

    while IFS= read -r dep; do
      [[ -n "$dep" ]] || continue
      adjacency=$(echo "$adjacency" | jq --arg dep "$dep" --arg id "$task_id" '.[$dep] = ((.[$dep] // []) + [$id])')
    done < <(echo "$task_data" | jq -r '.dependencies // [] | .[]')
  done

  local ready="[]"
  while IFS= read -r task_id; do
    [[ -n "$task_id" ]] || continue
    local degree
    degree=$(echo "$indegree" | jq -r --arg id "$task_id" '.[$id] // 0')
    if [[ "$degree" -eq 0 ]]; then
      ready=$(echo "$ready" | jq --arg id "$task_id" '. + [$id]')
    fi
  done < <(echo "$tasks_json" | jq -r '.[].id')

  local order="[]"
  local waves="[]"
  local processed=0

  while [[ $(echo "$ready" | jq 'length') -gt 0 ]]; do
    waves=$(echo "$waves" | jq --argjson ready "$ready" '. + [$ready]')

    local next_ready="[]"
    while IFS= read -r ready_id; do
      [[ -n "$ready_id" ]] || continue
      order=$(echo "$order" | jq --arg id "$ready_id" '. + [$id]')
      processed=$((processed + 1))

      while IFS= read -r neighbor; do
        [[ -n "$neighbor" ]] || continue
        indegree=$(echo "$indegree" | jq --arg id "$neighbor" '.[$id] = ((.[$id] // 0) - 1)')
        local neighbor_degree
        neighbor_degree=$(echo "$indegree" | jq -r --arg id "$neighbor" '.[$id] // 0')
        if [[ "$neighbor_degree" -eq 0 ]]; then
          next_ready=$(echo "$next_ready" | jq --arg id "$neighbor" 'if index($id) == null then . + [$id] else . end')
        fi
      done < <(echo "$adjacency" | jq -r --arg id "$ready_id" '.[$id][]?')
    done < <(echo "$ready" | jq -r '.[]')

    ready="$next_ready"
  done

  if [[ "$processed" -ne "$task_count" ]]; then
    local unresolved
    unresolved=$(echo "$tasks_json" | jq --argjson indegree "$indegree" '[.[] | select(($indegree[.id] // 0) > 0) | {id: .id, dependencies: (.dependencies // [])}]')
    jq -n \
      --argjson order "$order" \
      --argjson waves "$waves" \
      --argjson unresolved "$unresolved" \
      '{
        ok: false,
        error: "circular_dependency",
        order: $order,
        waves: $waves,
        unresolved: $unresolved
      }'
    return 1
  fi

  jq -n \
    --argjson order "$order" \
    --argjson waves "$waves" \
    --argjson validation "$validation" \
    '{
      ok: true,
      order: $order,
      waves: $waves,
      validation: $validation,
      unresolved: []
    }'
}

# Internal backend: prefer resolve_task_dependency_layers() unless you are
# implementing rollout/debug logic or planner parity tests.
resolve_task_dependency_layers_python() {
  local tasks_json="${1:-}"
  local python_bin
  local planner_script

  if [[ -z "$tasks_json" ]]; then
    echo '{"ok": false, "error": "invalid_input"}'
    return 1
  fi

  python_bin=$(wave_planner_python_bin)
  planner_script=$(wave_planner_script_path)

  if ! can_use_python_wave_planner; then
    echo '{"ok": false, "error": "python_planner_unavailable"}'
    return 1
  fi

  printf '%s' "$tasks_json" | "$python_bin" "$planner_script"
}

resolve_task_dependency_layers() {
  local tasks_json="${1:-}"
  local planner_mode
  local python_result=""
  local python_status=0

  planner_mode=$(wave_planner_mode)

  case "$planner_mode" in
    bash)
      resolve_task_dependency_layers_bash "$tasks_json"
      return $?
      ;;
    python)
      resolve_task_dependency_layers_python "$tasks_json"
      return $?
      ;;
    auto)
      if ! can_use_python_wave_planner; then
        echo "[WARN] Python wave planner unavailable, falling back to Bash planner" >&2
        resolve_task_dependency_layers_bash "$tasks_json"
        return $?
      fi

      if python_result=$(resolve_task_dependency_layers_python "$tasks_json"); then
        echo "$python_result"
        return 0
      else
        python_status=$?
      fi

      if wave_planner_should_fallback "$python_status" "$python_result"; then
        echo "[WARN] Python wave planner failed unexpectedly, falling back to Bash planner" >&2
        resolve_task_dependency_layers_bash "$tasks_json"
        return $?
      fi

      echo "$python_result"
      return "$python_status"
      ;;
  esac
}

# Kahn's algorithm for topological sorting
# Usage: topological_sort <tasks_json>
# Returns: JSON array of task IDs in execution order
topological_sort() {
  local tasks_json="${1:-}"

  if [[ -z "$tasks_json" ]] || ! command -v jq > /dev/null 2>&1; then
    echo "[]"
    return 1
  fi

  local resolution
  if ! resolution=$(resolve_task_dependency_layers "$tasks_json"); then
    echo "$resolution"
    return 1
  fi

  echo "$resolution" | jq '.order'
}

# Group tasks into waves based on dependencies
# Usage: group_tasks_into_waves <tasks_json>
# Returns: JSON array of waves, each containing task IDs that can run in parallel
group_tasks_into_waves() {
  local tasks_json="${1:-}"

  if [[ -z "$tasks_json" ]] || ! command -v jq > /dev/null 2>&1; then
    echo "[]"
    return 1
  fi

  local resolution
  if ! resolution=$(resolve_task_dependency_layers "$tasks_json"); then
    echo "$resolution"
    return 1
  fi

  echo "$resolution" | jq '.waves'
}

# Detect circular dependencies
# Usage: detect_circular_dependencies <tasks_json>
# Returns: JSON with cycle info or empty if no cycle
detect_circular_dependencies() {
  local tasks_json="${1:-}"

  if [[ -z "$tasks_json" ]] || ! command -v jq > /dev/null 2>&1; then
    echo '{"error": "invalid_input"}'
    return 1
  fi

  local resolution
  if resolution=$(resolve_task_dependency_layers "$tasks_json"); then
    echo "$resolution" | jq '{
      has_cycle: false,
      cycles: [],
      duplicate_ids: (.validation.duplicate_ids // []),
      missing_dependencies: (.validation.missing_dependencies // [])
    }'
    return 0
  fi

  local error_type
  error_type=$(echo "$resolution" | jq -r '.error // "unknown"' 2> /dev/null)
  if [[ "$error_type" == "circular_dependency" ]]; then
    echo "$resolution" | jq '{
      has_cycle: true,
      cycles: (.unresolved // [])
    }'
  else
    echo "$resolution" | jq '{
      has_cycle: false,
      error: .error,
      duplicate_ids: (.duplicate_ids // []),
      missing_dependencies: (.missing_dependencies // [])
    }'
  fi
}
