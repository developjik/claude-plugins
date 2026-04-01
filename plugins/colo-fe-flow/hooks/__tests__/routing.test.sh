#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib/state.sh
source "$ROOT_DIR/hooks/lib/state.sh"
# shellcheck source=../lib/approval.sh
source "$ROOT_DIR/hooks/lib/approval.sh"
# shellcheck source=../lib/routing.sh
source "$ROOT_DIR/hooks/lib/routing.sh"
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

cff_state_init_ticket "$tmp_dir" "FE-123"

assert_eq "intake|missing_intake" "$(cff_routing_required_next_skill "$tmp_dir" "FE-123")" "missing intake should route to intake"

cff_state_set_artifact "$tmp_dir" "FE-123" "intake" "docs/specs/FE-123/intake.md" "true" "2026-04-01T10:10:00+09:00"
assert_eq "clarify|missing_clarify" "$(cff_routing_required_next_skill "$tmp_dir" "FE-123")" "missing clarify should route to clarify"

cff_state_set_artifact "$tmp_dir" "FE-123" "clarify" "docs/specs/FE-123/clarify.md" "true" "2026-04-01T10:30:00+09:00"
cff_approval_set "$tmp_dir" "FE-123" "clarify" "true"
cff_state_set_artifact "$tmp_dir" "FE-123" "plan" "docs/specs/FE-123/plan.md" "true" "2026-04-01T10:45:00+09:00"
cff_approval_set "$tmp_dir" "FE-123" "plan" "true"
cff_state_set_artifact "$tmp_dir" "FE-123" "design" "docs/specs/FE-123/design.md" "true" "2026-04-01T11:00:00+09:00"
cff_approval_set "$tmp_dir" "FE-123" "design" "true"

assert_eq "design|missing_tasks" "$(cff_routing_required_next_skill "$tmp_dir" "FE-123")" "missing tasks should redirect to design"

cff_state_set_artifact "$tmp_dir" "FE-123" "tasks" "docs/specs/FE-123/tasks.json" "true" "2026-04-01T11:01:00+09:00"
assert_eq "implement|ready_to_run_implement" "$(cff_routing_required_next_skill "$tmp_dir" "FE-123")" "ready design with tasks should route to implement"

python3 - "$(cff_ticket_state_path "$tmp_dir" "FE-123")" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, "r", encoding="utf-8") as handle:
    data = json.load(handle)
data["implementation"]["finished"] = True
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=True, indent=2)
    handle.write("\n")
PY

assert_eq "check|missing_check" "$(cff_routing_required_next_skill "$tmp_dir" "FE-123")" "finished implementation without check should route to check"

cff_state_set_artifact "$tmp_dir" "FE-123" "check" "docs/specs/FE-123/check.md" "true" "2026-04-01T11:18:00+09:00"
cff_verification_record_check "$tmp_dir" "FE-123" "failed" "2" "84" "passed" "passed" "not_run" "failed"
assert_eq "iterate|check_failed" "$(cff_routing_required_next_skill "$tmp_dir" "FE-123")" "failed check should route to iterate"

cff_verification_record_check "$tmp_dir" "FE-123" "passed" "0" "97" "passed" "passed" "not_run" "passed"
assert_eq "sync-docs|docs_not_synced" "$(cff_routing_required_next_skill "$tmp_dir" "FE-123")" "passed check without wrapup should route to sync-docs"

cff_state_set_artifact "$tmp_dir" "FE-123" "wrapup" "docs/specs/FE-123/wrapup.md" "true" "2026-04-01T12:10:00+09:00"
cff_state_set_doc_sync "$tmp_dir" "FE-123" "true" "2026-04-01T12:11:00+09:00" '["docs/README.md"]'
assert_eq "complete-ticket|ready_to_complete" "$(cff_routing_required_next_skill "$tmp_dir" "FE-123")" "fully synced ticket should be ready to complete"

echo "routing.test.sh passed"

