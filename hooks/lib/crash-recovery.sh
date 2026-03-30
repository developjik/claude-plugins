#!/usr/bin/env bash
# crash-recovery.sh — Crash Recovery and Forensics System
# P1-3: State machine based recovery and root cause analysis
#
# DEPENDENCIES: json-utils.sh, logging.sh, state-machine-interface.sh
#
# DEPENDENCY HIERARCHY:
#   json-utils.sh, logging.sh (기본)
#         ↓
#   state-machine-interface.sh (인터페이스)
#         ↓
#   state-machine.sh (핵심 상태 관리)
#         ↓
#   crash-recovery.sh (복구 로직) ← 이 파일

set -euo pipefail

# ============================================================================
# Constants
# ============================================================================

readonly RECOVERY_DIR=".harness/recovery"
readonly FORENSICS_DIR=".harness/forensics"
readonly MAX_ITERATIONS=10
readonly MAX_PHASE_DURATION_MINUTES=30
readonly RECOVERY_LOG="recovery.log"

if [[ -z "${CRASH_RECOVERY_LIB_DIR:-}" ]]; then
  CRASH_RECOVERY_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
fi

# ============================================================================
# Dependency Loading (인터페이스 사용)
# ============================================================================

_load_dependencies() {
  if [[ -f "${CRASH_RECOVERY_LIB_DIR}/state-machine-interface.sh" ]]; then
    # shellcheck source=state-machine-interface.sh
    source "${CRASH_RECOVERY_LIB_DIR}/state-machine-interface.sh"
  fi
}

if ! declare -f ensure_state_machine_loaded > /dev/null 2>&1; then
  _load_dependencies
fi

# ============================================================================
# 내부 모듈 로드
# ============================================================================
if ! declare -f detect_stuck_state > /dev/null 2>&1; then
  # shellcheck source=hooks/lib/crash-detection.sh
  source "${CRASH_RECOVERY_LIB_DIR}/crash-detection.sh"
fi

if ! declare -f analyze_crash > /dev/null 2>&1; then
  # shellcheck source=hooks/lib/crash-report.sh
  source "${CRASH_RECOVERY_LIB_DIR}/crash-report.sh"
fi

# ============================================================================
# State Recovery (인터페이스 사용)
# ============================================================================

# Recover state
# Usage: recover_state <project_root> <option_id> [snapshot_id]
recover_state() {
  local project_root="${1:-}"
  local option_id="${2:-}"
  local snapshot_id="${3:-}"

  ensure_state_machine_loaded

  local recovery_dir="${project_root}/${RECOVERY_DIR}"
  mkdir -p "$recovery_dir"

  local timestamp
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  local success=false
  local message=""

  case "$option_id" in
    resume)
      success=true
      message="Ready to resume from current state"
      ;;
    rollback)
      if [[ -n "$snapshot_id" ]] && declare -f rollback_to_snapshot > /dev/null 2>&1; then
        if rollback_to_snapshot "$project_root" "$snapshot_id" 2> /dev/null; then
          success=true
          message="Rolled back to snapshot: $snapshot_id"
        else
          message="Failed to rollback"
        fi
      else
        message="No snapshot ID or function unavailable"
      fi
      ;;
    reset_to_design)
      local state_file="${project_root}/.harness/engine/state.json"
      if [[ -f "$state_file" ]]; then
        local tmp="${state_file}.tmp"
        jq ".phase = \"design\" | .iteration_count = 0 | .last_transition_at = \"$timestamp\"" "$state_file" > "$tmp" \
          && mv "$tmp" "$state_file"
        success=true
        message="Reset to design phase"
      fi
      ;;
    manual)
      success=true
      message="Manual intervention mode"
      ;;
    *)
      message="Unknown recovery option"
      ;;
  esac

  local log_file="${recovery_dir}/${RECOVERY_LOG}"
  echo "[${timestamp}] Recovery: ${option_id} - Success: ${success}" >> "$log_file"

  jq -c -n \
    --argjson success "$success" \
    --arg option "$option_id" \
    --arg ts "$timestamp" \
    --arg message "$message" \
    '{success: $success, option: $option, timestamp: $ts, message: $message}'
}

# ============================================================================
# Checkpoint Management (인터페이스 사용)
# ============================================================================

# Create recovery checkpoint
# Usage: create_recovery_checkpoint <project_root> <phase> [description]
create_recovery_checkpoint() {
  local project_root="${1:-}"
  local phase="${2:-}"
  local description="${3:-Manual checkpoint}"

  ensure_state_machine_loaded

  if declare -f create_snapshot > /dev/null 2>&1; then
    create_snapshot "$project_root" "$phase" 2> /dev/null
  else
    local snapshots_dir="${project_root}/.harness/engine/snapshots"
    mkdir -p "$snapshots_dir"

    local timestamp checkpoint_id
    timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    checkpoint_id="checkpoint_${phase}_$(date +%s)"

    jq -c -n \
      --arg id "$checkpoint_id" \
      --arg phase "$phase" \
      --arg ts "$timestamp" \
      --arg desc "$description" \
      '{id: $id, phase: $phase, timestamp: $ts, description: $desc, type: "recovery_checkpoint"}' \
      > "${snapshots_dir}/${checkpoint_id}.json"

    echo "$checkpoint_id"
  fi
}

# ============================================================================
# Full Recovery Process
# ============================================================================

# Run recovery process
# Usage: run_recovery_process <project_root> [--auto]
run_recovery_process() {
  local project_root="${1:-}"
  local auto_mode="${2:-}"

  echo "Analyzing system state..."
  echo ""

  local analysis
  analysis=$(analyze_crash "$project_root")

  local stuck
  stuck=$(echo "$analysis" | jq -r '.stuck_status.stuck')

  if [[ "$stuck" != "true" ]]; then
    echo "System is not stuck. No recovery needed."
    echo ""
    echo "Current phase: $(echo "$analysis" | jq -r '.current_state.phase')"

    local report_file
    report_file=$(generate_forensics_report "$project_root")
    echo ""
    echo "Health report saved to: $report_file"
    return 0
  fi

  local stuck_reason
  stuck_reason=$(echo "$analysis" | jq -r '.stuck_status.reason')
  echo "Stuck detected: $stuck_reason"
  echo ""

  local report_file
  report_file=$(generate_forensics_report "$project_root")
  echo "Forensics report generated: $report_file"
  echo ""

  if [[ "$auto_mode" == "--auto" ]]; then
    local first_option
    first_option=$(echo "$analysis" | jq -r '.recovery_options[0].id // "resume"')
    echo "Auto-recovery: Selecting '$first_option'"
    recover_state "$project_root" "$first_option"
  else
    list_recovery_options "$project_root"
    echo "Run: /recover --<option-id> to execute"
  fi
}
