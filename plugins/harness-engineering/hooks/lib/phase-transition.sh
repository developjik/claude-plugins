#!/usr/bin/env bash
# phase-transition.sh — 에이전트/phase 전환 헬퍼

PHASE_TRANSITION_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=runtime-paths.sh
source "${PHASE_TRANSITION_LIB_DIR}/runtime-paths.sh"
# shellcheck source=feature-context.sh
source "${PHASE_TRANSITION_LIB_DIR}/feature-context.sh"
# shellcheck source=automation-level.sh
source "${PHASE_TRANSITION_LIB_DIR}/automation-level.sh"

if [[ -f "${PHASE_TRANSITION_LIB_DIR}/state-machine-interface.sh" ]]; then
  # shellcheck source=state-machine-interface.sh
  source "${PHASE_TRANSITION_LIB_DIR}/state-machine-interface.sh"
fi

phase_for_agent() {
  local agent_name="${1:-}"

  case "$agent_name" in
    strategist|harness-engineering:strategist) echo "plan" ;;
    architect|harness-engineering:architect) echo "design" ;;
    engineer|harness-engineering:engineer) echo "implement" ;;
    guardian|harness-engineering:guardian) echo "check" ;;
    librarian|harness-engineering:librarian) echo "wrapup" ;;
    debugger|harness-engineering:debugger) echo "debug" ;;
    grill-me|harness-engineering:grill-me) echo "grill-me" ;;
    *) echo "unknown" ;;
  esac
}

is_managed_pdca_phase() {
  local phase="${1:-}"
  case "$phase" in
    clarify|plan|design|implement|check|wrapup|complete) return 0 ;;
    *) return 1 ;;
  esac
}

approval_transition_name() {
  local from_phase="${1:-}"
  local to_phase="${2:-}"

  case "${from_phase}_${to_phase}" in
    clarify_plan) echo "clarify_to_plan" ;;
    plan_design) echo "plan_to_design" ;;
    design_implement|design_do) echo "design_to_do" ;;
    implement_check|do_check) echo "do_to_check" ;;
    check_wrapup) echo "check_to_wrapup" ;;
    *) echo "" ;;
  esac
}

get_runtime_phase() {
  local project_root="${1:-}"
  local phase=""

  if declare -f safe_get_current_phase >/dev/null 2>&1; then
    phase=$(safe_get_current_phase "$project_root" 2>/dev/null || true)
  elif declare -f get_current_phase >/dev/null 2>&1; then
    phase=$(get_current_phase "$project_root" 2>/dev/null || true)
  fi

  if [[ -n "$phase" ]] && [[ "$phase" != "unknown" ]] && [[ "$phase" != "null" ]]; then
    printf '%s\n' "$phase"
    return 0
  fi

  cat "$(harness_phase_file "$project_root")" 2>/dev/null || printf 'idle\n'
}

record_phase_transition() {
  local project_root="${1:-}"
  local phase="${2:-}"
  local actor="${3:-claude}"
  local reason="${4:-agent_start}"

  if ! is_managed_pdca_phase "$phase"; then
    return 0
  fi

  if declare -f safe_record_runtime_phase_state >/dev/null 2>&1; then
    safe_record_runtime_phase_state "$project_root" "$phase" "$actor" "$reason"
  elif declare -f record_runtime_phase_state >/dev/null 2>&1; then
    record_runtime_phase_state "$project_root" "$phase" "$actor" "$reason"
  fi
}

handle_phase_transition_approval() {
  local project_root="${1:-}"
  local previous_phase="${2:-idle}"
  local next_phase="${3:-}"
  local current_level="${4:-$(get_automation_level "$project_root")}"

  if ! is_managed_pdca_phase "$next_phase"; then
    printf 'skip\n'
    return 0
  fi

  if [[ "$previous_phase" == "idle" ]] || [[ "$previous_phase" == "$next_phase" ]] || ! is_managed_pdca_phase "$previous_phase"; then
    clear_pending_approval "$project_root"
    printf 'skip\n'
    return 0
  fi

  local transition approval_needed
  transition=$(approval_transition_name "$previous_phase" "$next_phase")

  if [[ -z "$transition" ]]; then
    clear_pending_approval "$project_root"
    printf 'skip\n'
    return 0
  fi

  approval_needed=$(should_approve_transition "$current_level" "$transition")

  log_decision "$project_root" "phase_transition" \
    "\"from\":\"$previous_phase\",\"to\":\"$next_phase\",\"level\":\"$current_level\",\"approval_needed\":\"$approval_needed\""

  case "$approval_needed" in
    true)
      set_pending_approval "$project_root" "$transition" "Level $current_level requires approval for $transition"
      ;;
    false|if_uncertain)
      clear_pending_approval "$project_root"
      ;;
  esac

  printf '%s\n' "$approval_needed"
}
