#!/usr/bin/env bash
# hook-flow.test.sh — 세션/도구/에이전트 훅 상태 연동 테스트

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

TESTS_PASSED=0
TESTS_FAILED=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() {
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo -e "${GREEN}✓ ${1:-}${NC}"
}

fail() {
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo -e "${RED}✗ ${1:-}${NC}"
}

assert_equals() {
  local expected="${1:-}"
  local actual="${2:-}"
  local message="${3:-}"

  if [[ "$expected" == "$actual" ]]; then
    return 0
  fi

  echo -e "${RED}Assertion failed: ${message}${NC}"
  echo "  Expected: $expected"
  echo "  Actual:   $actual"
  return 1
}

test_feature_context_flows_across_hooks() {
  local test_dir
  test_dir=$(mktemp -d)
  mkdir -p "${test_dir}/docs/specs/hook-flow"
  touch "${test_dir}/docs/specs/hook-flow/clarify.md"

  printf '{"cwd":"%s"}\n' "$test_dir" | bash hooks/session-start.sh >/dev/null 2>/dev/null
  printf '{"cwd":"%s","tool_name":"Write","tool_input":{"file_path":"docs/specs/hook-flow/clarify.md"}}\n' "$test_dir" | \
    bash hooks/pre-tool.sh >/dev/null 2>/dev/null
  printf '{"cwd":"%s","tool_name":"Write","tool_input":{"file_path":"docs/specs/hook-flow/clarify.md"}}\n' "$test_dir" | \
    bash hooks/post-tool.sh >/dev/null 2>/dev/null
  printf '{"cwd":"%s","agent_name":"strategist"}\n' "$test_dir" | \
    bash hooks/on-agent-start.sh >/dev/null 2>/dev/null

  local cached_feature cached_phase state_feature state_phase
  cached_feature=$(cat "${test_dir}/.harness/state/current-feature.txt" 2>/dev/null || true)
  cached_phase=$(cat "${test_dir}/.harness/state/pdca-phase.txt" 2>/dev/null || true)
  state_feature=$(jq -r '.feature_slug // empty' "${test_dir}/.harness/engine/state.json" 2>/dev/null || true)
  state_phase=$(jq -r '.phase // empty' "${test_dir}/.harness/engine/state.json" 2>/dev/null || true)

  if assert_equals "hook-flow" "$cached_feature" "Feature cache should be inferred from docs path" && \
     assert_equals "hook-flow" "$state_feature" "State feature should match" && \
     assert_equals "plan" "$cached_phase" "Phase cache should move with agent" && \
     assert_equals "plan" "$state_phase" "State phase should match"; then
    pass "test_feature_context_flows_across_hooks"
  else
    fail "test_feature_context_flows_across_hooks"
  fi

  rm -rf "$test_dir"
}

main() {
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Hook Flow Tests"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  test_feature_context_flows_across_hooks

  echo ""
  echo "Passed: $TESTS_PASSED"
  echo "Failed: $TESTS_FAILED"

  if [[ "$TESTS_FAILED" -eq 0 ]]; then
    exit 0
  fi

  exit 1
}

main "$@"
