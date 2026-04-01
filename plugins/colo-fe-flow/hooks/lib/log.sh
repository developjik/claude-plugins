#!/usr/bin/env bash

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$LIB_DIR/common.sh"

cff_log_dir() {
  local project_root="$1"
  printf '%s/.colo-fe-flow/.log\n' "$project_root"
}

cff_ticket_log_dir() {
  local project_root="$1"
  local ticket_key="$2"
  printf '%s/%s\n' "$(cff_log_dir "$project_root")" "$ticket_key"
}

cff_orchestration_log_path() {
  local project_root="$1"
  local ticket_key="$2"
  printf '%s/orchestration.log\n' "$(cff_ticket_log_dir "$project_root" "$ticket_key")"
}

cff_runtime_log_path() {
  local project_root="$1"
  local log_name="$2"
  printf '%s/%s.log\n' "$(cff_log_dir "$project_root")" "$log_name"
}

cff_log_append() {
  local project_root="$1"
  local ticket_key="$2"
  local message="$3"
  local log_path

  log_path="$(cff_orchestration_log_path "$project_root" "$ticket_key")"
  mkdir -p "$(dirname "$log_path")"
  printf '%s %s\n' "$(cff_now_iso8601)" "$message" >> "$log_path"
}

cff_log_append_runtime() {
  local project_root="$1"
  local log_name="$2"
  local message="$3"
  local log_path

  log_path="$(cff_runtime_log_path "$project_root" "$log_name")"
  mkdir -p "$(dirname "$log_path")"
  printf '%s %s\n' "$(cff_now_iso8601)" "$message" >> "$log_path"
}

cff_log_write_check_snapshot() {
  local project_root="$1"
  local ticket_key="$2"
  local snapshot_name="$3"
  local payload="$4"
  local snapshot_path

  snapshot_path="$(cff_ticket_log_dir "$project_root" "$ticket_key")/$snapshot_name"
  mkdir -p "$(dirname "$snapshot_path")"
  cff_json_write_pretty "$snapshot_path" "$payload"
}
