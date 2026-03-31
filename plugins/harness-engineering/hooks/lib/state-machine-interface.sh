#!/usr/bin/env bash
# state-machine-interface.sh — State Machine Interface Definitions
# 이 파일은 state-machine.sh과 crash-recovery.sh 간의 인터페이스를 정의합니다.
#
# PURPOSE:
# - 순환 의존성 방지
# - 명확한 API 경계 정의
# - 함수 존재 여부 확인을 위한 가드 제공
#
# USAGE:
# source hooks/lib/state-machine-interface.sh
#
# DEPENDENCY HIERARCHY:
#   json-utils.sh, logging.sh (기본)
#         ↓
#   state-machine-interface.sh (인터페이스)
#         ↓
#   state-machine.sh (핵심 상태 관리)
#         ↓
#   crash-recovery.sh (복구 로직)

set -euo pipefail

# ============================================================================
# State Machine Interface Functions
# ============================================================================

# 상태 머신 함수들이 로드되었는지 확인
ensure_state_machine_loaded() {
  if ! declare -f get_state &>/dev/null; then
    local lib_dir
    lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

    if [[ -f "${lib_dir}/state-machine.sh" ]]; then
      # shellcheck source=state-machine.sh
      source "${lib_dir}/state-machine.sh"
      return 0
    else
      echo "ERROR: state-machine.sh not found" >&2
      return 1
    fi
  fi
  return 0
}

# 크래시 복구 함수들이 로드되었는지 확인
ensure_crash_recovery_loaded() {
  if ! declare -f detect_stuck_state &>/dev/null; then
    local lib_dir
    lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

    # state-machine.sh 먼저 로드 (의존성)
    ensure_state_machine_loaded

    if [[ -f "${lib_dir}/crash-recovery.sh" ]]; then
      # shellcheck source=crash-recovery.sh
      source "${lib_dir}/crash-recovery.sh"
      return 0
    else
      echo "ERROR: crash-recovery.sh not found" >&2
      return 1
    fi
  fi
  return 0
}

# ============================================================================
# Safe Wrapper Functions (의존성 자동 해결)
# ============================================================================

# 안전한 상태 조회
safe_get_state() {
  ensure_state_machine_loaded
  get_state "$@"
}

# 안전한 현재 단계 조회
safe_get_current_phase() {
  ensure_state_machine_loaded
  get_current_phase "$@"
}

safe_get_feature_slug() {
  ensure_state_machine_loaded
  get_feature_slug "$@"
}

safe_set_feature_slug() {
  ensure_state_machine_loaded
  set_feature_slug "$@"
}

# 안전한 상태 전환
safe_transition_state() {
  ensure_state_machine_loaded
  transition_state "$@"
}

# 안전한 스냅샷 생성
safe_create_snapshot() {
  ensure_state_machine_loaded
  create_snapshot "$@"
}

safe_sync_runtime_cache() {
  ensure_state_machine_loaded
  sync_runtime_cache "$@"
}

safe_init_or_repair_state_machine() {
  ensure_state_machine_loaded
  init_or_repair_state_machine "$@"
}

safe_record_runtime_phase_state() {
  ensure_state_machine_loaded
  record_runtime_phase_state "$@"
}

# 안전한 롤백
safe_rollback_to_snapshot() {
  ensure_state_machine_loaded
  rollback_to_snapshot "$@"
}

# 안전한 Stuck 상태 감지
safe_detect_stuck_state() {
  ensure_crash_recovery_loaded
  detect_stuck_state "$@"
}

# 안전한 크래시 분석
safe_analyze_crash() {
  ensure_crash_recovery_loaded
  analyze_crash "$@"
}

# 안전한 상태 복구
safe_recover_state() {
  ensure_crash_recovery_loaded
  recover_state "$@"
}

# ============================================================================
# Interface Constants (중복 정의 방지)
# ============================================================================

# 상태 머신 관련 상수 (state-machine.sh에서 이미 정의된 경우 스킵)
if [[ -z "${STATE_MACHINE_ENGINE_DIR:-}" ]]; then
  readonly STATE_MACHINE_ENGINE_DIR=".harness/engine"
fi

if [[ -z "${STATE_MACHINE_STATE_FILE:-}" ]]; then
  readonly STATE_MACHINE_STATE_FILE="state.json"
fi

if [[ -z "${STATE_MACHINE_TRANSITIONS_FILE:-}" ]]; then
  readonly STATE_MACHINE_TRANSITIONS_FILE="transitions.jsonl"
fi

if [[ -z "${STATE_MACHINE_SNAPSHOTS_DIR:-}" ]]; then
  readonly STATE_MACHINE_SNAPSHOTS_DIR="snapshots"
fi

# 크래시 복구 관련 상수 (crash-recovery.sh에서 이미 정의된 경우 스킵)
if [[ -z "${CRASH_RECOVERY_DIR:-}" ]]; then
  readonly CRASH_RECOVERY_DIR=".harness/recovery"
fi

if [[ -z "${CRASH_FORENSICS_DIR:-}" ]]; then
  readonly CRASH_FORENSICS_DIR=".harness/forensics"
fi

if [[ -z "${CRASH_MAX_ITERATIONS:-}" ]]; then
  readonly CRASH_MAX_ITERATIONS=10
fi

if [[ -z "${CRASH_MAX_PHASE_DURATION_MINUTES:-}" ]]; then
  readonly CRASH_MAX_PHASE_DURATION_MINUTES=30
fi

# PDCA 단계는 state-machine.sh에서 정의됨 (여기서는 정의하지 않음)

# ============================================================================
# Helper Functions
# ============================================================================

# 상태 파일 경로 가져오기
get_state_file_path() {
  local project_root="${1:-}"
  echo "${project_root}/${STATE_MACHINE_ENGINE_DIR}/${STATE_MACHINE_STATE_FILE}"
}

# 전환 파일 경로 가져오기
get_transitions_file_path() {
  local project_root="${1:-}"
  echo "${project_root}/${STATE_MACHINE_ENGINE_DIR}/${STATE_MACHINE_TRANSITIONS_FILE}"
}

# 스냅샷 디렉토리 경로 가져오기
get_snapshots_dir_path() {
  local project_root="${1:-}"
  echo "${project_root}/${STATE_MACHINE_ENGINE_DIR}/${STATE_MACHINE_SNAPSHOTS_DIR}"
}

# 복구 디렉토리 경로 가져오기
get_recovery_dir_path() {
  local project_root="${1:-}"
  echo "${project_root}/${CRASH_RECOVERY_DIR}"
}

# 포렌식 디렉토리 경로 가져오기
get_forensics_dir_path() {
  local project_root="${1:-}"
  echo "${project_root}/${CRASH_FORENSICS_DIR}"
}
