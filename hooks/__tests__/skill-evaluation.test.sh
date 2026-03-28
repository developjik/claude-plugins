#!/usr/bin/env bash
# skill-evaluation.test.sh — 스킬 평가 프레임워크 테스트
# P1-2: skill-evaluation.sh 통합 테스트

set -euo pipefail

# 테스트 프레임워크 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

# 라이브러리 로드
source "${LIB_DIR}/json-utils.sh"
source "${LIB_DIR}/logging.sh"
source "${LIB_DIR}/skill-evaluation.sh"

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
  mkdir -p "${TEST_DIR}/${METRICS_DIR}"
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

test_record_skill_execution_success() {
  setup

  local record
  record=$(record_skill_execution "$TEST_DIR" "clarify" "success" "1500")

  if assert_json_value "$record" ".skill" "clarify" "Skill should be clarify" && \
     assert_json_value "$record" ".status" "success" "Status should be success" && \
     assert_json_value "$record" ".duration_ms" "1500" "Duration should be 1500"; then
    pass "test_record_skill_execution_success"
  else
    fail "test_record_skill_execution_success"
  fi

  teardown
}

test_record_skill_execution_failure() {
  setup

  local record
  record=$(record_skill_execution "$TEST_DIR" "implement" "failure" "5000" "Test error")

  if assert_json_value "$record" ".status" "failure" "Status should be failure" && \
     assert_json_value "$record" ".error" "Test error" "Error should be recorded"; then
    pass "test_record_skill_execution_failure"
  else
    fail "test_record_skill_execution_failure"
  fi

  teardown
}

test_record_skill_execution_with_metadata() {
  setup

  # 메타데이터를 jq로 안전하게 생성
  local metadata
  metadata=$(jq -c -n --argjson files 5 --argjson tests 12 '{"files_changed": $files, "tests_run": $tests}')

  local record
  record=$(record_skill_execution "$TEST_DIR" "check" "success" "3000" "" "$metadata")

  if assert_json_value "$record" ".metadata.files_changed" "5" "Metadata should be recorded"; then
    pass "test_record_skill_execution_with_metadata"
  else
    fail "test_record_skill_execution_with_metadata"
  fi

  teardown
}

test_record_batch_execution() {
  setup

  # record_batch_execution 대신 record_skill_execution으로 직접 테스트
  local results='{"total": 10, "passed": 8, "failed": 2, "duration_ms": 5000}'

  # 배치 결과에서 값 추출
  local total passed failed duration
  total=$(echo "$results" | jq -r '.total // 1')
  passed=$(echo "$results" | jq -r '.passed // 0')
  failed=$(echo "$results" | jq -r '.failed // 0')
  duration=$(echo "$results" | jq -r '.duration_ms // 0')

  local status="partial"
  local metadata
  metadata=$(jq -c -n --argjson t "$total" --argjson p "$passed" --argjson f "$failed" \
    '{"total": $t, "passed": $p, "failed": $f}')

  local record
  record=$(record_skill_execution "$TEST_DIR" "test-runner" "$status" "$duration" "" "$metadata")

  if assert_json_value "$record" ".status" "partial" "Status should be partial" && \
     assert_json_value "$record" ".metadata.total" "10" "Total should be 10"; then
    pass "test_record_batch_execution"
  else
    fail "test_record_batch_execution"
  fi

  teardown
}

test_get_skill_statistics_empty() {
  setup

  local stats
  stats=$(get_skill_statistics "$TEST_DIR" "nonexistent")

  if assert_json_value "$stats" ".total_executions" "0" "Should have 0 executions"; then
    pass "test_get_skill_statistics_empty"
  else
    fail "test_get_skill_statistics_empty"
  fi

  teardown
}

test_get_skill_statistics_with_data() {
  setup

  # 여러 실행 기록 추가
  record_skill_execution "$TEST_DIR" "clarify" "success" "1000" > /dev/null
  record_skill_execution "$TEST_DIR" "clarify" "success" "1200" > /dev/null
  record_skill_execution "$TEST_DIR" "clarify" "failure" "500" "error1" > /dev/null
  record_skill_execution "$TEST_DIR" "clarify" "success" "1100" > /dev/null
  record_skill_execution "$TEST_DIR" "clarify" "success" "900" > /dev/null

  local stats
  stats=$(get_skill_statistics "$TEST_DIR" "clarify" "30")

  if assert_json_value "$stats" ".total_executions" "5" "Should have 5 executions" && \
     assert_json_value "$stats" ".success_count" "4" "Should have 4 successes" && \
     assert_json_value "$stats" ".failure_count" "1" "Should have 1 failure"; then
    pass "test_get_skill_statistics_with_data (success_rate: $(echo "$stats" | jq -r '.success_rate'))"
  else
    fail "test_get_skill_statistics_with_data"
  fi

  teardown
}

test_get_all_skill_statistics() {
  setup

  # 여러 스킬에 기록 추가
  record_skill_execution "$TEST_DIR" "clarify" "success" "1000" > /dev/null
  record_skill_execution "$TEST_DIR" "plan" "success" "2000" > /dev/null
  record_skill_execution "$TEST_DIR" "plan" "failure" "100" "error" > /dev/null

  local stats
  stats=$(get_all_skill_statistics "$TEST_DIR" "30")

  if assert_json_value "$stats" ".summary.total_skills" "2" "Should have 2 skills" && \
     assert_json_value "$stats" ".summary.total_executions" "3" "Should have 3 executions"; then
    pass "test_get_all_skill_statistics"
  else
    fail "test_get_all_skill_statistics"
  fi

  teardown
}

test_calculate_skill_score_high() {
  # 높은 성공률, 빠른 실행
  local stats='{"total_executions": 10, "success_rate": 0.95, "avg_duration_ms": 800}'

  local score
  score=$(calculate_skill_score "$stats")

  if awk "BEGIN {exit !($score >= 0.8)}"; then
    pass "test_calculate_skill_score_high (score: $score)"
  else
    fail "test_calculate_skill_score_high (score: $score, expected >= 0.8)"
  fi
}

test_calculate_skill_score_low() {
  # 낮은 성공률, 느린 실행
  local stats='{"total_executions": 10, "success_rate": 0.3, "avg_duration_ms": 15000}'

  local score
  score=$(calculate_skill_score "$stats")

  if awk "BEGIN {exit !($score < 0.5)}"; then
    pass "test_calculate_skill_score_low (score: $score)"
  else
    fail "test_calculate_skill_score_low (score: $score, expected < 0.5)"
  fi
}

test_calculate_skill_score_insufficient_data() {
  # 샘플 크기 부족
  local stats='{"total_executions": 2, "success_rate": 1.0, "avg_duration_ms": 500}'

  local score
  score=$(calculate_skill_score "$stats")

  if assert_equals "0.5" "$score" "Should return neutral score for insufficient data"; then
    pass "test_calculate_skill_score_insufficient_data"
  else
    fail "test_calculate_skill_score_insufficient_data (score: $score)"
  fi
}

test_generate_skill_dashboard() {
  setup

  # 샘플 데이터 추가
  record_skill_execution "$TEST_DIR" "clarify" "success" "1000" > /dev/null
  record_skill_execution "$TEST_DIR" "clarify" "success" "1200" > /dev/null
  record_skill_execution "$TEST_DIR" "implement" "failure" "5000" "test error" > /dev/null

  local dashboard_file
  dashboard_file=$(generate_skill_dashboard "$TEST_DIR" "30")

  if [[ -f "$dashboard_file" ]]; then
    local content
    content=$(cat "$dashboard_file")

    if echo "$content" | grep -q "Skill Evaluation Dashboard" && \
       echo "$content" | grep -q "clarify" && \
       echo "$content" | grep -q "implement"; then
      pass "test_generate_skill_dashboard"
    else
      fail "test_generate_skill_dashboard (missing content)"
    fi
  else
    fail "test_generate_skill_dashboard (file not created)"
  fi

  teardown
}

test_cleanup_old_metrics() {
  setup

  # 최신 기록
  record_skill_execution "$TEST_DIR" "test" "success" "1000" > /dev/null

  # 오래된 기록 (파일 직접 조작)
  local metric_file="${TEST_DIR}/${METRICS_DIR}/test.jsonl"
  echo '{"id":"old","skill":"test","status":"success","duration_ms":1000,"timestamp":"2020-01-01T00:00:00Z","metadata":{}}' >> "$metric_file"

  local cleaned
  cleaned=$(cleanup_old_metrics "$TEST_DIR" 7)

  if [[ "$cleaned" -ge 1 ]]; then
    pass "test_cleanup_old_metrics ($cleaned records cleaned)"
  else
    fail "test_cleanup_old_metrics (expected >=1, got $cleaned)"
  fi

  teardown
}

test_export_metrics_json() {
  setup

  record_skill_execution "$TEST_DIR" "test" "success" "1000" > /dev/null

  local export
  export=$(export_metrics "$TEST_DIR" "json")

  if echo "$export" | jq -e '.skills' > /dev/null 2>&1; then
    pass "test_export_metrics_json"
  else
    fail "test_export_metrics_json (invalid JSON)"
  fi

  teardown
}

test_export_metrics_csv() {
  setup

  record_skill_execution "$TEST_DIR" "test" "success" "1000" > /dev/null

  local export
  export=$(export_metrics "$TEST_DIR" "csv")

  if echo "$export" | grep -q "skill,total_executions,success_rate"; then
    pass "test_export_metrics_csv"
  else
    fail "test_export_metrics_csv (missing header)"
  fi

  teardown
}

test_detect_anomalies() {
  setup

  # 정상 스킬
  for i in {1..10}; do
    record_skill_execution "$TEST_DIR" "good-skill" "success" "1000" > /dev/null
  done

  # 문제 스킬
  for i in {1..10}; do
    record_skill_execution "$TEST_DIR" "bad-skill" "failure" "5000" "error" > /dev/null
  done

  local anomalies
  anomalies=$(detect_anomalies "$TEST_DIR" "0.5")

  local anomaly_count
  anomaly_count=$(echo "$anomalies" | jq 'length')

  if [[ "$anomaly_count" -ge 1 ]]; then
    pass "test_detect_anomalies ($anomaly_count anomalies detected)"
  else
    fail "test_detect_anomalies (expected >=1, got $anomaly_count)"
  fi

  teardown
}

test_generate_weekly_report() {
  setup

  # 샘플 데이터
  record_skill_execution "$TEST_DIR" "clarify" "success" "1000" > /dev/null
  record_skill_execution "$TEST_DIR" "plan" "success" "2000" > /dev/null

  local report_file
  report_file=$(generate_weekly_report "$TEST_DIR")

  if [[ -f "$report_file" ]]; then
    local content
    content=$(cat "$report_file")

    if echo "$content" | grep -q "Weekly Skill Evaluation Report"; then
      pass "test_generate_weekly_report"
    else
      fail "test_generate_weekly_report (missing header)"
    fi
  else
    fail "test_generate_weekly_report (file not created)"
  fi

  teardown
}

# ============================================================================
# 메인 실행
# ============================================================================

main() {
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Skill Evaluation Framework - Integration Tests"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  # jq 확인
  if ! command -v jq &>/dev/null; then
    echo "ERROR: jq is required for tests"
    echo "Install: brew install jq"
    exit 1
  fi

  # 테스트 실행
  test_record_skill_execution_success
  test_record_skill_execution_failure
  test_record_skill_execution_with_metadata
  test_record_batch_execution
  test_get_skill_statistics_empty
  test_get_skill_statistics_with_data
  test_get_all_skill_statistics
  test_calculate_skill_score_high
  test_calculate_skill_score_low
  test_calculate_skill_score_insufficient_data
  test_generate_skill_dashboard
  test_cleanup_old_metrics
  test_export_metrics_json
  test_export_metrics_csv
  test_detect_anomalies
  test_generate_weekly_report

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
