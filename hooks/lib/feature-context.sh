#!/usr/bin/env bash
# feature-context.sh — feature slug 컨텍스트 헬퍼

FEATURE_CONTEXT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=runtime-paths.sh
source "${FEATURE_CONTEXT_LIB_DIR}/runtime-paths.sh"

if [[ -f "${FEATURE_CONTEXT_LIB_DIR}/state-machine-interface.sh" ]]; then
  # shellcheck source=state-machine-interface.sh
  source "${FEATURE_CONTEXT_LIB_DIR}/state-machine-interface.sh"
fi

_feature_context_state_file() {
  local project_root="${1:-}"
  if declare -f get_state_file_path >/dev/null 2>&1; then
    get_state_file_path "$project_root"
  else
    printf '%s/state.json\n' "$(harness_engine_dir_from_root "$project_root")"
  fi
}

_feature_context_update_state_slug() {
  local project_root="${1:-}"
  local feature_slug="${2:-}"
  local state_path
  state_path=$(_feature_context_state_file "$project_root")

  if [[ ! -f "$state_path" ]] || ! command -v jq >/dev/null 2>&1; then
    return 0
  fi

  local timestamp tmp
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  tmp="${state_path}.tmp"

  jq --arg feature "$feature_slug" \
     --arg ts "$timestamp" \
     '.feature_slug = $feature |
      .metadata.updated_at = $ts' \
     "$state_path" > "$tmp" && mv "$tmp" "$state_path"
}

get_current_feature() {
  local project_root="${1:-}"
  local feature_slug=""

  if declare -f safe_get_feature_slug >/dev/null 2>&1; then
    feature_slug=$(safe_get_feature_slug "$project_root" 2>/dev/null || true)
  elif declare -f get_feature_slug >/dev/null 2>&1; then
    feature_slug=$(get_feature_slug "$project_root" 2>/dev/null || true)
  fi

  if [[ -n "$feature_slug" ]]; then
    printf '%s\n' "$feature_slug"
    return 0
  fi

  cat "$(harness_current_feature_file "$project_root")" 2>/dev/null || true
}

set_current_feature() {
  local project_root="${1:-}"
  local feature_slug="${2:-}"

  ensure_harness_runtime_subdirs "$project_root"

  if declare -f safe_init_or_repair_state_machine >/dev/null 2>&1; then
    safe_init_or_repair_state_machine "$project_root" "$feature_slug" >/dev/null 2>&1 || true
  elif declare -f init_or_repair_state_machine >/dev/null 2>&1; then
    init_or_repair_state_machine "$project_root" "$feature_slug" >/dev/null 2>&1 || true
  fi

  if declare -f safe_set_feature_slug >/dev/null 2>&1; then
    safe_set_feature_slug "$project_root" "$feature_slug" >/dev/null 2>&1 || true
  elif declare -f set_feature_slug >/dev/null 2>&1; then
    set_feature_slug "$project_root" "$feature_slug" >/dev/null 2>&1 || true
  else
    _feature_context_update_state_slug "$project_root" "$feature_slug"
  fi

  printf '%s\n' "$feature_slug" > "$(harness_current_feature_file "$project_root")"

  if declare -f safe_sync_runtime_cache >/dev/null 2>&1; then
    safe_sync_runtime_cache "$project_root" >/dev/null 2>&1 || true
  elif declare -f sync_runtime_cache >/dev/null 2>&1; then
    sync_runtime_cache "$project_root" >/dev/null 2>&1 || true
  fi

  printf '%s\n' "$feature_slug"
}

clear_current_feature() {
  local project_root="${1:-}"

  ensure_harness_runtime_subdirs "$project_root"
  : > "$(harness_current_feature_file "$project_root")"

  if declare -f safe_set_feature_slug >/dev/null 2>&1; then
    safe_set_feature_slug "$project_root" "" >/dev/null 2>&1 || true
  elif declare -f set_feature_slug >/dev/null 2>&1; then
    set_feature_slug "$project_root" "" >/dev/null 2>&1 || true
  else
    _feature_context_update_state_slug "$project_root" ""
  fi

  if declare -f safe_sync_runtime_cache >/dev/null 2>&1; then
    safe_sync_runtime_cache "$project_root" >/dev/null 2>&1 || true
  elif declare -f sync_runtime_cache >/dev/null 2>&1; then
    sync_runtime_cache "$project_root" >/dev/null 2>&1 || true
  fi
}

sync_feature_from_state() {
  local project_root="${1:-}"
  local feature_slug=""

  if declare -f safe_get_feature_slug >/dev/null 2>&1; then
    feature_slug=$(safe_get_feature_slug "$project_root" 2>/dev/null || true)
  elif declare -f get_feature_slug >/dev/null 2>&1; then
    feature_slug=$(get_feature_slug "$project_root" 2>/dev/null || true)
  fi

  ensure_harness_runtime_subdirs "$project_root"
  printf '%s\n' "$feature_slug" > "$(harness_current_feature_file "$project_root")"
  printf '%s\n' "$feature_slug"
}

infer_feature_from_path() {
  local path="${1:-}"

  if [[ "$path" =~ (^|/)docs/specs/([^/]+)/ ]]; then
    printf '%s\n' "${BASH_REMATCH[2]}"
    return 0
  fi

  if [[ "$path" =~ (^|/)docs/specs/([^/]+)$ ]]; then
    printf '%s\n' "${BASH_REMATCH[2]}"
    return 0
  fi

  return 1
}
