#!/usr/bin/env bash
# subagent-spawner.sh — 서브에이전트 스포닝 시스템
# P0-2: superpowers/GSD-2 벤치마킹
#
# DEPENDENCIES: json-utils.sh, logging.sh

set -euo pipefail

# ============================================================================
# 상수
# ============================================================================

readonly SUBAGENT_DIR=".harness/subagents"
readonly MAX_PARALLEL_SUBAGENTS=4
readonly SUBAGENT_TIMEOUT=600
readonly SUBAGENT_STATE_FILE="state.json"
readonly SUBAGENT_TASK_FILE="task.md"
readonly SUBAGENT_CONTEXT_FILE="context.md"
readonly SUBAGENT_EXECUTION_REQUEST_FILE="execution-request.json"
readonly SUBAGENT_ADAPTER_RESULT_FILE="adapter-result.json"
readonly SUBAGENT_COLLECTED_RESULT_FILE="collected-result.json"
readonly SUBAGENT_RESULT_FILE="result.md"
readonly SUBAGENT_FAILURE_FILE="failure.json"

# ============================================================================
# 공통 유틸리티
# ============================================================================
subagent_now_utc() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

get_subagent_dir_path() {
  local subagent_id="${1:-}"
  local project_root="${2:-}"
  echo "${project_root}/${SUBAGENT_DIR}/${subagent_id}"
}

get_subagent_artifact_paths() {
  local subagent_id="${1:-}"
  local project_root="${2:-}"
  local subagent_dir
  subagent_dir=$(get_subagent_dir_path "$subagent_id" "$project_root")

  jq -n \
    --arg directory "$subagent_dir" \
    --arg state_file "${subagent_dir}/${SUBAGENT_STATE_FILE}" \
    --arg task_file "${subagent_dir}/${SUBAGENT_TASK_FILE}" \
    --arg context_file "${subagent_dir}/${SUBAGENT_CONTEXT_FILE}" \
    --arg execution_request_file "${subagent_dir}/${SUBAGENT_EXECUTION_REQUEST_FILE}" \
    --arg adapter_result_file "${subagent_dir}/${SUBAGENT_ADAPTER_RESULT_FILE}" \
    --arg collected_result_file "${subagent_dir}/${SUBAGENT_COLLECTED_RESULT_FILE}" \
    --arg result_file "${subagent_dir}/${SUBAGENT_RESULT_FILE}" \
    --arg failure_file "${subagent_dir}/${SUBAGENT_FAILURE_FILE}" \
    '{
      directory: $directory,
      state_file: $state_file,
      task_file: $task_file,
      context_file: $context_file,
      execution_request_file: $execution_request_file,
      adapter_result_file: $adapter_result_file,
      collected_result_file: $collected_result_file,
      result_file: $result_file,
      failure_file: $failure_file
    }'
}

is_terminal_subagent_status() {
  local status="${1:-}"
  [[ "$status" == "completed" || "$status" == "failed" || "$status" == "timeout" ]]
}

normalize_terminal_subagent_status() {
  local status="${1:-completed}"
  case "$status" in
    completed | failed | timeout) echo "$status" ;;
    *) echo "failed" ;;
  esac
}

iso_timestamp_to_epoch() {
  local timestamp="${1:-}"

  if [[ -z "$timestamp" || "$timestamp" == "null" ]]; then
    echo 0
    return 0
  fi

  if date -u -d "$timestamp" +%s > /dev/null 2>&1; then
    date -u -d "$timestamp" +%s
    return 0
  fi

  if date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$timestamp" +%s > /dev/null 2>&1; then
    date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$timestamp" +%s
    return 0
  fi

  echo 0
}

normalize_failure_reason_json() {
  local failure_input="${1:-}"

  if [[ -z "$failure_input" || "$failure_input" == "null" ]]; then
    echo "null"
    return 0
  fi

  if echo "$failure_input" | jq -e '.' > /dev/null 2>&1; then
    echo "$failure_input" | jq -c '
      if . == null then
        null
      elif type == "string" then
        {code: "execution_failed", message: ., details: null}
      elif type == "object" then
        {
          code: (.code // .type // .kind // "execution_failed"),
          message: (.message // .error // .reason // "Execution failed"),
          details: (.details // .context // .metadata // null)
        }
      else
        {code: "execution_failed", message: (tostring), details: null}
      end
    '
    return 0
  fi

  jq -n --arg message "$failure_input" \
    '{code: "execution_failed", message: $message, details: null}'
}

resolve_subagent_result_payload() {
  local payload_input="${1:-}"

  if [[ -n "$payload_input" && -f "$payload_input" ]]; then
    cat "$payload_input"
    return 0
  fi

  if [[ -n "$payload_input" ]] && echo "$payload_input" | jq -e '.' > /dev/null 2>&1; then
    echo "$payload_input"
    return 0
  fi

  jq -n --arg content "$payload_input" \
    '{status: "completed", result_content: $content}'
}

# ============================================================================
# 내부 모듈 로드
# ============================================================================
if ! declare -f subagent_request_spawn > /dev/null 2>&1; then
  # shellcheck source=hooks/lib/subagent-request.sh
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/subagent-request.sh"
fi

if ! declare -f subagent_collect_execution_result > /dev/null 2>&1; then
  # shellcheck source=hooks/lib/subagent-collect.sh
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/subagent-collect.sh"
fi

if ! declare -f subagent_finalize_complete > /dev/null 2>&1; then
  # shellcheck source=hooks/lib/subagent-finalize.sh
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/subagent-finalize.sh"
fi

# ============================================================================
# 모델 이름 변환
# ============================================================================
get_model_full_name() {
  local model_short="${1:-sonnet}"
  case "$model_short" in
    opus) echo "claude-opus-4-6" ;;
    sonnet) echo "claude-sonnet-4-6" ;;
    haiku) echo "claude-haiku-4-5" ;;
    *) echo "$model_short" ;;
  esac
}

# ============================================================================
# 서브에이전트 스폰
# ============================================================================
spawn_subagent() {
  subagent_request_spawn "$@"
}

# ============================================================================
# 서브에이전트 컨텍스트 준비
# ============================================================================
prepare_subagent_context() {
  subagent_request_prepare_context "$@"
}

# ============================================================================
# 실행 계약 정의
# ============================================================================
build_subagent_execution_contract() {
  subagent_request_build_execution_contract "$@"
}

# ============================================================================
# 실행 준비
# ============================================================================
prepare_subagent_execution() {
  subagent_request_prepare_execution "$@"
}

# ============================================================================
# 서브에이전트 실행 시작
# ============================================================================
start_subagent_execution() {
  subagent_request_start_execution "$@"
}

# ============================================================================
# 실행 결과 수집
# ============================================================================
collect_subagent_execution_result() {
  subagent_collect_execution_result "$@"
}

# ============================================================================
# 서브에이전트 완료 처리
# ============================================================================
complete_subagent() {
  subagent_finalize_complete "$@"
}

# ============================================================================
# 서브에이전트 상태 조회
# ============================================================================
get_subagent_status() {
  subagent_collect_get_status "$@"
}

# ============================================================================
# 활성 서브에이전트 목록
# ============================================================================
list_active_subagents() {
  subagent_collect_list_active "$@"
}

# ============================================================================
# 서브에이전트 결과 집계
# ============================================================================
aggregate_subagent_results() {
  subagent_collect_aggregate_results "$@"
}

# ============================================================================
# 서브에이전트 완료 대기
# Usage: wait_for_subagents <project_root> <subagent_ids_comma> [timeout_seconds]
# Returns: JSON with overall status and per-subagent summary
# ============================================================================
wait_for_subagents() {
  subagent_collect_wait_for_subagents "$@"
}

# ============================================================================
# 서브에이전트 정리
# ============================================================================
cleanup_completed_subagents() {
  subagent_finalize_cleanup_completed "$@"
}

# ============================================================================
# Agent 툴 파라미터 생성
# ============================================================================
generate_agent_params() {
  subagent_request_generate_agent_params "$@"
}

# ============================================================================
# 실행 준비
# ============================================================================
prepare_for_agent_execution() {
  subagent_request_prepare_execution "$@"
}

# ============================================================================
# 실행 완료 처리
# ============================================================================
finalize_subagent_execution() {
  subagent_finalize_finalize_execution "$@"
}

finalize_agent_execution() {
  subagent_finalize_finalize_agent_execution "$@"
}
