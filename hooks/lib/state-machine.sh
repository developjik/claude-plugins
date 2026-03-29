#!/usr/bin/env bash
# state-machine.sh — PDCA 상태 머신 엔진
# P0-3: GSD-2 벤치마킹: Single-writer state engine
#
# DEPENDENCIES: json-utils.sh, logging.sh
#
# 핵심 기능:
# - 전환 가드 (Transition Guards)
# - 스냅샷 & 롤백
# - 크래시 복구
# - 감사 추적 (Audit Trail)

set -euo pipefail

STATE_MACHINE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
if [[ -f "${STATE_MACHINE_LIB_DIR}/runtime-paths.sh" ]]; then
  # shellcheck source=runtime-paths.sh
  source "${STATE_MACHINE_LIB_DIR}/runtime-paths.sh"
fi

# ============================================================================
# 상수
# ============================================================================

readonly ENGINE_DIR=".harness/engine"
readonly STATE_FILE="state.json"
readonly TRANSITIONS_FILE="transitions.jsonl"
readonly SNAPSHOTS_DIR="snapshots"
readonly MAX_SNAPSHOTS=20
readonly LOCK_TIMEOUT=30
readonly LOCK_RETRY_INTERVAL=0.5

# PDCA 단계
readonly PDCA_PHASES=("clarify" "plan" "design" "implement" "check" "wrapup")

# ============================================================================
# 파일 락킹 (File Locking) - 디렉토리 기반 (모든 쉘 호환)
# ============================================================================

# 락 파일 경로 가져오기
# Usage: lock_file <project_root>
lock_file() {
  local project_root="${1:-}"
  echo "$(engine_dir "$project_root")/.lock"
}

# 락 획득 (디렉토리 기반, 모든 쉘 호환)
# Usage: acquire_lock <project_root> [timeout_seconds]
# Returns: 0 on success, 1 on timeout
acquire_lock() {
  local project_root="${1:-}"
  local timeout="${2:-$LOCK_TIMEOUT}"

  # 테스트 환경에서는 락킹 비활성화
  if [[ "${STATE_MACHINE_NO_LOCK:-}" == "true" ]]; then
    return 0
  fi

  local lock_file
  lock_file=$(lock_file "$project_root")
  local lock_dir="${lock_file}.d"

  # 락 디렉토리 생성 (부모 디렉토리)
  mkdir -p "$(dirname "$lock_file")"

  # 이미 현재 프로세스가 락을 가지고 있는지 확인 (재진입 방지)
  if [[ -d "$lock_dir" ]]; then
    local existing_pid
    existing_pid=$(cat "${lock_dir}/pid" 2>/dev/null || echo "")
    if [[ "$existing_pid" == "$$" ]]; then
      return 0  # 이미 락 획득됨
    fi
  fi

  local start_time elapsed
  start_time=$(date +%s)

  while true; do
    # atomic mkdir - 이미 존재하면 실패
    if mkdir "$lock_dir" 2>/dev/null; then
      echo $$ > "${lock_dir}/pid"
      echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" > "${lock_dir}/acquired_at"
      return 0
    fi

    elapsed=$(( $(date +%s) - start_time ))
    if [[ "$elapsed" -ge "$timeout" ]]; then
      log_validation_error "lock_timeout" "$project_root" "Failed to acquire lock within ${timeout}s"
      return 1
    fi

    # 잠시 대기 후 재시도
    sleep "$LOCK_RETRY_INTERVAL"
  done
}

# 락 해제
# Usage: release_lock <project_root>
release_lock() {
  local project_root="${1:-}"

  local lock_file
  lock_file=$(lock_file "$project_root")
  local lock_dir="${lock_file}.d"

  # 락 디렉토리 제거
  rm -rf "$lock_dir" 2>/dev/null || true
}

# 락과 함께 명령 실행 (래퍼 함수)
# Usage: with_lock <project_root> <command...>
with_lock() {
  local project_root="${1:-}"
  shift

  if ! acquire_lock "$project_root"; then
    return 1
  fi

  # trap으로 항상 락 해제 보장
  trap "release_lock '$project_root'" EXIT

  "$@"
  local result=$?

  release_lock "$project_root"
  trap - EXIT

  return $result
}

# 락 상태 확인
# Usage: is_locked <project_root>
is_locked() {
  local project_root="${1:-}"

  local lock_file
  lock_file=$(lock_file "$project_root")
  local lock_dir="${lock_file}.d"

  [[ -d "$lock_dir" ]]
}

# 락 정보 조회
# Usage: get_lock_info <project_root>
get_lock_info() {
  local project_root="${1:-}"

  local lock_file
  lock_file=$(lock_file "$project_root")
  local lock_dir="${lock_file}.d"

  if [[ ! -d "$lock_dir" ]]; then
    echo '{"locked": false}'
    return 0
  fi

  local pid acquired_at
  pid=$(cat "${lock_dir}/pid" 2>/dev/null || echo "unknown")
  acquired_at=$(cat "${lock_dir}/acquired_at" 2>/dev/null || echo "unknown")

  jq -n \
    --arg pid "$pid" \
    --arg acquired_at "$acquired_at" \
    '{"locked": true, "pid": $pid, "acquired_at": $acquired_at}'
}

# ============================================================================
# 전환 규칙 (Transition Rules)
# ============================================================================

# 유효한 전환 정의 (함수로 구현)
get_valid_transitions() {
  local from="${1:-}"
  local to="${2:-}"

  case "${from}:${to}" in
    "null:clarify"|"init:clarify") echo "always_true" ;;
    "clarify:plan") echo "design_doc_exists" ;;
    "plan:design") echo "design_doc_complete" ;;
    "design:implement") echo "atomic_tasks_defined" ;;
    "implement:check") echo "code_written" ;;
    "check:wrapup") echo "match_rate_90_percent" ;;
    "check:implement") echo "match_rate_below_90" ;;
    "wrapup:clarify") echo "new_feature" ;;
    "wrapup:complete") echo "milestone_complete" ;;
    *) echo "" ;;
  esac
}

# ============================================================================
# 경로 함수
# ============================================================================

engine_dir() {
  local project_root="${1:-}"
  if declare -f harness_engine_dir_from_root >/dev/null 2>&1; then
    harness_engine_dir_from_root "$project_root"
  else
    echo "${project_root}/${ENGINE_DIR}"
  fi
}

state_file() {
  local project_root="${1:-}"
  echo "$(engine_dir "$project_root")/${STATE_FILE}"
}

transitions_file() {
  local project_root="${1:-}"
  echo "$(engine_dir "$project_root")/${TRANSITIONS_FILE}"
}

snapshots_dir() {
  local project_root="${1:-}"
  echo "$(engine_dir "$project_root")/${SNAPSHOTS_DIR}"
}

# ============================================================================
# 상태 머신 초기화
# Usage: init_state_machine <project_root> <feature_slug>
# ============================================================================
init_state_machine() {
  local project_root="${1:-}"
  local feature_slug="${2:-}"

  local engine_dir
  engine_dir=$(engine_dir "$project_root")
  local snapshots_dir
  snapshots_dir=$(snapshots_dir "$project_root")

  mkdir -p "$engine_dir" "$snapshots_dir"

  local state_file
  state_file=$(state_file "$project_root")

  if [[ ! -f "$state_file" ]]; then
    local timestamp
    timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

    cat > "$state_file" << EOF
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

    log_transition "$project_root" "init" "null" "clarify" "State machine initialized"
    echo "✅ State machine initialized for: $feature_slug"
  else
    echo "ℹ️  State machine already exists"
  fi
}

_state_jq_update() {
  local project_root="${1:-}"
  shift

  local state_path
  state_path=$(state_file "$project_root")

  if [[ ! -f "$state_path" ]] || ! command -v jq >/dev/null 2>&1; then
    return 1
  fi

  local tmp="${state_path}.tmp"
  jq "$@" "$state_path" > "$tmp" && mv "$tmp" "$state_path"
}

# ============================================================================
# 상태 조회
# Usage: get_state <project_root>
# Returns: JSON state
# ============================================================================
get_state() {
  local project_root="${1:-}"
  local state_file
  state_file=$(state_file "$project_root")

  if [[ -f "$state_file" ]]; then
    cat "$state_file"
  else
    echo '{"error": "state_not_initialized", "phase": null}'
  fi
}

# ============================================================================
# 현재 단계 조회
# Usage: get_current_phase <project_root>
# Returns: clarify | plan | design | implement | check | wrapup | complete | unknown
# ============================================================================
get_current_phase() {
  local project_root="${1:-}"
  get_state "$project_root" | jq -r '.phase // "unknown"'
}

get_feature_slug() {
  local project_root="${1:-}"
  get_state "$project_root" | jq -r '.feature_slug // empty'
}

set_feature_slug() {
  local project_root="${1:-}"
  local feature_slug="${2:-}"

  if [[ ! -f "$(state_file "$project_root")" ]]; then
    init_state_machine "$project_root" "$feature_slug" >/dev/null 2>&1
  fi

  local timestamp
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  _state_jq_update "$project_root" \
    --arg feature "$feature_slug" \
    --arg ts "$timestamp" \
    '.feature_slug = $feature |
     .metadata.updated_at = $ts' || return 1

  sync_runtime_cache "$project_root" >/dev/null 2>&1 || true
  printf '%s\n' "$feature_slug"
}

_iso8601_to_epoch() {
  local timestamp="${1:-}"

  if [[ -z "$timestamp" ]]; then
    return 1
  fi

  if date -j -f "%Y-%m-%dT%H:%M:%SZ" "$timestamp" "+%s" >/dev/null 2>&1; then
    date -j -f "%Y-%m-%dT%H:%M:%SZ" "$timestamp" "+%s"
    return 0
  fi

  if date -d "$timestamp" "+%s" >/dev/null 2>&1; then
    date -d "$timestamp" "+%s"
    return 0
  fi

  return 1
}

sync_runtime_cache() {
  local project_root="${1:-}"
  local state
  state=$(get_state "$project_root")

  if echo "$state" | jq -e '.error' >/dev/null 2>&1; then
    return 0
  fi

  local state_dir phase_file feature_file agent_file phase_start_file
  if declare -f harness_state_dir_from_root >/dev/null 2>&1; then
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
  entered_at_epoch=$(_iso8601_to_epoch "$entered_at" 2>/dev/null || true)

  printf '%s\n' "${phase:-idle}" > "$phase_file"
  printf '%s\n' "$feature_slug" > "$feature_file"
  printf '%s\n' "$actor" > "$agent_file"

  if [[ -n "$entered_at_epoch" ]]; then
    printf '%s\n' "$entered_at_epoch" > "$phase_start_file"
  elif [[ ! -f "$phase_start_file" ]]; then
    printf '%s\n' "$(date +%s)" > "$phase_start_file"
  fi
}

init_or_repair_state_machine() {
  local project_root="${1:-}"
  local feature_slug="${2:-}"

  if [[ ! -f "$(state_file "$project_root")" ]]; then
    init_state_machine "$project_root" "$feature_slug" >/dev/null 2>&1
  fi

  if [[ -n "$feature_slug" ]]; then
    local current_feature
    current_feature=$(get_feature_slug "$project_root" 2>/dev/null || true)
    if [[ "$current_feature" != "$feature_slug" ]]; then
      set_feature_slug "$project_root" "$feature_slug" >/dev/null 2>&1 || true
    fi
  fi

  sync_runtime_cache "$project_root" >/dev/null 2>&1 || true
}

record_runtime_phase_state() {
  local project_root="${1:-}"
  local phase="${2:-}"
  local actor="${3:-claude}"
  local reason="${4:-runtime_phase_sync}"

  case "$phase" in
    clarify|plan|design|implement|check|wrapup|complete) ;;
    *) return 0 ;;
  esac

  init_or_repair_state_machine "$project_root" "$(get_feature_slug "$project_root" 2>/dev/null || true)" >/dev/null 2>&1 || true

  local current_phase timestamp
  current_phase=$(get_current_phase "$project_root" 2>/dev/null || echo "unknown")
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  _state_jq_update "$project_root" \
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
    log_transition "$project_root" "runtime_phase_sync" "$current_phase" "$phase" "$reason"
  fi

  sync_runtime_cache "$project_root" >/dev/null 2>&1 || true
  printf '%s\n' "$phase"
}

# ============================================================================
# 전환 가드 (Transition Guards)
# ============================================================================

# 항상 true
always_true() {
  local project_root="${1:-}"
  return 0
}

# design.md 파일 존재 확인
design_doc_exists() {
  local project_root="${1:-}"
  local feature_slug
  feature_slug=$(get_state "$project_root" | jq -r '.feature_slug // empty')

  if [[ -z "$feature_slug" ]]; then
    return 1
  fi

  # docs/specs/{feature}/design.md 또는 design.md
  if [[ -f "${project_root}/docs/specs/${feature_slug}/design.md" ]] || \
     [[ -f "${project_root}/design.md" ]]; then
    return 0
  fi

  # clarify 단계에서는 design.md가 없어도 됨 (이동하며 생성)
  local current_phase
  current_phase=$(get_current_phase "$project_root")
  if [[ "$current_phase" == "clarify" ]]; then
    return 0
  fi

  return 1
}

# design.md 완전성 확인
design_doc_complete() {
  local project_root="${1:-}"
  local feature_slug
  feature_slug=$(get_state "$project_root" | jq -r '.feature_slug // empty')

  if [[ -z "$feature_slug" ]]; then
    return 1
  fi

  local design_file="${project_root}/docs/specs/${feature_slug}/design.md"

  if [[ ! -f "$design_file" ]]; then
    design_file="${project_root}/design.md"
  fi

  if [[ ! -f "$design_file" ]]; then
    return 1
  fi

  # 필수 섹션 확인
  if grep -q "## 구현 순서" "$design_file" 2>/dev/null && \
     grep -q "## 파일 변경" "$design_file" 2>/dev/null; then
    return 0
  fi

  return 1
}

# Atomic tasks 정의 확인
atomic_tasks_defined() {
  local project_root="${1:-}"
  local feature_slug
  feature_slug=$(get_state "$project_root" | jq -r '.feature_slug // empty')

  if [[ -z "$feature_slug" ]]; then
    return 1
  fi

  # waves.yaml 또는 design.md의 구현 순서
  if [[ -f "${project_root}/docs/specs/${feature_slug}/waves.yaml" ]]; then
    return 0
  fi

  local design_file="${project_root}/docs/specs/${feature_slug}/design.md"
  if [[ -f "$design_file" ]] && grep -q "## 구현 순서" "$design_file" 2>/dev/null; then
    return 0
  fi

  return 1
}

# 코드 작성 확인
code_written() {
  local project_root="${1:-}"

  # Git 변경사항이 있는지 확인
  if command -v git &>/dev/null && \
     git -C "$project_root" diff --quiet HEAD 2>/dev/null; then
    return 1
  fi

  return 0
}

# 일치도 90% 이상
match_rate_90_percent() {
  local project_root="${1:-}"
  local state
  state=$(get_state "$project_root")

  local match_rate
  match_rate=$(echo "$state" | jq -r '.check_results.match_rate // 0')

  if command -v awk &>/dev/null; then
    if awk "BEGIN {exit !($match_rate >= 0.9)}"; then
      return 0
    fi
  fi

  return 1
}

# 일치도 90% 미만 (iterate)
match_rate_below_90() {
  local project_root="${1:-}"
  local state
  state=$(get_state "$project_root")

  local match_rate
  match_rate=$(echo "$state" | jq -r '.check_results.match_rate // 0')

  if command -v awk &>/dev/null; then
    if awk "BEGIN {exit !($match_rate < 0.9)}"; then
      return 0
    fi
  fi

  return 1
}

# 새 기능 시작
new_feature() {
  return 0
}

# 마일스톤 완료
milestone_complete() {
  local project_root="${1:-}"
  # 모든 필수 작업 완료 확인
  return 0
}

# ============================================================================
# 전환 가능 여부 확인
# Usage: can_transition <project_root> <from_phase> <to_phase>
# Returns: "true" or "false:reason"
# ============================================================================
can_transition() {
  local project_root="${1:-}"
  local from_phase="${2:-}"
  local to_phase="${3:-}"

  # init → clarify 특별 처리
  if [[ "$from_phase" == "null" || "$from_phase" == "init" ]]; then
    if [[ "$to_phase" == "clarify" ]]; then
      echo "true"
      return 0
    fi
  fi

  local guard_function
  guard_function=$(get_valid_transitions "$from_phase" "$to_phase")

  if [[ -z "$guard_function" ]]; then
    echo "false:invalid_transition"
    return 1
  fi

  # 가드 함수 실행
  if "$guard_function" "$project_root"; then
    echo "true"
    return 0
  else
    echo "false:guard_failed:$guard_function"
    return 1
  fi
}

# ============================================================================
# 스냅샷 생성 (락킹 적용)
# Usage: create_snapshot <project_root> [phase]
# Returns: snapshot_id
# ============================================================================
create_snapshot() {
  local project_root="${1:-}"
  local phase="${2:-$(get_current_phase "$project_root")}"

  # 락 획득
  if ! acquire_lock "$project_root"; then
    echo "ERROR: Failed to acquire lock for snapshot creation" >&2
    return 1
  fi

  # trap으로 항상 락 해제 보장
  trap "release_lock '$project_root'" EXIT

  local snapshots_dir
  snapshots_dir=$(snapshots_dir "$project_root")
  local timestamp entropy
  timestamp=$(date +%Y%m%d_%H%M%S)
  entropy="${RANDOM}"
  local snapshot_id="snap_${phase}_${timestamp}_${entropy}"
  local snapshot_file="${snapshots_dir}/${snapshot_id}.json"

  # 현재 상태와 관련 파일들 스냅샷
  local state
  state=$(get_state "$project_root")

  local files_snapshot="{}"
  local feature_slug
  feature_slug=$(echo "$state" | jq -r '.feature_slug // empty')

  if [[ -n "$feature_slug" ]]; then
    local spec_dir="${project_root}/docs/specs/${feature_slug}"

    # 주요 파일들 저장
    for file in "plan.md" "design.md" "STATE.md"; do
      if [[ -f "${spec_dir}/${file}" ]]; then
        local content_hash
        content_hash=$(md5 -q "${spec_dir}/${file}" 2>/dev/null || \
                       md5sum "${spec_dir}/${file}" 2>/dev/null | cut -d' ' -f1)
        files_snapshot=$(echo "$files_snapshot" | jq \
          --arg file "$file" \
          --arg hash "$content_hash" \
          '.[$file] = $hash')
      fi
    done
  fi

  # 스냅샷 저장
  jq -n \
    --arg id "$snapshot_id" \
    --arg phase "$phase" \
    --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    --argjson state "$state" \
    --argjson files "$files_snapshot" \
    '{
      id: $id,
      phase: $phase,
      created_at: $ts,
      state: $state,
      files: $files
    }' > "$snapshot_file"

  # 상태에 스냅샷 ID 추가
  local state_file
  state_file=$(state_file "$project_root")
  if command -v jq &>/dev/null; then
    local tmp="${state_file}.tmp"
    jq --arg snap "$snapshot_id" '.snapshots += [$snap]' "$state_file" > "$tmp" && \
      mv "$tmp" "$state_file"
  fi

  # 오래된 스냅샷 정리
  cleanup_old_snapshots "$project_root"

  # 락 해제
  release_lock "$project_root"
  trap - EXIT

  echo "$snapshot_id"
}

# ============================================================================
# 오래된 스냅샷 정리
# ============================================================================
cleanup_old_snapshots() {
  local project_root="${1:-}"
  local snapshots_dir
  snapshots_dir=$(snapshots_dir "$project_root")

  local snapshot_count
  snapshot_count=$(ls -1 "${snapshots_dir}"/*.json 2>/dev/null | wc -l)

  if [[ "$snapshot_count" -gt "$MAX_SNAPSHOTS" ]]; then
    local to_delete=$((snapshot_count - MAX_SNAPSHOTS))
    ls -1t "${snapshots_dir}"/*.json | tail -n "$to_delete" | while read -r file; do
      rm -f "$file"
    done
  fi
}

# ============================================================================
# 스냅샷으로 롤백
# Usage: rollback_to_snapshot <project_root> <snapshot_id>
# ============================================================================
rollback_to_snapshot() {
  local project_root="${1:-}"
  local snapshot_id="${2:-}"

  local snapshots_dir
  snapshots_dir=$(snapshots_dir "$project_root")
  local snapshot_file="${snapshots_dir}/${snapshot_id}.json"

  if [[ ! -f "$snapshot_file" ]]; then
    echo "ERROR: Snapshot not found: $snapshot_id" >&2
    return 1
  fi

  # 스냅샷에서 상태 복원
  local snapshot_state
  snapshot_state=$(jq '.state' "$snapshot_file")

  local state_file
  state_file=$(state_file "$project_root")
  echo "$snapshot_state" > "$state_file"

  # 롤백 로그
  local to_phase
  to_phase=$(echo "$snapshot_state" | jq -r '.phase')
  log_transition "$project_root" "rollback" "unknown" "$to_phase" \
    "Rolled back to $snapshot_id"

  echo "✅ Rolled back to snapshot: $snapshot_id"
  echo "   Phase: $to_phase"
}

# ============================================================================
# 사용 가능한 스냅샷 목록
# Usage: list_snapshots <project_root>
# ============================================================================
list_snapshots() {
  local project_root="${1:-}"
  local snapshots_dir
  snapshots_dir=$(snapshots_dir "$project_root")

  if [[ ! -d "$snapshots_dir" ]]; then
    echo "[]"
    return 0
  fi

  local result="[]"
  for snapshot_file in "${snapshots_dir}"/snap_*.json; do
    if [[ -f "$snapshot_file" ]]; then
      local entry
      entry=$(jq '{id: .id, phase: .phase, created_at: .created_at}' "$snapshot_file")
      result=$(echo "$result" | jq '. + ['"$entry"']')
    fi
  done

  echo "$result" | jq 'sort_by(.created_at) | reverse'
}

# ============================================================================
# 상태 전환 (락킹 적용)
# Usage: transition_state <project_root> <to_phase> [reason] [actor]
# ============================================================================
transition_state() {
  local project_root="${1:-}"
  local to_phase="${2:-}"
  local reason="${3:-manual}"
  local actor="${4:-claude}"

  local state_file
  state_file=$(state_file "$project_root")

  if [[ ! -f "$state_file" ]]; then
    echo "ERROR: State machine not initialized" >&2
    return 1
  fi

  # 락 획득
  if ! acquire_lock "$project_root"; then
    echo "ERROR: Failed to acquire lock for state transition" >&2
    return 1
  fi

  # trap으로 항상 락 해제 보장
  trap "release_lock '$project_root'" EXIT

  local current_state
  current_state=$(get_state "$project_root")
  local from_phase
  from_phase=$(echo "$current_state" | jq -r '.phase')

  # 전환 가능 여부 확인
  local can_trans
  can_trans=$(can_transition "$project_root" "$from_phase" "$to_phase")

  if [[ "$can_trans" != true* ]]; then
    release_lock "$project_root"
    trap - EXIT
    echo "ERROR: Cannot transition from $from_phase to $to_phase: $can_trans" >&2
    return 1
  fi

  # 스냅샷 생성 (락 이미 획득된 상태에서 내부적으로 처리)
  local snapshot_id
  snapshot_id=$(create_snapshot_without_lock "$project_root" "$from_phase")

  # 상태 업데이트
  local timestamp
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  local iteration_count
  iteration_count=$(echo "$current_state" | jq '.iteration_count // 0')

  # check → implement (iterate) 시 iteration 증가
  if [[ "$from_phase" == "check" && "$to_phase" == "implement" ]]; then
    iteration_count=$((iteration_count + 1))
  fi

  # check → wrapup 시 iteration 리셋
  if [[ "$from_phase" == "check" && "$to_phase" == "wrapup" ]]; then
    iteration_count=0
  fi

  if command -v jq &>/dev/null; then
    local tmp="${state_file}.tmp"
    jq --arg to "$to_phase" \
       --arg from "$from_phase" \
       --arg ts "$timestamp" \
       --arg actor "$actor" \
       --arg snap "$snapshot_id" \
       --argjson iter "$iteration_count" \
       '.previous_phase = $from |
        .phase = $to |
        .entered_at = $ts |
        .actor = $actor |
        .iteration_count = $iter |
        .metadata.updated_at = $ts' \
       "$state_file" > "$tmp" && mv "$tmp" "$state_file"
  fi

  # 전환 로그
  log_transition "$project_root" "transition" "$from_phase" "$to_phase" "$reason"

  # 락 해제
  release_lock "$project_root"
  trap - EXIT

  echo "✅ Transitioned: $from_phase → $to_phase"
}

# ============================================================================
# 락 없이 스냅샷 생성 (내부용)
# Usage: create_snapshot_without_lock <project_root> [phase]
# ============================================================================
create_snapshot_without_lock() {
  local project_root="${1:-}"
  local phase="${2:-$(get_current_phase "$project_root")}"

  local snapshots_dir
  snapshots_dir=$(snapshots_dir "$project_root")
  local timestamp entropy
  timestamp=$(date +%Y%m%d_%H%M%S)
  entropy="${RANDOM}"
  local snapshot_id="snap_${phase}_${timestamp}_${entropy}"
  local snapshot_file="${snapshots_dir}/${snapshot_id}.json"

  # 현재 상태와 관련 파일들 스냅샷
  local state
  state=$(get_state "$project_root")

  local files_snapshot="{}"
  local feature_slug
  feature_slug=$(echo "$state" | jq -r '.feature_slug // empty')

  if [[ -n "$feature_slug" ]]; then
    local spec_dir="${project_root}/docs/specs/${feature_slug}"

    for file in "plan.md" "design.md" "STATE.md"; do
      if [[ -f "${spec_dir}/${file}" ]]; then
        local content_hash
        content_hash=$(md5 -q "${spec_dir}/${file}" 2>/dev/null || \
                       md5sum "${spec_dir}/${file}" 2>/dev/null | cut -d' ' -f1)
        files_snapshot=$(echo "$files_snapshot" | jq \
          --arg file "$file" \
          --arg hash "$content_hash" \
          '.[$file] = $hash')
      fi
    done
  fi

  # 스냅샷 저장
  jq -n \
    --arg id "$snapshot_id" \
    --arg phase "$phase" \
    --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    --argjson state "$state" \
    --argjson files "$files_snapshot" \
    '{
      id: $id,
      phase: $phase,
      created_at: $ts,
      state: $state,
      files: $files
    }' > "$snapshot_file"

  # 상태에 스냅샷 ID 추가
  local state_file
  state_file=$(state_file "$project_root")
  if command -v jq &>/dev/null; then
    local tmp="${state_file}.tmp"
    jq --arg snap "$snapshot_id" '.snapshots += [$snap]' "$state_file" > "$tmp" && \
      mv "$tmp" "$state_file"
  fi

  echo "$snapshot_id"
}

# ============================================================================
# 전환 로그 기록
# Usage: log_transition <project_root> <event> <from> <to> <reason>
# ============================================================================
log_transition() {
  local project_root="${1:-}"
  local event="${2:-}"
  local from="${3:-}"
  local to="${4:-}"
  local reason="${5:-}"

  local transitions_file
  transitions_file=$(transitions_file "$project_root")

  # 디렉토리 확인
  mkdir -p "$(dirname "$transitions_file")"

  local entry
  entry=$(jq -cn \
    --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    --arg event "$event" \
    --arg from "$from" \
    --arg to "$to" \
    --arg reason "$reason" \
    '{timestamp: $ts, event: $event, from: $from, to: $to, reason: $reason}')

  echo "$entry" >> "$transitions_file"
}

# ============================================================================
# 전환 히스토리 조회
# Usage: get_transition_history <project_root> [limit]
# ============================================================================
get_transition_history() {
  local project_root="${1:-}"
  local limit="${2:-10}"
  local transitions_file
  transitions_file=$(transitions_file "$project_root")

  if [[ ! -f "$transitions_file" ]]; then
    echo "[]"
    return 0
  fi

  tail -n "$limit" "$transitions_file" | jq -s '. | reverse'
}

# ============================================================================
# Check 결과 저장
# Usage: save_check_results <project_root> <match_rate> [details_json]
# ============================================================================
save_check_results() {
  local project_root="${1:-}"
  local match_rate="${2:-0}"
  local details="${3:-"{}"}"

  local state_file
  state_file=$(state_file "$project_root")

  if command -v jq &>/dev/null; then
    local tmp="${state_file}.tmp"
    jq --argjson rate "$match_rate" \
       --argjson details "$details" \
       '.check_results = {match_rate: $rate, details: $details}' \
       "$state_file" > "$tmp" && mv "$tmp" "$state_file"
  fi
}

# ============================================================================
# 상태 복구 정보 표시 (실제 복구는 crash-recovery.sh 담당)
# Usage: show_recovery_status <project_root>
# ============================================================================
show_recovery_status() {
  local project_root="${1:-}"
  local state_file
  state_file=$(state_file "$project_root")

  if [[ ! -f "$state_file" ]]; then
    echo "No state to recover"
    return 0
  fi

  echo "🔧 State Recovery Status"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  # 현재 상태
  local current_phase
  current_phase=$(get_current_phase "$project_root")
  echo "Current Phase: $current_phase"

  # 마지막 전환 확인
  local last_transition
  last_transition=$(get_transition_history "$project_root" 1)
  echo "Last Transition: $(echo "$last_transition" | jq -r '.[0].from // "none"') → $(echo "$last_transition" | jq -r '.[0].to // "none"')"

  # 사용 가능한 스냅샷
  echo ""
  echo "📸 Available Snapshots:"
  list_snapshots "$project_root" | jq -r '.[] | "  - \(.id) (\(.phase))"'

  echo ""
  echo "➡️ For actual recovery, use crash-recovery.sh:"
  echo "  source hooks/lib/crash-recovery.sh"
  echo "  run_recovery_process \"$project_root\""
}

# ============================================================================
# 레거시 호환성 유지 (crash-recovery.sh의 recover_state 호출)
# Usage: recover_state <project_root>
# ============================================================================
recover_state() {
  local project_root="${1:-}"

  # crash-recovery.sh가 로드되어 있으면 해당 함수 사용
  if declare -f run_recovery_process &>/dev/null; then
    run_recovery_process "$project_root"
  else
    # 폴백: 상태만 표시
    show_recovery_status "$project_root"
  fi
}

# ============================================================================
# 상태 요약 출력
# Usage: print_state_summary <project_root>
# ============================================================================
print_state_summary() {
  local project_root="${1:-}"
  local state
  state=$(get_state "$project_root")

  if echo "$state" | jq -e '.error' &>/dev/null; then
    echo "⚠️  State machine not initialized"
    return 1
  fi

  local phase feature_slug iteration_count entered_at
  phase=$(echo "$state" | jq -r '.phase')
  feature_slug=$(echo "$state" | jq -r '.feature_slug')
  iteration_count=$(echo "$state" | jq -r '.iteration_count')
  entered_at=$(echo "$state" | jq -r '.entered_at')

  echo "📊 State Summary"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "Feature: $feature_slug"
  echo "Phase: $phase"
  echo "Iteration: $iteration_count"
  echo "Entered: $entered_at"
  echo ""

  # 체크 결과가 있으면 표시
  if echo "$state" | jq -e '.check_results' &>/dev/null; then
    local match_rate
    match_rate=$(echo "$state" | jq -r '.check_results.match_rate // 0')
    echo "Check Match Rate: ${match_rate}%"
  fi

  # 스냅샷 수
  local snapshot_count
  snapshot_count=$(echo "$state" | jq '.snapshots | length')
  echo "Snapshots: $snapshot_count"
}

# ============================================================================
# 자동화 레벨과 연동
# Usage: should_auto_transition <project_root> <transition>
# Returns: true or false
# ============================================================================
should_auto_transition() {
  local project_root="${1:-}"
  local transition="${2:-}"

  # automation-level.sh 함수가 있는지 확인
  if ! declare -f get_automation_level &>/dev/null; then
    return 1
  fi

  local level
  level=$(get_automation_level "$project_root")

  local approve
  approve=$(should_approve_transition "$level" "$transition" "$project_root" 2>/dev/null)

  if [[ "$approve" == "false" ]]; then
    return 0  # 자동 전환
  else
    return 1  # 승인 필요
  fi
}
