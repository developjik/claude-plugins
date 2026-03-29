#!/usr/bin/env bash
# feature-context.test.sh — feature context 헬퍼 테스트

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

source "${LIB_DIR}/json-utils.sh"
source "${LIB_DIR}/logging.sh"
source "${LIB_DIR}/state-machine.sh"
source "${LIB_DIR}/feature-context.sh"

TESTS_PASSED=0
TESTS_FAILED=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

setup() {
  TEST_DIR=$(mktemp -d)
  mkdir -p "${TEST_DIR}/docs/specs"
}

teardown() {
  rm -rf "$TEST_DIR"
}

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

test_set_and_get_current_feature() {
  setup

  set_current_feature "$TEST_DIR" "feature-alpha" > /dev/null
  local current_feature state_feature
  current_feature=$(get_current_feature "$TEST_DIR")
  state_feature=$(get_feature_slug "$TEST_DIR")

  if assert_equals "feature-alpha" "$current_feature" "Current feature should come from state/cache" && \
     assert_equals "feature-alpha" "$state_feature" "State feature slug should match"; then
    pass "test_set_and_get_current_feature"
  else
    fail "test_set_and_get_current_feature"
  fi

  teardown
}

test_clear_current_feature() {
  setup

  set_current_feature "$TEST_DIR" "feature-beta" > /dev/null
  clear_current_feature "$TEST_DIR"

  local current_feature state_feature
  current_feature=$(get_current_feature "$TEST_DIR")
  state_feature=$(get_feature_slug "$TEST_DIR")

  if assert_equals "" "$current_feature" "Current feature should clear cache" && \
     assert_equals "" "$state_feature" "State feature slug should clear"; then
    pass "test_clear_current_feature"
  else
    fail "test_clear_current_feature"
  fi

  teardown
}

test_infer_feature_from_path() {
  setup

  local feature_slug
  feature_slug=$(infer_feature_from_path "${TEST_DIR}/docs/specs/payments-redesign/design.md")

  if assert_equals "payments-redesign" "$feature_slug" "Feature slug should be inferred from docs path"; then
    pass "test_infer_feature_from_path"
  else
    fail "test_infer_feature_from_path"
  fi

  teardown
}

main() {
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Feature Context Tests"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  test_set_and_get_current_feature
  test_clear_current_feature
  test_infer_feature_from_path

  echo ""
  echo "Passed: $TESTS_PASSED"
  echo "Failed: $TESTS_FAILED"

  if [[ "$TESTS_FAILED" -eq 0 ]]; then
    exit 0
  fi

  exit 1
}

main "$@"
