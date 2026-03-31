#!/usr/bin/env bash
# test-runner.sh — 테스트 실행 및 결과 분석 라이브러리
# P0-1: 테스트 실행 통합
#
# DEPENDENCIES: json-utils.sh, logging.sh
#
# 지원 프레임워크:
# - JavaScript: jest, vitest, mocha
# - Python: pytest, unittest
# - Go: go test
# - Rust: cargo test
# - Java: maven, gradle
# - Ruby: rspec

set -euo pipefail

# ============================================================================
# 상수
# ============================================================================

readonly TEST_RESULTS_DIR=".harness/test-results"
readonly TEST_TIMEOUT=300
readonly MAX_TEST_RETRIES=2

if [[ -z "${TEST_RUNNER_LIB_DIR:-}" ]]; then
  TEST_RUNNER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# ============================================================================
# 내부 모듈 로드
# ============================================================================
if ! declare -f detect_test_framework > /dev/null 2>&1; then
  # shellcheck source=hooks/lib/test-detection.sh
  source "${TEST_RUNNER_LIB_DIR}/test-detection.sh"
fi

if ! declare -f parse_test_output > /dev/null 2>&1; then
  # shellcheck source=hooks/lib/test-results.sh
  source "${TEST_RUNNER_LIB_DIR}/test-results.sh"
fi

# ============================================================================
# 테스트 실행
# Usage: run_tests <project_root> [test_filter] [test_type]
# Returns: JSON with pass/fail/skip counts
# ============================================================================
run_tests() {
  local project_root="${1:-}"
  local test_filter="${2:-}"
  local test_type="${3:-all}"

  local framework
  framework=$(detect_test_framework "$project_root")

  if [[ "$framework" == "none" ]]; then
    echo '{"error": "no_test_framework", "framework": "none", "passed": 0, "failed": 0, "skipped": 0, "total": 0}'
    return 1
  fi

  local results_dir="${project_root}/${TEST_RESULTS_DIR}"
  mkdir -p "$results_dir"

  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)
  local results_file="${results_dir}/${timestamp}.json"

  local test_cmd
  test_cmd=$(get_test_command "$framework" "$project_root" "$test_filter")

  if [[ -z "$test_cmd" ]]; then
    echo '{"error": "unsupported_framework", "framework": "'"$framework"'"}'
    return 1
  fi

  if declare -f log_event &> /dev/null; then
    log_event "$project_root" "INFO" "test_start" "Starting tests" \
      "\"framework\":\"$framework\",\"filter\":\"$test_filter\",\"test_type\":\"$test_type\""
  fi

  local exit_code=0
  if ! timeout "$TEST_TIMEOUT" bash -c "$test_cmd" 2>&1; then
    exit_code=$?
  fi

  local results
  results=$(parse_test_output "$framework" "$project_root" "$exit_code")

  echo "$results" > "$results_file"

  local passed failed total
  passed=$(echo "$results" | jq -r '.passed // 0')
  failed=$(echo "$results" | jq -r '.failed // 0')
  total=$(echo "$results" | jq -r '.total // 0')

  if declare -f log_event &> /dev/null; then
    log_event "$project_root" "INFO" "test_complete" "Tests completed" \
      "\"framework\":\"$framework\",\"passed\":$passed,\"failed\":$failed,\"total\":$total"
  fi

  echo "$results"
}

# ============================================================================
# 커버리지 리포트 생성
# Usage: generate_coverage_report <project_root>
# Returns: JSON with coverage percentage
# ============================================================================
generate_coverage_report() {
  local project_root="${1:-}"
  local framework
  framework=$(detect_test_framework "$project_root")
  local js_package_manager
  local js_runner

  local coverage_file="${project_root}/${TEST_RESULTS_DIR}/coverage.json"

  case "$framework" in
    jest)
      js_package_manager=$(detect_js_package_manager "$project_root")
      js_runner=$(get_js_test_runner_command "$js_package_manager" "jest")
      if (cd "$project_root" && $js_runner --coverage --coverageReporters=json-summary > /dev/null 2>&1); then
        if [[ -f "${project_root}/coverage/coverage-summary.json" ]]; then
          jq '.total.lines.pct' "${project_root}/coverage/coverage-summary.json" > "$coverage_file"
        fi
      fi
      ;;
    vitest)
      js_package_manager=$(detect_js_package_manager "$project_root")
      js_runner=$(get_js_test_runner_command "$js_package_manager" "vitest")
      if (cd "$project_root" && $js_runner run --coverage --coverage.reporter=json > /dev/null 2>&1); then
        if [[ -f "${project_root}/coverage/coverage-final.json" ]]; then
          jq '[.[]?.l] | add / length' "${project_root}/coverage/coverage-final.json" > "$coverage_file" 2> /dev/null || true
        fi
      fi
      ;;
    pytest)
      if (cd "$project_root" && python -m pytest --cov --cov-report=json > /dev/null 2>&1); then
        if [[ -f "${project_root}/coverage.json" ]]; then
          jq '.totals.percent_covered' "${project_root}/coverage.json" > "$coverage_file"
        fi
      fi
      ;;
    go_test)
      if (cd "$project_root" && go test -coverprofile=coverage.out ./... > /dev/null 2>&1); then
        (
          cd "$project_root" \
            && go tool cover -func=coverage.out | tail -1 | awk '{print $3}' | tr -d '%'
        ) > "$coverage_file"
      fi
      ;;
  esac

  if [[ -f "$coverage_file" ]]; then
    cat "$coverage_file"
  else
    echo "0"
  fi
}

# ============================================================================
# 테스트 실패 시 자동 재시도
# Usage: run_tests_with_retry <project_root> [test_filter] [max_retries]
# ============================================================================
run_tests_with_retry() {
  local project_root="${1:-}"
  local test_filter="${2:-}"
  local max_retries="${3:-$MAX_TEST_RETRIES}"

  local attempt=1
  local results=""

  while [[ $attempt -le $max_retries ]]; do
    results=$(run_tests "$project_root" "$test_filter")

    local failed
    failed=$(echo "$results" | jq -r '.failed // 0')

    if [[ "$failed" -eq 0 ]]; then
      echo "$results"
      return 0
    fi

    if declare -f log_event &> /dev/null; then
      log_event "$project_root" "WARN" "test_retry" "Tests failed, retrying" \
        "\"attempt\":$attempt,\"max_retries\":$max_retries,\"failed\":$failed"
    fi

    attempt=$((attempt + 1))
    sleep 2
  done

  echo "$results"
  return 1
}
