#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib/state.sh
source "$ROOT_DIR/hooks/lib/state.sh"
# shellcheck source=../lib/approval.sh
source "$ROOT_DIR/hooks/lib/approval.sh"
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

assert_json_value() {
  local file_path="$1"
  local json_path="$2"
  local expected="$3"
  local message="$4"
  local actual

  actual="$(cff_json_get "$file_path" "$json_path")"
  assert_eq "$expected" "$actual" "$message"
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

cat > "$tmp_dir/.mcp.json" <<'JSON'
{
  "mcpServers": {
    "atlassian": {},
    "figma": {}
  }
}
JSON

assert_eq "run_implement" "$(cff_routing_normalize_action "이제 구현 들어가자")" "implement request should normalize"
assert_eq "FE-123" "$(cff_routing_extract_requested_ticket "FE-123 구현하자")" "ticket key should be extracted"
assert_eq "implement" "$(cff_routing_action_to_skill "run_implement")" "implement action should map to skill"

no_ticket_json="$tmp_dir/no-ticket.json"
cff_routing_route_result_json "$tmp_dir" "이제 계획하자" > "$no_ticket_json"
assert_json_value "$no_ticket_json" "decision" "block" "missing ticket should block"
assert_json_value "$no_ticket_json" "reason_code" "no_ticket_context" "missing ticket should explain context gap"
assert_json_value "$no_ticket_json" "requires_user_input" "true" "missing ticket should require user input"

list_json="$tmp_dir/list.json"
cff_routing_route_result_json "$tmp_dir" "티켓 목록 보여줘" > "$list_json"
assert_json_value "$list_json" "decision" "execute" "list request should execute directly"
assert_json_value "$list_json" "next_skill" "list-tickets" "list request should route to list-tickets"
assert_json_value "$list_json" "reason_code" "user_input_required" "list request should use utility reason"

cff_state_init_ticket "$tmp_dir" "FE-123"
cff_state_set_active_ticket "$tmp_dir" "FE-123"
cff_state_set_phase "$tmp_dir" "FE-123" "design-approved"
cff_state_set_artifact "$tmp_dir" "FE-123" "intake" "docs/specs/FE-123/intake.md" "true" "2026-04-01T10:10:00+09:00"
cff_state_set_artifact "$tmp_dir" "FE-123" "clarify" "docs/specs/FE-123/clarify.md" "true" "2026-04-01T10:30:00+09:00"
cff_approval_set "$tmp_dir" "FE-123" "clarify" "true"
cff_state_set_artifact "$tmp_dir" "FE-123" "plan" "docs/specs/FE-123/plan.md" "true" "2026-04-01T10:45:00+09:00"
cff_approval_set "$tmp_dir" "FE-123" "plan" "true"
cff_state_set_artifact "$tmp_dir" "FE-123" "design" "docs/specs/FE-123/design.md" "true" "2026-04-01T11:00:00+09:00"
cff_approval_set "$tmp_dir" "FE-123" "design" "true"

mkdir -p "$tmp_dir/docs/specs/FE-123"
touch "$tmp_dir/docs/specs/FE-123/intake.md"
touch "$tmp_dir/docs/specs/FE-123/clarify.md"
touch "$tmp_dir/docs/specs/FE-123/plan.md"
touch "$tmp_dir/docs/specs/FE-123/design.md"

missing_tasks_json="$tmp_dir/missing-tasks.json"
cff_routing_route_result_json "$tmp_dir" "이제 구현 들어가자" > "$missing_tasks_json"
assert_json_value "$missing_tasks_json" "decision" "redirect" "missing tasks should redirect"
assert_json_value "$missing_tasks_json" "next_skill" "design" "missing tasks should redirect to design"
assert_json_value "$missing_tasks_json" "reason_code" "missing_tasks" "missing tasks should use missing_tasks reason"

cff_state_set_artifact "$tmp_dir" "FE-123" "tasks" "docs/specs/FE-123/tasks.json" "true" "2026-04-01T11:01:00+09:00"
printf '{ "tasks": [] }\n' > "$tmp_dir/docs/specs/FE-123/tasks.json"

implement_json="$tmp_dir/implement.json"
cff_routing_route_result_json "$tmp_dir" "이제 구현 들어가자" > "$implement_json"
assert_json_value "$implement_json" "decision" "execute" "implement should execute when tasks exist"
assert_json_value "$implement_json" "next_skill" "implement" "implement should route to implement"
assert_json_value "$implement_json" "reason_code" "ready_to_run_implement" "implement should use ready reason"

explicit_ticket_json="$tmp_dir/explicit-ticket.json"
cff_routing_route_result_json "$tmp_dir" "FE-456 상태 보여줘" > "$explicit_ticket_json"
assert_json_value "$explicit_ticket_json" "resolved_ticket" "FE-456" "explicit ticket should override active ticket"
assert_json_value "$explicit_ticket_json" "decision" "execute" "status utility should execute directly"
assert_json_value "$explicit_ticket_json" "next_skill" "show-ticket-status" "status utility should route to show-ticket-status"

echo "route-workflow.test.sh passed"
