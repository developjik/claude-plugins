#!/usr/bin/env bash
# browser-testing.sh — 브라우저 테스트 통합 시스템
# P1-4: Playwright 기반 E2E 테스트 자동화
#
# DEPENDENCIES: json-utils.sh, logging.sh, test-runner.sh
#
# 지원 프레임워크:
# - Playwright (JavaScript/TypeScript)
# - Cypress (JavaScript/TypeScript)
# - Selenium (다양한 언어)

set -euo pipefail

# ============================================================================
# 상수
# ============================================================================

readonly BROWSER_TEST_DIR=".harness/browser-tests"
readonly PLAYWRIGHT_CONFIG="playwright.config.ts"
readonly CYPRESS_CONFIG="cypress.config.ts"
readonly DEFAULT_BROWSERS="chromium"
readonly BROWSER_TIMEOUT=300000
readonly RETRY_COUNT=2

if [[ -z "${BROWSER_TESTING_LIB_DIR:-}" ]]; then
  BROWSER_TESTING_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# ============================================================================
# 내부 모듈 로드
# ============================================================================
if ! declare -f browser_test_results_dir > /dev/null 2>&1; then
  # shellcheck source=hooks/lib/browser-test-runner.sh
  source "${BROWSER_TESTING_LIB_DIR}/browser-test-runner.sh"
fi

if ! declare -f generate_html_report > /dev/null 2>&1; then
  # shellcheck source=hooks/lib/browser-test-report.sh
  source "${BROWSER_TESTING_LIB_DIR}/browser-test-report.sh"
fi

# ============================================================================
# 통합 실행
# ============================================================================

# 전체 브라우저 테스트 실행
# Usage: run_full_browser_test_suite <project_root> [options]
run_full_browser_test_suite() {
  local project_root="${1:-}"
  shift

  echo "========================================"
  echo "Browser Test Suite"
  echo "========================================"
  echo ""

  local framework
  framework=$(detect_browser_test_framework "$project_root")

  if [[ "$framework" == "none" ]]; then
    echo "No browser test framework detected."
    echo ""
    echo "Install one of the following:"
    echo "  - Playwright: npm install -D @playwright/test"
    echo "  - Cypress:    npm install -D cypress"
    return 1
  fi

  echo "Framework: $framework"
  echo ""

  echo "Checking setup..."
  local setup_result
  setup_result=$(setup_playwright "$project_root" 2> /dev/null)

  if echo "$setup_result" | jq -e '.success' > /dev/null 2>&1; then
    echo "  Setup OK"
  else
    echo "  Setup issues found:"
    echo "$setup_result" | jq -r '.errors[]? // empty' | while read -r err; do
      echo "    - $err"
    done
  fi
  echo ""

  echo "Checking browser availability..."
  local browser_status
  browser_status=$(check_browser_availability "$project_root")

  if echo "$browser_status" | jq -e '.available' > /dev/null 2>&1; then
    echo "  Browsers ready"
  else
    echo "  Browser issues:"
    echo "$browser_status" | jq -r '.issues[]? // empty' | while read -r issue; do
      echo "    - $issue"
    done
    echo ""
    echo "Installing browsers..."
    install_browsers "$project_root"
  fi
  echo ""

  echo "Running browser tests..."
  echo ""

  local test_result
  test_result=$(run_browser_tests "$project_root" "$@")

  local success total passed failed duration
  success=$(echo "$test_result" | jq -r '.success')
  total=$(echo "$test_result" | jq -r '.summary.total // 0')
  passed=$(echo "$test_result" | jq -r '.summary.passed // 0')
  failed=$(echo "$test_result" | jq -r '.summary.failed // 0')
  duration=$(echo "$test_result" | jq -r '.summary.duration_ms // 0')

  echo ""
  echo "========================================"
  echo "Results"
  echo "========================================"
  echo ""
  echo "  Total:   $total"
  echo "  Passed:  $passed"
  echo "  Failed:  $failed"
  echo "  Duration: ${duration}ms"
  echo ""

  if [[ "$success" == "true" ]]; then
    echo "  Status: PASSED"
  else
    echo "  Status: FAILED"
  fi
  echo ""

  local report
  report=$(generate_html_report "$project_root")
  echo "Report: $(echo "$report" | jq -r '.report_file')"

  echo "$test_result"
}
