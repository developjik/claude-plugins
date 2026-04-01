#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib/state.sh
source "$ROOT_DIR/hooks/lib/state.sh"
# shellcheck source=../lib/approval.sh
source "$ROOT_DIR/hooks/lib/approval.sh"
# shellcheck source=../lib/verification.sh
source "$ROOT_DIR/hooks/lib/verification.sh"

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

cff_state_init_index "$tmp_dir"
[[ -f "$(cff_index_path "$tmp_dir")" ]] || fail "expected index.json to exist"

cff_state_init_ticket "$tmp_dir" "FE-123" "$tmp_dir" "$tmp_dir/.worktrees/FE-123" "feat/FE-123" "main"
cff_state_set_active_ticket "$tmp_dir" "FE-123"

assert_eq "FE-123" "$(cff_state_get_active_ticket "$tmp_dir")" "active ticket should be stored"
assert_eq "intake" "$(cff_json_get "$(cff_ticket_state_path "$tmp_dir" "FE-123")" "phase")" "ticket phase should initialize to intake"
assert_eq "false" "$(cff_json_get "$(cff_ticket_state_path "$tmp_dir" "FE-123")" "artifacts.tasks.exists")" "tasks artifact should start absent"

cff_state_set_artifact "$tmp_dir" "FE-123" "design" "docs/specs/FE-123/design.md" "true" "2026-04-01T11:00:00+09:00"
assert_eq "true" "$(cff_json_get "$(cff_ticket_state_path "$tmp_dir" "FE-123")" "artifacts.design.exists")" "design artifact should update"

cff_approval_set "$tmp_dir" "FE-123" "design" "true" "2026-04-01T11:02:00+09:00"
assert_eq "true" "$(cff_json_get "$(cff_ticket_state_path "$tmp_dir" "FE-123")" "approvals.design.approved")" "design approval should update"

cff_verification_record_check "$tmp_dir" "FE-123" "passed" "0" "91" "passed" "passed" "not_run" "passed"
assert_eq "passed" "$(cff_verification_last_status "$tmp_dir" "FE-123")" "verification status should update"
assert_eq "0" "$(cff_verification_open_gaps "$tmp_dir" "FE-123")" "open gaps should update"

cff_state_set_doc_sync "$tmp_dir" "FE-123" "true" "2026-04-01T12:00:00+09:00" '["docs/README.md"]'
assert_eq "true" "$(cff_json_get "$(cff_ticket_state_path "$tmp_dir" "FE-123")" "doc_sync.completed")" "doc sync should update"

echo "state.test.sh passed"

