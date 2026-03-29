#!/usr/bin/env bash
# test-runner.test.sh — 테스트 러너 시스템 통합 테스트
# P0-1: 테스트 실행 통합

set -euo pipefail

# 테스트 프레임워크 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

# 라이브러리 로드
source "${LIB_DIR}/json-utils.sh"
source "${LIB_DIR}/logging.sh"
source "${LIB_DIR}/test-runner.sh"

# 테스트 카운터
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ============================================================================
# 테스트 유틸리티
# ============================================================================

setup() {
  TEST_DIR=$(mktemp -d)
  mkdir -p "${TEST_DIR}/.harness/logs"
  TESTS_RUN=$((TESTS_RUN + 1))
}

teardown() {
  rm -rf "$TEST_DIR"
}

assert_equals() {
  local expected="${1:-}"
  local actual="${2:-}"
  local message="${3:-}"

  if [[ "$expected" == "$actual" ]]; then
    return 0
  else
    echo -e "${RED}✗ Assertion failed: $message${NC}"
    echo "  Expected: $expected"
    echo "  Actual:   $actual"
    return 1
  fi
}

assert_contains() {
  local needle="${1:-}"
  local haystack="${2:-}"
  local message="${3:-}"

  if [[ "$haystack" == *"$needle"* ]]; then
    return 0
  else
    echo -e "${RED}✗ Assertion failed: $message${NC}"
    echo "  Expected to contain: $needle"
    echo "  Actual: $haystack"
    return 1
  fi
}

assert_file_exists() {
  local file="${1:-}"
  local message="${2:-File should exist}"

  if [[ -f "$file" ]]; then
    return 0
  else
    echo -e "${RED}✗ Assertion failed: $message${NC}"
    echo "  File not found: $file"
    return 1
  fi
}

pass() {
  local message="${1:-}"
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo -e "${GREEN}✓ $message${NC}"
}

fail() {
  local message="${1:-}"
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo -e "${RED}✗ $message${NC}"
}

# ============================================================================
# 테스트 케이스
# ============================================================================

test_detect_test_framework_jest() {
  setup

  # Jest 프로젝트 생성
  cat > "${TEST_DIR}/package.json" << 'EOF'
{
  "name": "test-project",
  "devDependencies": {
    "jest": "^29.0.0"
  }
}
EOF

  local result
  result=$(detect_test_framework "$TEST_DIR")

  if assert_equals "jest" "$result" "Should detect jest framework"; then
    pass "test_detect_test_framework_jest"
  else
    fail "test_detect_test_framework_jest"
  fi

  teardown
}

test_detect_test_framework_pytest() {
  setup

  # Pytest 프로젝트 생성
  cat > "${TEST_DIR}/pytest.ini" << 'EOF'
[pytest]
testpaths = tests
EOF

  local result
  result=$(detect_test_framework "$TEST_DIR")

  if assert_equals "pytest" "$result" "Should detect pytest framework"; then
    pass "test_detect_test_framework_pytest"
  else
    fail "test_detect_test_framework_pytest"
  fi

  teardown
}

test_detect_test_framework_go() {
  setup

  # Go 프로젝트 생성
  cat > "${TEST_DIR}/go.mod" << 'EOF'
module example.com/test

go 1.21
EOF

  local result
  result=$(detect_test_framework "$TEST_DIR")

  if assert_equals "go_test" "$result" "Should detect go_test framework"; then
    pass "test_detect_test_framework_go"
  else
    fail "test_detect_test_framework_go"
  fi

  teardown
}

test_detect_test_framework_none() {
  setup

  # 아무것도 없는 디렉토리
  local result
  result=$(detect_test_framework "$TEST_DIR")

  if assert_equals "none" "$result" "Should return none for empty project"; then
    pass "test_detect_test_framework_none"
  else
    fail "test_detect_test_framework_none"
  fi

  teardown
}

test_get_test_command_jest() {
  setup

  cat > "${TEST_DIR}/package.json" << 'EOF'
{"devDependencies": {"jest": "^29.0.0"}}
EOF

  local cmd
  cmd=$(get_test_command "jest" "$TEST_DIR" "")

  if assert_contains "npm test" "$cmd" "Should contain npm test command" && \
     assert_contains "--json" "$cmd" "Should contain json flag"; then
    pass "test_get_test_command_jest"
  else
    fail "test_get_test_command_jest"
  fi

  teardown
}

test_get_test_command_with_filter() {
  setup

  local cmd
  cmd=$(get_test_command "jest" "$TEST_DIR" "user-auth")

  if assert_contains "testNamePattern" "$cmd" "Should contain test pattern" && \
     assert_contains "user-auth" "$cmd" "Should contain filter value"; then
    pass "test_get_test_command_with_filter"
  else
    fail "test_get_test_command_with_filter"
  fi

  teardown
}

test_parse_jest_output() {
  setup

  # Jest 결과 JSON 생성
  mkdir -p "${TEST_DIR}"
  cat > "${TEST_DIR}/test-results.json" << 'EOF'
{
  "numPassedTests": 10,
  "numFailedTests": 2,
  "numPendingTests": 1,
  "numTotalTests": 13,
  "testResults": [{
    "perfStats": {"runtime": 1.5}
  }]
}
EOF

  local result
  result=$(parse_jest_output "$TEST_DIR" "0")

  local passed failed total
  passed=$(echo "$result" | jq -r '.passed')
  failed=$(echo "$result" | jq -r '.failed')
  total=$(echo "$result" | jq -r '.total')

  if assert_equals "10" "$passed" "Passed count should be 10" && \
     assert_equals "2" "$failed" "Failed count should be 2" && \
     assert_equals "13" "$total" "Total count should be 13"; then
    pass "test_parse_jest_output"
  else
    fail "test_parse_jest_output"
  fi

  teardown
}

test_check_test_success_rate_passing() {
  local results='{"passed": 90, "failed": 10, "total": 100}'

  if check_test_success_rate "$results" "0.9" | grep -q "true"; then
    pass "test_check_test_success_rate_passing"
  else
    fail "test_check_test_success_rate_passing"
  fi
}

test_check_test_success_rate_failing() {
  local results='{"passed": 80, "failed": 20}'

  # 함수가 false를 출력하는지 확인 (return 1이어도 출력 확인)
  local output
  output=$(check_test_success_rate "$results" "0.9" 2>/dev/null || true)

  if echo "$output" | grep -q "false"; then
    pass "test_check_test_success_rate_failing"
  else
    fail "test_check_test_success_rate_failing"
  fi
}

test_summarize_test_results() {
  local results='{
    "framework": "jest",
    "passed": 10,
    "failed": 2,
    "skipped": 1,
    "total": 13,
    "exit_code": 1
  }'

  local summary
  summary=$(summarize_test_results "$results" 2>/dev/null || true)

  if assert_contains "10" "$summary" "Should show passed count" && \
     assert_contains "2" "$summary" "Should show failed count"; then
    pass "test_summarize_test_results"
  else
    fail "test_summarize_test_results"
  fi
}

# ============================================================================
# 메인 실행
# ============================================================================

main() {
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Test Runner System - Integration Tests"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  # 테스트 실행
  test_detect_test_framework_jest
  test_detect_test_framework_pytest
  test_detect_test_framework_go
  test_detect_test_framework_none
  test_get_test_command_jest
  test_get_test_command_with_filter
  test_parse_jest_output
  test_check_test_success_rate_passing
  test_check_test_success_rate_failing
  test_summarize_test_results

  # 결과 요약
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Test Summary"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "  Total:   $TESTS_RUN"
  echo -e "  ${GREEN}Passed:  $TESTS_PASSED${NC}"
  echo -e "  ${RED}Failed:  $TESTS_FAILED${NC}"
  echo ""

  if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}✅ All tests passed!${NC}"
    exit 0
  else
    echo -e "${RED}❌ Some tests failed.${NC}"
    exit 1
  fi
}

# jq 확인
if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is required for tests"
  echo "Install: brew install jq"
  exit 1
fi

main "$@"
