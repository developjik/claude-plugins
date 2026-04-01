#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib/state.sh
source "$ROOT_DIR/hooks/lib/state.sh"
# shellcheck source=../lib/utility.sh
source "$ROOT_DIR/hooks/lib/utility.sh"

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

cff_state_init_ticket "$tmp_dir" "FE-123"
cff_state_init_ticket "$tmp_dir" "FE-456"
cff_state_set_active_ticket "$tmp_dir" "FE-123"
cff_state_set_phase "$tmp_dir" "FE-123" "plan-approved"
cff_state_set_phase "$tmp_dir" "FE-456" "blocked"
cff_state_set_status "$tmp_dir" "FE-456" "blocked"

list_json="$tmp_dir/list.json"
cff_utility_list_tickets_json "$tmp_dir" > "$list_json"
assert_json_value "$list_json" "active_ticket" "FE-123" "list should expose active ticket"
assert_json_value "$list_json" "tickets.0.ticket_key" "FE-123" "first ticket should be FE-123"
assert_json_value "$list_json" "tickets.0.is_active" "true" "first ticket should be active"
assert_json_value "$list_json" "tickets.1.ticket_key" "FE-456" "second ticket should be FE-456"
assert_json_value "$list_json" "tickets.1.status" "blocked" "second ticket should expose status"

status_json="$tmp_dir/status.json"
cff_utility_show_ticket_status_json "$tmp_dir" > "$status_json"
assert_json_value "$status_json" "ticket_key" "FE-123" "status without explicit ticket should use active ticket"
assert_json_value "$status_json" "phase" "plan-approved" "status should expose phase"
assert_json_value "$status_json" "is_active" "true" "active ticket should be marked active"

explicit_status_json="$tmp_dir/explicit-status.json"
cff_utility_show_ticket_status_json "$tmp_dir" "FE-456" > "$explicit_status_json"
assert_json_value "$explicit_status_json" "ticket_key" "FE-456" "explicit status should use requested ticket"
assert_json_value "$explicit_status_json" "is_active" "false" "non-active explicit ticket should not be marked active"

cff_utility_switch_ticket "$tmp_dir" "FE-456"
assert_eq "FE-456" "$(cff_state_get_active_ticket "$tmp_dir")" "switch should update active ticket"
assert_eq "FE-123" "$(cff_json_get "$(cff_index_path "$tmp_dir")" "last_ticket")" "switch should preserve last ticket"

after_switch_json="$tmp_dir/after-switch.json"
cff_utility_show_ticket_status_json "$tmp_dir" > "$after_switch_json"
assert_json_value "$after_switch_json" "ticket_key" "FE-456" "status should follow switched active ticket"
assert_json_value "$after_switch_json" "is_active" "true" "switched ticket should now be active"

if cff_utility_switch_ticket "$tmp_dir" "FE-999" 2>/dev/null; then
  fail "switching to unknown ticket should fail"
fi

echo "utility.test.sh passed"
