#!/usr/bin/env bash
# browser-testing.test.sh — 브라우저 테스트 시스템 테스트
# P1-4: browser-testing.sh 통합 테스트

set -euo pipefail

# 테스트 프레임워크 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

# 라이브러리 로드
source "${LIB_DIR}/json-utils.sh"
source "${LIB_DIR}/logging.sh"
source "${LIB_DIR}/browser-testing.sh"

# 테스트 카운터
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ============================================================================
# 테스트 유틸리티
# ============================================================================

setup() {
  TEST_DIR=$(mktemp -d)
  mkdir -p "${TEST_DIR}/${BROWSER_TEST_DIR}"
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

assert_json_value() {
  local json="${1:-}"
  local path="${2:-}"
  local expected="${3:-}"
  local message="${4:-}"

  local actual
  actual=$(echo "$json" | jq -r "$path" 2>/dev/null)

  if [[ "$expected" == "$actual" ]]; then
    return 0
  else
    echo -e "${RED}✗ Assertion failed: $message${NC}"
    echo "  Path: $path"
    echo "  Expected: $expected"
    echo "  Actual:   $actual"
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

test_detect_browser_test_framework_none() {
  setup

  local framework
  framework=$(detect_browser_test_framework "$TEST_DIR")

  if assert_equals "none" "$framework" "Should detect no framework"; then
    pass "test_detect_browser_test_framework_none"
  else
    fail "test_detect_browser_test_framework_none"
  fi

  teardown
}

test_detect_browser_test_framework_playwright() {
  setup

  # Playwright 패키지 시뮬레이션
  echo '{"devDependencies": {"@playwright/test": "^1.0.0"}}' > "${TEST_DIR}/package.json"

  local framework
  framework=$(detect_browser_test_framework "$TEST_DIR")

  if assert_equals "playwright" "$framework" "Should detect Playwright"; then
    pass "test_detect_browser_test_framework_playwright"
  else
    fail "test_detect_browser_test_framework_playwright"
  fi

  teardown
}

test_detect_browser_test_framework_cypress() {
  setup

  # Cypress 패키지 시뮬레이션
  echo '{"devDependencies": {"cypress": "^10.0.0"}}' > "${TEST_DIR}/package.json"

  local framework
  framework=$(detect_browser_test_framework "$TEST_DIR")

  if assert_equals "cypress" "$framework" "Should detect Cypress"; then
    pass "test_detect_browser_test_framework_cypress"
  else
    fail "test_detect_browser_test_framework_cypress"
  fi

  teardown
}

test_detect_browser_test_framework_by_config() {
  setup

  # Playwright 설정 파일 시뮬레이션
  touch "${TEST_DIR}/playwright.config.ts"

  local framework
  framework=$(detect_browser_test_framework "$TEST_DIR")

  if assert_equals "playwright" "$framework" "Should detect by config file"; then
    pass "test_detect_browser_test_framework_by_config"
  else
    fail "test_detect_browser_test_framework_by_config"
  fi

  teardown
}

test_generate_playwright_config() {
  setup

  local config_file
  config_file=$(generate_playwright_config "$TEST_DIR" "chromium")

  if [[ -f "$config_file" ]]; then
    local content
    content=$(cat "$config_file")

    if echo "$content" | grep -q "defineConfig" && \
       echo "$content" | grep -q "@playwright/test"; then
      pass "test_generate_playwright_config"
    else
      fail "test_generate_playwright_config (missing content)"
    fi
  else
    fail "test_generate_playwright_config (file not created)"
  fi

  teardown
}

test_check_browser_availability_no_framework() {
  setup

  local result
  result=$(check_browser_availability "$TEST_DIR")

  if assert_json_value "$result" ".available" "false" "Should not be available"; then
    pass "test_check_browser_availability_no_framework"
  else
    fail "test_check_browser_availability_no_framework"
  fi

  teardown
}

test_check_browser_availability_with_playwright() {
  setup

  # Playwright 시뮬레이션
  echo '{"devDependencies": {"@playwright/test": "^1.0.0"}}' > "${TEST_DIR}/package.json"

  local result
  result=$(check_browser_availability "$TEST_DIR")

  # 실제 설치 여부와 관계없이 구조 확인
  if echo "$result" | jq -e '.browser' > /dev/null 2>&1; then
    pass "test_check_browser_availability_with_playwright"
  else
    fail "test_check_browser_availability_with_playwright"
  fi

  teardown
}

test_parse_playwright_results_success() {
  setup

  # Playwright 결과 시뮬레이션
  local output_file="${TEST_DIR}/${BROWSER_TEST_DIR}/output.json"
  cat > "$output_file" << 'EOF'
{
  "stats": {
    "tests": 10,
    "passed": 8,
    "failed": 2,
    "skipped": 0,
    "duration": 5000
  }
}
EOF

  local result
  result=$(parse_playwright_results "$output_file" 1)

  if assert_json_value "$result" ".summary.total" "10" "Total should be 10" && \
     assert_json_value "$result" ".summary.passed" "8" "Passed should be 8"; then
    pass "test_parse_playwright_results_success"
  else
    fail "test_parse_playwright_results_success"
  fi

  teardown
}

test_parse_playwright_results_invalid_json() {
  setup

  local output_file="${TEST_DIR}/${BROWSER_TEST_DIR}/output.json"
  echo "invalid json" > "$output_file"

  local result
  result=$(parse_playwright_results "$output_file" 1)

  if assert_json_value "$result" ".success" "false" "Should fail for invalid JSON"; then
    pass "test_parse_playwright_results_invalid_json"
  else
    fail "test_parse_playwright_results_invalid_json"
  fi

  teardown
}

test_parse_cypress_results() {
  setup

  # Cypress 결과 시뮬레이션
  local output_file="${TEST_DIR}/${BROWSER_TEST_DIR}/cypress_output.json"
  cat > "$output_file" << 'EOF'
{
  "stats": {
    "tests": 15,
    "passes": 14,
    "failures": 1,
    "duration": 8000
  }
}
EOF

  local result
  result=$(parse_cypress_results "$output_file" 0)

  if assert_json_value "$result" ".summary.total" "15" "Total should be 15" && \
     assert_json_value "$result" ".framework" "cypress" "Framework should be cypress"; then
    pass "test_parse_cypress_results"
  else
    fail "test_parse_cypress_results"
  fi

  teardown
}

test_generate_html_report() {
  setup

  # 결과 파일 생성
  local results_file="${TEST_DIR}/${BROWSER_TEST_DIR}/browser_test_20260328.json"
  cat > "$results_file" << 'EOF'
{
  "success": true,
  "framework": "playwright",
  "timestamp": "20260328_120000",
  "summary": {
    "total": 10,
    "passed": 10,
    "failed": 0,
    "skipped": 0,
    "duration_ms": 5000
  }
}
EOF

  local report
  report=$(generate_html_report "$TEST_DIR" "$results_file")

  if echo "$report" | jq -e '.report_file' > /dev/null 2>&1; then
    local report_file
    report_file=$(echo "$report" | jq -r '.report_file')

    if [[ -f "$report_file" ]]; then
      local content
      content=$(cat "$report_file")

      if echo "$content" | grep -q "Browser Test Report" && \
         echo "$content" | grep -q "PASSED"; then
        pass "test_generate_html_report"
      else
        fail "test_generate_html_report (missing content)"
      fi
    else
      fail "test_generate_html_report (file not created)"
    fi
  else
    fail "test_generate_html_report (invalid response)"
  fi

  teardown
}

test_get_browser_test_history_empty() {
  setup

  local history
  history=$(get_browser_test_history "$TEST_DIR" 10)

  if assert_json_value "$history" ". | length" "0" "Should have empty history"; then
    pass "test_get_browser_test_history_empty"
  else
    fail "test_get_browser_test_history_empty"
  fi

  teardown
}

test_get_browser_test_history_with_data() {
  setup

  # 여러 결과 파일 생성
  for i in 1 2 3; do
    cat > "${TEST_DIR}/${BROWSER_TEST_DIR}/browser_test_2026032${i}.json" << EOF
{
  "success": true,
  "framework": "playwright",
  "timestamp": "2026032${i}",
  "summary": {"total": 10, "passed": $((10 - i)), "failed": $i, "skipped": 0, "duration_ms": 5000}
}
EOF
  done

  local history
  history=$(get_browser_test_history "$TEST_DIR" 10)

  local count
  count=$(echo "$history" | jq 'length')

  if [[ "$count" -ge 3 ]]; then
    pass "test_get_browser_test_history_with_data ($count entries)"
  else
    fail "test_get_browser_test_history_with_data (expected >=3, got $count)"
  fi

  teardown
}

test_cleanup_old_browser_results() {
  setup

  # 최신 파일
  echo '{}' > "${TEST_DIR}/${BROWSER_TEST_DIR}/new_result.json"

  # 오래된 파일
  echo '{}' > "${TEST_DIR}/${BROWSER_TEST_DIR}/old_result.json"
  touch -t 202001010000 "${TEST_DIR}/${BROWSER_TEST_DIR}/old_result.json"

  local cleaned
  cleaned=$(cleanup_old_browser_results "$TEST_DIR" 7)

  if [[ "$cleaned" -ge 1 ]]; then
    pass "test_cleanup_old_browser_results ($cleaned files cleaned)"
  else
    fail "test_cleanup_old_browser_results (expected >=1, got $cleaned)"
  fi

  teardown
}

test_run_browser_tests_no_framework() {
  setup

  # 프레임워크 없이 실행
  local result
  result=$(run_browser_tests "$TEST_DIR" 2>/dev/null || echo '{"success": false}')

  if assert_json_value "$result" ".success" "false" "Should fail without framework"; then
    pass "test_run_browser_tests_no_framework"
  else
    fail "test_run_browser_tests_no_framework"
  fi

  teardown
}

# ============================================================================
# 메인 실행
# ============================================================================

main() {
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Browser Testing System - Integration Tests"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  # jq 확인
  if ! command -v jq &>/dev/null; then
    echo "ERROR: jq is required for tests"
    echo "Install: brew install jq"
    exit 1
  fi

  # 테스트 실행
  test_detect_browser_test_framework_none
  test_detect_browser_test_framework_playwright
  test_detect_browser_test_framework_cypress
  test_detect_browser_test_framework_by_config
  test_generate_playwright_config
  test_check_browser_availability_no_framework
  test_check_browser_availability_with_playwright
  test_parse_playwright_results_success
  test_parse_playwright_results_invalid_json
  test_parse_cypress_results
  test_generate_html_report
  test_get_browser_test_history_empty
  test_get_browser_test_history_with_data
  test_cleanup_old_browser_results
  test_run_browser_tests_no_framework

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

main "$@"
