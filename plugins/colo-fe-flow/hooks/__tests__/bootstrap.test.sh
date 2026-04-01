#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib/bootstrap.sh
source "$ROOT_DIR/hooks/lib/bootstrap.sh"
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

index_path="$(cff_index_path "$tmp_dir")"
ticket_path="$(cff_ticket_state_path "$tmp_dir" "FE-123")"
intake_path="$tmp_dir/docs/specs/FE-123/intake.md"

[[ -f "$index_path" ]] || fail "index.json should exist"
[[ -f "$ticket_path" ]] || fail "ticket state should exist"
[[ -f "$intake_path" ]] || fail "intake.md should exist"

assert_eq "FE-123" "$(cff_json_get "$index_path" "active_ticket")" "active ticket should be stored"
assert_eq "10001" "$(cff_json_get "$ticket_path" "sources.jira.issue_id")" "jira issue id should be stored"
assert_eq "Checkout 페이지 개선" "$(cff_json_get "$ticket_path" "sources.jira.summary")" "jira summary should be stored"
assert_eq "https://jira.example.com/browse/FE-123" "$(cff_json_get "$ticket_path" "sources.jira.url")" "jira url should be stored"
assert_eq "$tmp_dir/.worktrees/FE-123" "$(cff_json_get "$ticket_path" "workspace.worktree_path")" "worktree path should be stored"
assert_eq "feat/FE-123" "$(cff_json_get "$ticket_path" "workspace.branch_name")" "branch name should be stored"
assert_eq "true" "$(cff_json_get "$ticket_path" "artifacts.intake.exists")" "intake artifact should be marked present"
assert_eq "branch-ready" "$(cff_json_get "$ticket_path" "phase")" "ticket phase should advance to branch-ready"

grep -Fq "FE-123" "$intake_path" || fail "intake should include ticket key"
grep -Fq "Checkout 페이지 개선" "$intake_path" || fail "intake should include ticket summary"
grep -Fq "https://jira.example.com/browse/FE-123" "$intake_path" || fail "intake should include jira url"
grep -Fq "$tmp_dir/.worktrees/FE-123" "$intake_path" || fail "intake should include worktree path"

assert_eq "clarify|missing_clarify" "$(cff_routing_required_next_skill "$tmp_dir" "FE-123")" "bootstrap should leave ticket ready for clarify"

echo "bootstrap.test.sh passed"
