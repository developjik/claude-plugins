#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib/bootstrap.sh
source "$ROOT_DIR/hooks/lib/bootstrap.sh"
# shellcheck source=../lib/planning.sh
source "$ROOT_DIR/hooks/lib/planning.sh"
# shellcheck source=../lib/state.sh
source "$ROOT_DIR/hooks/lib/state.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
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

printf '{"cwd":"%s"}' "$tmp_dir" | bash "$ROOT_DIR/hooks/session-start.sh" >/dev/null
[[ -f "$tmp_dir/.colo-fe-flow/.state/index.json" ]] || fail "session-start should initialize index"
grep -Fq "SESSION_START" "$tmp_dir/.colo-fe-flow/.log/session.log" || fail "session-start should log session start"

cff_bootstrap_ticket \
  "$tmp_dir" \
  "FE-123" \
  "10001" \
  "Checkout 페이지 개선" \
  "https://jira.example.com/browse/FE-123"
cff_planning_write_clarify "$tmp_dir" "FE-123" "Clarify checkout."
cff_planning_approve_stage "$tmp_dir" "FE-123" "clarify"
cff_planning_write_plan "$tmp_dir" "FE-123" "Plan checkout."
cff_planning_approve_stage "$tmp_dir" "FE-123" "plan"
cff_planning_write_design "$tmp_dir" "FE-123" "Design checkout."
cff_planning_approve_stage "$tmp_dir" "FE-123" "design"

pre_payload=$(printf '{"cwd":"%s","tool_name":"Edit","tool_input":{"file_path":"docs/specs/FE-123/plan.md"}}' "$tmp_dir")
echo "$pre_payload" | bash "$ROOT_DIR/hooks/pre-tool.sh" >/dev/null

[[ "$(cff_json_get "$(cff_ticket_state_path "$tmp_dir" "FE-123")" "approvals.plan.approved")" == "false" ]] || fail "pre-tool should reset edited plan approval"
[[ "$(cff_json_get "$(cff_ticket_state_path "$tmp_dir" "FE-123")" "approvals.design.approved")" == "false" ]] || fail "pre-tool should reset downstream design approval"
[[ "$(cff_json_get "$(cff_ticket_state_path "$tmp_dir" "FE-123")" "phase")" == "plan-draft" ]] || fail "pre-tool should move edited plan back to draft"

echo "$pre_payload" | bash "$ROOT_DIR/hooks/post-tool.sh" >/dev/null
[[ "$(cff_json_get "$(cff_ticket_state_path "$tmp_dir" "FE-123")" "artifacts.plan.exists")" == "true" ]] || fail "post-tool should keep edited artifact present"
grep -Fq "POST_TOOL" "$tmp_dir/.colo-fe-flow/.log/FE-123/orchestration.log" || fail "post-tool should log ticket event"

agent_payload=$(printf '{"cwd":"%s","agent_name":"planning-agent"}' "$tmp_dir")
echo "$agent_payload" | bash "$ROOT_DIR/hooks/on-agent-start.sh" >/dev/null
echo "$agent_payload" | bash "$ROOT_DIR/hooks/on-agent-stop.sh" >/dev/null

grep -Fq "AGENT_START planning-agent" "$tmp_dir/.colo-fe-flow/.log/agents.log" || fail "agent start should be logged"
grep -Fq "AGENT_STOP planning-agent" "$tmp_dir/.colo-fe-flow/.log/agents.log" || fail "agent stop should be logged"

echo "hook-flow.test.sh passed"
