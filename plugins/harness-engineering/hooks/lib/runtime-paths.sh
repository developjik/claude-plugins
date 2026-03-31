#!/usr/bin/env bash
# runtime-paths.sh — .harness 런타임 경로 헬퍼

harness_runtime_dir_from_root() {
  local project_root="${1:-}"
  printf '%s/.harness\n' "$project_root"
}

harness_logs_dir_from_root() {
  local project_root="${1:-}"
  printf '%s/logs\n' "$(harness_runtime_dir_from_root "$project_root")"
}

harness_state_dir_from_root() {
  local project_root="${1:-}"
  printf '%s/state\n' "$(harness_runtime_dir_from_root "$project_root")"
}

harness_engine_dir_from_root() {
  local project_root="${1:-}"
  printf '%s/engine\n' "$(harness_runtime_dir_from_root "$project_root")"
}

harness_current_feature_file() {
  local project_root="${1:-}"
  printf '%s/current-feature.txt\n' "$(harness_state_dir_from_root "$project_root")"
}

harness_current_agent_file() {
  local project_root="${1:-}"
  printf '%s/current-agent.txt\n' "$(harness_state_dir_from_root "$project_root")"
}

harness_phase_file() {
  local project_root="${1:-}"
  printf '%s/pdca-phase.txt\n' "$(harness_state_dir_from_root "$project_root")"
}

harness_phase_start_file() {
  local project_root="${1:-}"
  printf '%s/phase-start-time.txt\n' "$(harness_state_dir_from_root "$project_root")"
}

harness_current_level_file() {
  local project_root="${1:-}"
  printf '%s/current-level.txt\n' "$(harness_state_dir_from_root "$project_root")"
}

harness_approval_status_file() {
  local project_root="${1:-}"
  printf '%s/approval-status.txt\n' "$(harness_state_dir_from_root "$project_root")"
}

harness_approval_transition_file() {
  local project_root="${1:-}"
  printf '%s/approval-transition.txt\n' "$(harness_state_dir_from_root "$project_root")"
}

harness_approval_reason_file() {
  local project_root="${1:-}"
  printf '%s/approval-reason.txt\n' "$(harness_state_dir_from_root "$project_root")"
}

harness_approval_requested_at_file() {
  local project_root="${1:-}"
  printf '%s/approval-requested-at.txt\n' "$(harness_state_dir_from_root "$project_root")"
}

ensure_harness_runtime_subdirs() {
  local project_root="${1:-}"
  mkdir -p \
    "$(harness_runtime_dir_from_root "$project_root")" \
    "$(harness_logs_dir_from_root "$project_root")" \
    "$(harness_state_dir_from_root "$project_root")" \
    "$(harness_engine_dir_from_root "$project_root")"
}
