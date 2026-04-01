#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib/bootstrap.sh
source "$ROOT_DIR/hooks/lib/bootstrap.sh"
# shellcheck source=../lib/planning.sh
source "$ROOT_DIR/hooks/lib/planning.sh"
# shellcheck source=../lib/execution.sh
source "$ROOT_DIR/hooks/lib/execution.sh"
# shellcheck source=../lib/routing.sh
source "$ROOT_DIR/hooks/lib/routing.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  if [[ "$expected" != "$actual" ]]; then
    fail "$message: expected '$expected', got '$actual'"
  fi
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

cff_bootstrap_ticket \
  "$tmp_dir" \
  "FE-123" \
  "10001" \
  "Checkout 페이지 개선" \
  "https://jira.example.com/browse/FE-123"
cff_planning_write_clarify "$tmp_dir" "FE-123" "Clarify checkout edge cases."
cff_planning_approve_stage "$tmp_dir" "FE-123" "clarify"
cff_planning_write_plan "$tmp_dir" "FE-123" "Plan checkout UI and validation changes."
cff_planning_approve_stage "$tmp_dir" "FE-123" "plan"
cff_planning_write_design "$tmp_dir" "FE-123" "Design checkout changes and tasks."
cff_planning_approve_stage "$tmp_dir" "FE-123" "design"

assert_eq "implement|ready_to_run_implement" "$(cff_routing_required_next_skill "$tmp_dir" "FE-123")" "approved design should route to implement"

cff_execution_start_implementation "$tmp_dir" "FE-123" "1" "0"
assert_eq "implementing" "$(cff_json_get "$(cff_ticket_state_path "$tmp_dir" "FE-123")" "phase")" "implementation start should move phase"
assert_eq "true" "$(cff_json_get "$(cff_ticket_state_path "$tmp_dir" "FE-123")" "implementation.started")" "implementation should be marked started"

cff_execution_finish_implementation "$tmp_dir" "FE-123" "1" "1"
assert_eq "check|missing_check" "$(cff_routing_required_next_skill "$tmp_dir" "FE-123")" "finished implementation should require check"

cff_execution_write_check "$tmp_dir" "FE-123" "failed" "2" "84" "테스트 실패와 gap 2건 발견"
assert_eq "iterate|check_failed" "$(cff_routing_required_next_skill "$tmp_dir" "FE-123")" "failed check should route to iterate"
assert_eq "checking" "$(cff_json_get "$(cff_ticket_state_path "$tmp_dir" "FE-123")" "phase")" "check should move phase to checking"

cff_execution_iterate "$tmp_dir" "FE-123" "Fix failed check gaps"
assert_eq "iterating" "$(cff_json_get "$(cff_ticket_state_path "$tmp_dir" "FE-123")" "phase")" "iterate should move phase to iterating"
assert_eq "1" "$(cff_json_get "$(cff_ticket_state_path "$tmp_dir" "FE-123")" "iteration.count")" "iterate should increment count"
assert_eq "false" "$(cff_json_get "$(cff_ticket_state_path "$tmp_dir" "FE-123")" "implementation.finished")" "iterate should reopen implementation"

cff_execution_finish_implementation "$tmp_dir" "FE-123" "1" "1"
cff_execution_write_check "$tmp_dir" "FE-123" "passed" "0" "97" "테스트 통과, gap 없음"
assert_eq "sync-docs|docs_not_synced" "$(cff_routing_required_next_skill "$tmp_dir" "FE-123")" "passing check should route to sync-docs"

cff_execution_sync_docs "$tmp_dir" "FE-123" '["docs/checkout.md"]' "변경 사항과 문서 반영을 마감한다."
assert_eq "syncing-docs" "$(cff_json_get "$(cff_ticket_state_path "$tmp_dir" "FE-123")" "phase")" "sync-docs should move phase"
assert_eq "true" "$(cff_json_get "$(cff_ticket_state_path "$tmp_dir" "FE-123")" "doc_sync.completed")" "sync-docs should mark doc sync complete"
assert_eq "complete-ticket|ready_to_complete" "$(cff_routing_required_next_skill "$tmp_dir" "FE-123")" "synced docs should route to completion"

cff_execution_complete_ticket "$tmp_dir" "FE-123"
assert_eq "done" "$(cff_json_get "$(cff_ticket_state_path "$tmp_dir" "FE-123")" "status")" "completion should mark status done"
assert_eq "done" "$(cff_json_get "$(cff_ticket_state_path "$tmp_dir" "FE-123")" "phase")" "completion should mark phase done"

grep -Fq "테스트 통과, gap 없음" "$tmp_dir/docs/specs/FE-123/check.md" || fail "check.md should include latest summary"
grep -Fq "docs/checkout.md" "$tmp_dir/docs/specs/FE-123/wrapup.md" || fail "wrapup.md should include affected doc"

echo "execution-loop.test.sh passed"
