#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib/bootstrap.sh
source "$ROOT_DIR/hooks/lib/bootstrap.sh"
# shellcheck source=../lib/planning.sh
source "$ROOT_DIR/hooks/lib/planning.sh"
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

assert_eq "clarify|missing_clarify" "$(cff_routing_required_next_skill "$tmp_dir" "FE-123")" "bootstrap should require clarify"

cff_planning_write_clarify "$tmp_dir" "FE-123" "Checkout 요구사항을 정리하고 open question을 추출한다."
assert_eq "clarify-draft" "$(cff_json_get "$(cff_ticket_state_path "$tmp_dir" "FE-123")" "phase")" "clarify write should move phase to draft"
assert_eq "false" "$(cff_json_get "$(cff_ticket_state_path "$tmp_dir" "FE-123")" "approvals.clarify.approved")" "clarify write should reset approval"
assert_eq "clarify|clarify_not_approved" "$(cff_routing_required_next_skill "$tmp_dir" "FE-123")" "draft clarify should require approval"

cff_planning_approve_stage "$tmp_dir" "FE-123" "clarify"
assert_eq "clarify-approved" "$(cff_json_get "$(cff_ticket_state_path "$tmp_dir" "FE-123")" "phase")" "clarify approval should move phase"
assert_eq "plan|missing_plan" "$(cff_routing_required_next_skill "$tmp_dir" "FE-123")" "approved clarify should route to plan"

cff_planning_write_plan "$tmp_dir" "FE-123" "Checkout 변경 범위, 검증, 롤아웃 순서를 계획한다."
assert_eq "plan-draft" "$(cff_json_get "$(cff_ticket_state_path "$tmp_dir" "FE-123")" "phase")" "plan write should move phase to draft"
assert_eq "plan|plan_not_approved" "$(cff_routing_required_next_skill "$tmp_dir" "FE-123")" "draft plan should require approval"

cff_planning_approve_stage "$tmp_dir" "FE-123" "plan"
assert_eq "design|missing_design" "$(cff_routing_required_next_skill "$tmp_dir" "FE-123")" "approved plan should route to design"

cff_planning_write_design "$tmp_dir" "FE-123" "Checkout UI/상태 변경 설계를 작성하고 atomic task를 생성한다."
assert_eq "design-draft" "$(cff_json_get "$(cff_ticket_state_path "$tmp_dir" "FE-123")" "phase")" "design write should move phase to draft"
assert_eq "true" "$(cff_json_get "$(cff_ticket_state_path "$tmp_dir" "FE-123")" "artifacts.tasks.exists")" "design write should generate tasks"
assert_eq "design|design_not_approved" "$(cff_routing_required_next_skill "$tmp_dir" "FE-123")" "draft design should require approval"

cff_planning_approve_stage "$tmp_dir" "FE-123" "design"
assert_eq "design-approved" "$(cff_json_get "$(cff_ticket_state_path "$tmp_dir" "FE-123")" "phase")" "design approval should move phase"
assert_eq "implement|ready_to_run_implement" "$(cff_routing_required_next_skill "$tmp_dir" "FE-123")" "approved design with tasks should route to implement"

grep -Fq "Checkout 페이지 개선" "$tmp_dir/docs/specs/FE-123/clarify.md" || fail "clarify should include ticket summary"
grep -Fq "Checkout 변경 범위" "$tmp_dir/docs/specs/FE-123/plan.md" || fail "plan should include provided notes"
grep -Fq "\"ticket_key\": \"FE-123\"" "$tmp_dir/docs/specs/FE-123/tasks.json" || fail "tasks.json should include ticket key"

echo "planning-chain.test.sh passed"
