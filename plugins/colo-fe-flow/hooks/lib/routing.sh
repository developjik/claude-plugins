#!/usr/bin/env bash

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./approval.sh
source "$LIB_DIR/approval.sh"
# shellcheck source=./dependency-check.sh
source "$LIB_DIR/dependency-check.sh"
# shellcheck source=./verification.sh
source "$LIB_DIR/verification.sh"

CFF_ROUTING_ACTIONS=(
  start_ticket
  run_intake
  run_clarify
  run_plan
  run_design
  run_implement
  run_check
  run_iterate
  run_sync_docs
  show_ticket_status
  list_tickets
  switch_ticket
  complete_ticket
)

CFF_ROUTING_REASON_CODES=(
  missing_required_mcp
  unknown_action
  no_ticket_context
  ticket_switch_required
  user_input_required
  invalid_state_schema
  state_artifact_mismatch
  missing_ticket_state
  missing_intake
  missing_clarify
  clarify_not_approved
  missing_plan
  plan_not_approved
  missing_design
  design_not_approved
  missing_tasks
  implementation_incomplete
  missing_check
  check_failed
  open_gaps_remaining
  docs_not_synced
  already_done
  ready_to_run_intake
  ready_to_run_clarify
  ready_to_run_plan
  ready_to_run_design
  ready_to_run_implement
  ready_to_run_check
  ready_to_run_iterate
  ready_to_run_sync_docs
  ready_to_complete
)

cff_routing_action_valid() {
  local candidate="$1"
  local action

  for action in "${CFF_ROUTING_ACTIONS[@]}"; do
    if [[ "$action" == "$candidate" ]]; then
      return 0
    fi
  done

  return 1
}

cff_routing_reason_code_valid() {
  local candidate="$1"
  local code

  for code in "${CFF_ROUTING_REASON_CODES[@]}"; do
    if [[ "$code" == "$candidate" ]]; then
      return 0
    fi
  done

  return 1
}

cff_routing_extract_requested_ticket() {
  local raw_request="${1:-}"

  printf '%s\n' "$raw_request" | grep -Eo '[A-Z][A-Z0-9]+-[0-9]+' | head -n 1 || true
}

cff_routing_normalize_action() {
  local raw_request="${1:-}"
  local lowered

  lowered="$(printf '%s' "$raw_request" | tr '[:upper:]' '[:lower:]')"

  case "$lowered" in
    *"list"*|*"목록"*)
      printf 'list_tickets\n'
      return 0
      ;;
    *"status"*|*"상태"*|*"진행 상황"*)
      printf 'show_ticket_status\n'
      return 0
      ;;
    *"switch"*|*"전환"*|*"바꿔"*|*"변경"*)
      printf 'switch_ticket\n'
      return 0
      ;;
    *"intake"*)
      printf 'run_intake\n'
      return 0
      ;;
    *"clarify"*|*"명확"*)
      printf 'run_clarify\n'
      return 0
      ;;
    *"plan"*|*"계획"*)
      printf 'run_plan\n'
      return 0
      ;;
    *"design"*|*"설계"*)
      printf 'run_design\n'
      return 0
      ;;
    *"implement"*|*"구현"*|*"개발"*)
      printf 'run_implement\n'
      return 0
      ;;
    *"check"*|*"검증"*|*"테스트"*)
      printf 'run_check\n'
      return 0
      ;;
    *"iterate"*|*"반복"*|*"보정"*|*"수정"*)
      printf 'run_iterate\n'
      return 0
      ;;
    *"sync-docs"*|*"동기화"*|*"문서 반영"*)
      printf 'run_sync_docs\n'
      return 0
      ;;
    *"complete"*|*"완료"*|*"끝내"*)
      printf 'complete_ticket\n'
      return 0
      ;;
  esac

  if [[ "$lowered" == *"start"* ]] || [[ "$raw_request" == *"시작"* ]]; then
    printf 'start_ticket\n'
    return 0
  fi

  printf '\n'
}

cff_routing_action_to_skill() {
  local resolved_action="$1"

  case "$resolved_action" in
    start_ticket) printf 'start-jira-ticket\n' ;;
    run_intake) printf 'intake\n' ;;
    run_clarify) printf 'clarify\n' ;;
    run_plan) printf 'plan\n' ;;
    run_design) printf 'design\n' ;;
    run_implement) printf 'implement\n' ;;
    run_check) printf 'check\n' ;;
    run_iterate) printf 'iterate\n' ;;
    run_sync_docs) printf 'sync-docs\n' ;;
    show_ticket_status) printf 'show-ticket-status\n' ;;
    list_tickets) printf 'list-tickets\n' ;;
    switch_ticket) printf 'switch-ticket\n' ;;
    complete_ticket) printf 'complete-ticket\n' ;;
    *) printf '\n' ;;
  esac
}

cff_routing_reason_message() {
  local reason_code="$1"

  case "$reason_code" in
    missing_required_mcp) printf '필수 MCP 선언이 없어 route-workflow를 진행할 수 없음\n' ;;
    unknown_action) printf '요청 의도를 내부 action으로 정규화하지 못함\n' ;;
    no_ticket_context) printf '현재 작업할 ticket context가 없어 다음 단계를 결정할 수 없음\n' ;;
    ticket_switch_required) printf '다른 ticket으로 전환한 뒤 진행해야 함\n' ;;
    user_input_required) printf '사용자 입력 또는 선택이 먼저 필요함\n' ;;
    invalid_state_schema) printf 'ticket state schema가 기대한 구조와 다름\n' ;;
    state_artifact_mismatch) printf 'state와 실제 artifact 파일 상태가 일치하지 않음\n' ;;
    missing_ticket_state) printf 'ticket state가 없어 intake가 필요함\n' ;;
    missing_intake) printf 'intake.md가 없어 intake가 필요함\n' ;;
    missing_clarify) printf 'clarify.md가 없어 clarify가 필요함\n' ;;
    clarify_not_approved) printf 'clarify가 아직 승인되지 않음\n' ;;
    missing_plan) printf 'plan.md가 없어 plan이 필요함\n' ;;
    plan_not_approved) printf 'plan이 아직 승인되지 않음\n' ;;
    missing_design) printf 'design.md가 없어 design이 필요함\n' ;;
    design_not_approved) printf 'design이 아직 승인되지 않음\n' ;;
    missing_tasks) printf 'design은 승인되었지만 tasks.json이 없어 implement로 진행할 수 없음\n' ;;
    implementation_incomplete) printf '구현이 아직 완료되지 않음\n' ;;
    missing_check) printf 'check.md 또는 최신 check 결과가 없어 check가 필요함\n' ;;
    check_failed) printf '마지막 check가 실패해 iterate가 필요함\n' ;;
    open_gaps_remaining) printf '열린 gap이 남아 있어 iterate가 필요함\n' ;;
    docs_not_synced) printf 'wrapup 또는 docs sync가 완료되지 않아 sync-docs가 필요함\n' ;;
    already_done) printf '이 ticket은 이미 done 상태임\n' ;;
    ready_to_run_intake) printf 'intake를 시작할 준비가 됨\n' ;;
    ready_to_run_clarify) printf 'clarify를 시작할 준비가 됨\n' ;;
    ready_to_run_plan) printf 'plan을 시작할 준비가 됨\n' ;;
    ready_to_run_design) printf 'design을 시작할 준비가 됨\n' ;;
    ready_to_run_implement) printf 'design 승인 완료, tasks.json 준비됨\n' ;;
    ready_to_run_check) printf 'check를 시작할 준비가 됨\n' ;;
    ready_to_run_iterate) printf 'iterate를 시작할 준비가 됨\n' ;;
    ready_to_run_sync_docs) printf 'sync-docs를 시작할 준비가 됨\n' ;;
    ready_to_complete) printf '완료 조건이 충족되어 complete-ticket으로 진행 가능함\n' ;;
    *) printf 'route-workflow 판정 결과를 생성함\n' ;;
  esac
}

cff_routing_ticket_phase() {
  local project_root="$1"
  local ticket_key="$2"
  local ticket_path

  ticket_path="$(cff_ticket_state_path "$project_root" "$ticket_key")"
  if [[ ! -f "$ticket_path" ]]; then
    printf '\n'
    return 0
  fi

  cff_json_get "$ticket_path" "phase" "null"
}

cff_routing_artifact_file_exists() {
  local project_root="$1"
  local ticket_key="$2"
  local artifact_key="$3"
  local ticket_path
  local artifact_path

  ticket_path="$(cff_ticket_state_path "$project_root" "$ticket_key")"
  artifact_path="$(cff_json_get "$ticket_path" "artifacts.${artifact_key}.path" "")"
  if [[ -z "$artifact_path" ]]; then
    return 1
  fi

  if [[ "$artifact_path" = /* ]]; then
    [[ -f "$artifact_path" ]]
  else
    [[ -f "$project_root/$artifact_path" ]]
  fi
}

cff_routing_critical_revalidate() {
  local project_root="$1"
  local ticket_key="$2"
  local next_skill="$3"
  local ticket_path

  ticket_path="$(cff_ticket_state_path "$project_root" "$ticket_key")"
  [[ -f "$ticket_path" ]] || return 0

  case "$next_skill" in
    implement)
      cff_routing_artifact_file_exists "$project_root" "$ticket_key" "design" || return 1
      cff_routing_artifact_file_exists "$project_root" "$ticket_key" "tasks" || return 1
      ;;
    sync-docs)
      cff_routing_artifact_file_exists "$project_root" "$ticket_key" "check" || return 1
      ;;
    complete-ticket)
      cff_routing_artifact_file_exists "$project_root" "$ticket_key" "wrapup" || return 1
      [[ "$(cff_json_get "$ticket_path" "doc_sync.completed" "false")" == "true" ]] || return 1
      ;;
  esac

  return 0
}

cff_routing_required_next_skill() {
  local project_root="$1"
  local ticket_key="$2"
  local ticket_path

  ticket_path="$(cff_ticket_state_path "$project_root" "$ticket_key")"
  if [[ ! -f "$ticket_path" ]]; then
    printf 'intake|missing_ticket_state\n'
    return 0
  fi

  local status phase
  status="$(cff_json_get "$ticket_path" "status" "active")"
  phase="$(cff_json_get "$ticket_path" "phase" "intake")"

  if [[ "$status" == "done" || "$phase" == "done" ]]; then
    printf 'show-ticket-status|already_done\n'
    return 0
  fi

  if [[ "$(cff_json_get "$ticket_path" "artifacts.intake.exists" "false")" != "true" ]]; then
    printf 'intake|missing_intake\n'
    return 0
  fi

  if [[ "$(cff_json_get "$ticket_path" "artifacts.clarify.exists" "false")" != "true" ]]; then
    printf 'clarify|missing_clarify\n'
    return 0
  fi

  if ! cff_approval_is_approved "$project_root" "$ticket_key" "clarify"; then
    printf 'clarify|clarify_not_approved\n'
    return 0
  fi

  if [[ "$(cff_json_get "$ticket_path" "artifacts.plan.exists" "false")" != "true" ]]; then
    printf 'plan|missing_plan\n'
    return 0
  fi

  if ! cff_approval_is_approved "$project_root" "$ticket_key" "plan"; then
    printf 'plan|plan_not_approved\n'
    return 0
  fi

  if [[ "$(cff_json_get "$ticket_path" "artifacts.design.exists" "false")" != "true" ]]; then
    printf 'design|missing_design\n'
    return 0
  fi

  if ! cff_approval_is_approved "$project_root" "$ticket_key" "design"; then
    printf 'design|design_not_approved\n'
    return 0
  fi

  if [[ "$(cff_json_get "$ticket_path" "artifacts.tasks.exists" "false")" != "true" ]]; then
    printf 'design|missing_tasks\n'
    return 0
  fi

  if [[ "$(cff_json_get "$ticket_path" "implementation.finished" "false")" != "true" ]]; then
    printf 'implement|ready_to_run_implement\n'
    return 0
  fi

  if [[ "$(cff_json_get "$ticket_path" "artifacts.check.exists" "false")" != "true" || "$(cff_verification_last_status "$project_root" "$ticket_key")" == "not_run" ]]; then
    printf 'check|missing_check\n'
    return 0
  fi

  if [[ "$(cff_verification_last_status "$project_root" "$ticket_key")" == "failed" ]]; then
    printf 'iterate|check_failed\n'
    return 0
  fi

  if [[ "$(cff_verification_open_gaps "$project_root" "$ticket_key")" != "0" ]]; then
    printf 'iterate|open_gaps_remaining\n'
    return 0
  fi

  if [[ "$(cff_json_get "$ticket_path" "artifacts.wrapup.exists" "false")" != "true" || "$(cff_json_get "$ticket_path" "doc_sync.completed" "false")" != "true" ]]; then
    printf 'sync-docs|docs_not_synced\n'
    return 0
  fi

  printf 'complete-ticket|ready_to_complete\n'
}

cff_routing_emit_result_json() {
  local raw_request="$1"
  local resolved_action="$2"
  local requested_ticket="$3"
  local resolved_ticket="$4"
  local current_phase="$5"
  local decision="$6"
  local next_skill="$7"
  local reason_code="$8"
  local reason="$9"
  local requires_user_input="${10}"

  python3 - "$raw_request" "$resolved_action" "$requested_ticket" "$resolved_ticket" "$current_phase" "$decision" "$next_skill" "$reason_code" "$reason" "$requires_user_input" <<'PY'
import json
import sys

(
    raw_request,
    resolved_action,
    requested_ticket,
    resolved_ticket,
    current_phase,
    decision,
    next_skill,
    reason_code,
    reason,
    requires_user_input,
) = sys.argv[1:11]

def to_optional(value: str):
    return None if value == "__CFF_NULL__" else value

payload = {
    "raw_request": raw_request,
    "resolved_action": to_optional(resolved_action),
    "requested_ticket": to_optional(requested_ticket),
    "resolved_ticket": to_optional(resolved_ticket),
    "current_phase": to_optional(current_phase),
    "decision": decision,
    "next_skill": to_optional(next_skill),
    "reason_code": reason_code,
    "reason": reason,
    "requires_user_input": requires_user_input.lower() == "true",
}

json.dump(payload, sys.stdout, ensure_ascii=True, indent=2)
sys.stdout.write("\n")
PY
}

cff_routing_route_result_json() {
  local project_root="$1"
  local raw_request="${2:-}"
  local resolved_action
  local requested_ticket
  local active_ticket
  local resolved_ticket
  local current_phase="__CFF_NULL__"
  local decision
  local next_skill="__CFF_NULL__"
  local reason_code
  local reason
  local requires_user_input="false"
  local required_result
  local required_next_skill
  local required_reason
  local requested_skill

  resolved_action="$(cff_routing_normalize_action "$raw_request")"
  requested_ticket="$(cff_routing_extract_requested_ticket "$raw_request")"
  active_ticket="$(cff_state_get_active_ticket "$project_root")"
  resolved_ticket="${requested_ticket:-$active_ticket}"

  if ! require_declared_mcp_servers "$project_root" >/dev/null 2>&1; then
    decision="block"
    reason_code="missing_required_mcp"
    requires_user_input="false"
    reason="$(cff_routing_reason_message "$reason_code")"
    cff_routing_emit_result_json \
      "$raw_request" \
      "${resolved_action:-__CFF_NULL__}" \
      "${requested_ticket:-__CFF_NULL__}" \
      "${resolved_ticket:-__CFF_NULL__}" \
      "$current_phase" \
      "$decision" \
      "$next_skill" \
      "$reason_code" \
      "$reason" \
      "$requires_user_input"
    return 0
  fi

  if [[ -n "$resolved_ticket" ]]; then
    local maybe_phase
    maybe_phase="$(cff_routing_ticket_phase "$project_root" "$resolved_ticket")"
    if [[ -n "$maybe_phase" ]]; then
      current_phase="$maybe_phase"
    fi
  fi

  case "$resolved_action" in
    list_tickets)
      decision="execute"
      next_skill="list-tickets"
      reason_code="user_input_required"
      reason="$(cff_routing_reason_message "$reason_code")"
      cff_routing_emit_result_json \
        "$raw_request" \
        "${resolved_action:-__CFF_NULL__}" \
        "${requested_ticket:-__CFF_NULL__}" \
        "${resolved_ticket:-__CFF_NULL__}" \
        "$current_phase" \
        "$decision" \
        "$next_skill" \
        "$reason_code" \
        "$reason" \
        "$requires_user_input"
      return 0
      ;;
    start_ticket)
      decision="execute"
      next_skill="start-jira-ticket"
      reason_code="user_input_required"
      reason="$(cff_routing_reason_message "$reason_code")"
      cff_routing_emit_result_json \
        "$raw_request" \
        "${resolved_action:-__CFF_NULL__}" \
        "${requested_ticket:-__CFF_NULL__}" \
        "${resolved_ticket:-__CFF_NULL__}" \
        "$current_phase" \
        "$decision" \
        "$next_skill" \
        "$reason_code" \
        "$reason" \
        "$requires_user_input"
      return 0
      ;;
    switch_ticket)
      if [[ -z "$resolved_ticket" ]]; then
        decision="block"
        next_skill="__CFF_NULL__"
        reason_code="no_ticket_context"
        requires_user_input="true"
      else
        decision="execute"
        next_skill="switch-ticket"
        reason_code="ticket_switch_required"
      fi
      reason="$(cff_routing_reason_message "$reason_code")"
      cff_routing_emit_result_json \
        "$raw_request" \
        "${resolved_action:-__CFF_NULL__}" \
        "${requested_ticket:-__CFF_NULL__}" \
        "${resolved_ticket:-__CFF_NULL__}" \
        "$current_phase" \
        "$decision" \
        "$next_skill" \
        "$reason_code" \
        "$reason" \
        "$requires_user_input"
      return 0
      ;;
  esac

  if [[ -z "$resolved_ticket" ]]; then
    decision="block"
    next_skill="__CFF_NULL__"
    reason_code="no_ticket_context"
    requires_user_input="true"
    reason="$(cff_routing_reason_message "$reason_code")"
    cff_routing_emit_result_json \
      "$raw_request" \
      "${resolved_action:-__CFF_NULL__}" \
      "__CFF_NULL__" \
      "__CFF_NULL__" \
      "$current_phase" \
      "$decision" \
      "$next_skill" \
      "$reason_code" \
      "$reason" \
      "$requires_user_input"
    return 0
  fi

  required_result="$(cff_routing_required_next_skill "$project_root" "$resolved_ticket")"
  required_next_skill="${required_result%%|*}"
  required_reason="${required_result#*|}"

  if [[ "$resolved_action" == "show_ticket_status" ]]; then
    decision="execute"
    next_skill="show-ticket-status"
    reason_code="$required_reason"
  elif [[ -z "$resolved_action" ]]; then
    decision="execute"
    next_skill="$required_next_skill"
    reason_code="$required_reason"
  else
    requested_skill="$(cff_routing_action_to_skill "$resolved_action")"
    if [[ -z "$requested_skill" ]]; then
      decision="block"
      next_skill="__CFF_NULL__"
      reason_code="unknown_action"
      requires_user_input="false"
    elif [[ "$requested_skill" == "$required_next_skill" ]]; then
      decision="execute"
      next_skill="$requested_skill"
      reason_code="$required_reason"
    else
      decision="redirect"
      next_skill="$required_next_skill"
      reason_code="$required_reason"
    fi
  fi

  if [[ "$decision" != "block" && "$next_skill" != "__CFF_NULL__" ]]; then
    if ! cff_routing_critical_revalidate "$project_root" "$resolved_ticket" "$next_skill"; then
      decision="block"
      next_skill="__CFF_NULL__"
      reason_code="state_artifact_mismatch"
      requires_user_input="false"
    fi
  fi

  reason="$(cff_routing_reason_message "$reason_code")"
  cff_routing_emit_result_json \
    "$raw_request" \
    "${resolved_action:-__CFF_NULL__}" \
    "${requested_ticket:-__CFF_NULL__}" \
    "${resolved_ticket:-__CFF_NULL__}" \
    "$current_phase" \
    "$decision" \
    "$next_skill" \
    "$reason_code" \
    "$reason" \
    "$requires_user_input"
}
