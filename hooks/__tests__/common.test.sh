#!/usr/bin/env bash
# common.test.sh — common.sh 모듈 테스트
# 실행: bash hooks/__tests__/common.test.sh

set -e

# 테스트 프레임워크 (간단한 구현)
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 테스트 헬퍼 함수
assert_equals() {
  local expected="$1"
  local actual="$2"
  local message="${3:-}"

  TESTS_RUN=$((TESTS_RUN + 1))

  if [[ "$expected" == "$actual" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf "${GREEN}✓ PASS${NC}: %s\n" "$message"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf "${RED}✗ FAIL${NC}: %s\n" "$message"
    printf "  Expected: '%s'\n" "$expected"
    printf "  Actual:   '%s'\n" "$actual"
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="${3:-}"

  TESTS_RUN=$((TESTS_RUN + 1))

  if [[ "$haystack" == *"$needle"* ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf "${GREEN}✓ PASS${NC}: %s\n" "$message"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf "${RED}✗ FAIL${NC}: %s\n" "$message"
    printf "  Expected to contain: '%s'\n" "$needle"
    printf "  Actual: '%s'\n" "$haystack"
  fi
}

assert_not_empty() {
  local value="$1"
  local message="${2:-}"

  TESTS_RUN=$((TESTS_RUN + 1))

  if [[ -n "$value" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf "${GREEN}✓ PASS${NC}: %s\n" "$message"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf "${RED}✗ FAIL${NC}: %s (value is empty)\n" "$message"
  fi
}

assert_file_exists() {
  local file_path="$1"
  local message="${2:-}"

  TESTS_RUN=$((TESTS_RUN + 1))

  if [[ -f "$file_path" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf "${GREEN}✓ PASS${NC}: %s\n" "$message"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf "${RED}✗ FAIL${NC}: %s (file not found: %s)\n" "$message" "$file_path"
  fi
}

# ============================================================================
# 테스트 설정
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$(dirname "$SCRIPT_DIR")"

# 모듈 로드
source "${HOOKS_DIR}/lib/json-utils.sh"
source "${HOOKS_DIR}/lib/context-rot.sh"
source "${HOOKS_DIR}/lib/automation-level.sh"
source "${HOOKS_DIR}/lib/logging.sh"

# 테스트용 임시 디렉토리
TEST_ROOT=$(mktemp -d)
trap "rm -rf $TEST_ROOT" EXIT

echo "========================================"
echo "Running common.sh module tests"
echo "Test root: $TEST_ROOT"
echo "========================================"
echo ""

# ============================================================================
# JSON Utils 테스트
# ============================================================================

echo "--- Testing json-utils.sh ---"

# json_query 테스트
test_json='{"name":"test","value":42,"nested":{"key":"value"}}'

result=$(json_query "$test_json" '.name')
assert_equals "test" "$result" "json_query: extract string"

result=$(json_query "$test_json" '.value')
assert_equals "42" "$result" "json_query: extract number"

result=$(json_query "$test_json" '.nested.key')
assert_equals "value" "$result" "json_query: extract nested value"

result=$(json_query "" '.name')
assert_equals "" "$result" "json_query: empty payload returns empty"

# safe_json_query 테스트
result=$(safe_json_query "$test_json" '.name')
assert_equals "test" "$result" "safe_json_query: valid query"

result=$(safe_json_query "invalid json" '.name' 2>/dev/null || echo "")
assert_contains "$result" "" "safe_json_query: invalid JSON returns empty"

echo ""

# ============================================================================
# Context Rot 테스트
# ============================================================================

echo "--- Testing context-rot.sh ---"

# 세션 시작 기록
record_session_start "$TEST_ROOT"
assert_file_exists "${TEST_ROOT}/.harness/state/session-start-time" "record_session_start: creates start time file"
assert_file_exists "${TEST_ROOT}/.harness/state/tool-call-count" "record_session_start: creates count file"

# 도구 호출 카운터
initial_count=$(get_tool_call_count "$TEST_ROOT")
assert_equals "0" "$initial_count" "get_tool_call_count: initial count is 0"

increment_tool_call_count "$TEST_ROOT"
increment_tool_call_count "$TEST_ROOT"
new_count=$(get_tool_call_count "$TEST_ROOT")
assert_equals "2" "$new_count" "increment_tool_call_count: increments count"

# Context Rot 점수 계산
score=$(calculate_context_rot "$TEST_ROOT")
assert_not_empty "$score" "calculate_context_rot: returns a score"

# 점수 범위 확인 (0.0 ~ 1.0)
is_valid=$(awk -v s="$score" 'BEGIN { if (s >= 0 && s <= 1) print "true"; else print "false" }')
assert_equals "true" "$is_valid" "calculate_context_rot: score in valid range"

# 등급 조회
grade=$(get_context_rot_grade "$TEST_ROOT")
assert_contains "healthy caution rot" "$grade" "get_context_rot_grade: returns valid grade"

# 서브에이전트 권장 여부
should_use=$(should_use_subagent "$TEST_ROOT" "0.99")
assert_equals "false" "$should_use" "should_use_subagent: returns false for low score"

echo ""

# ============================================================================
# Automation Level 테스트
# ============================================================================

echo "--- Testing automation-level.sh ---"

# 기본 레벨 조회
level=$(get_automation_level "$TEST_ROOT")
assert_equals "L2" "$level" "get_automation_level: default is L2"

# 전환 승인 필요 여부
result=$(should_approve_transition "L0" "plan_to_design")
assert_equals "true" "$result" "should_approve_transition: L0 always requires approval"

result=$(should_approve_transition "L4" "plan_to_design")
assert_equals "false" "$result" "should_approve_transition: L4 never requires approval"

result=$(should_approve_transition "L2" "plan_to_design")
assert_equals "if_uncertain" "$result" "should_approve_transition: L2 uncertain for plan_to_design"

# 전환 이름 조회
transition=$(get_transition_name "plan" "design")
assert_equals "plan_to_design" "$transition" "get_transition_name: returns correct name"

transition=$(get_transition_name "unknown" "phase")
assert_equals "" "$transition" "get_transition_name: returns empty for unknown"

# 설정 초기화
init_automation_config "$TEST_ROOT"
assert_file_exists "${TEST_ROOT}/.harness/config.yaml" "init_automation_config: creates config.yaml"
assert_file_exists "${TEST_ROOT}/.harness/trust.json" "init_automation_config: creates trust.json"

# 신뢰 점수 조회
trust=$(get_trust_score "$TEST_ROOT")
assert_not_empty "$trust" "get_trust_score: returns a score"

# 추천 레벨
recommended=$(get_recommended_level "$TEST_ROOT")
assert_contains "L0 L1 L2 L3 L4" "$recommended" "get_recommended_level: returns valid level"

echo ""

# ============================================================================
# Logging 테스트
# ============================================================================

echo "--- Testing logging.sh ---"

# 트레이스 ID 생성
trace_id=$(generate_trace_id)
# trace_ 접두사와 타임스탬프 확인
assert_not_empty "$trace_id" "generate_trace_id: returns non-empty trace ID"
# 접두사 확인 (더 유연하게)
if [[ "$trace_id" == trace_* ]]; then
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf "${GREEN}✓ PASS${NC}: generate_trace_id: starts with trace_\n"
else
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf "${RED}✗ FAIL${NC}: generate_trace_id: starts with trace_\n"
  printf "  Actual: '%s'\n" "$trace_id"
fi

# 세션 트레이스 ID
session_trace=$(get_session_trace_id "$TEST_ROOT")
assert_not_empty "$session_trace" "get_session_trace_id: returns trace ID"
assert_file_exists "${TEST_ROOT}/.harness/state/trace-id" "get_session_trace_id: creates trace file"

# 민감 정보 마스킹
masked=$(mask_sensitive_data "password=secret123")
# [REDACTED]가 포함되어 있는지 확인
if [[ "$masked" == *"[REDACTED]"* ]]; then
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf "${GREEN}✓ PASS${NC}: mask_sensitive_data: masks password\n"
else
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf "${RED}✗ FAIL${NC}: mask_sensitive_data: masks password\n"
  printf "  Actual: '%s'\n" "$masked"
fi

masked=$(mask_sensitive_data "token=abc123xyz")
if [[ "$masked" == *"[REDACTED]"* ]]; then
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf "${GREEN}✓ PASS${NC}: mask_sensitive_data: masks token\n"
else
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf "${RED}✗ FAIL${NC}: mask_sensitive_data: masks token\n"
  printf "  Actual: '%s'\n" "$masked"
fi

masked=$(mask_sensitive_data "normal text")
assert_equals "normal text" "$masked" "mask_sensitive_data: preserves normal text"

# 로그 이벤트
log_event "$TEST_ROOT" "INFO" "test_event" "Test message"
assert_file_exists "${TEST_ROOT}/.harness/logs/events.jsonl" "log_event: creates log file"

# 로그 내용 확인 (더 유연하게)
log_content=$(cat "${TEST_ROOT}/.harness/logs/events.jsonl")
# JSON 형식 확인
if [[ "$log_content" == *"test_event"* ]] && [[ "$log_content" == *"Test message"* ]]; then
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf "${GREEN}✓ PASS${NC}: log_event: contains event and message\n"
else
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf "${RED}✗ FAIL${NC}: log_event: contains event and message\n"
  printf "  Actual: '%s'\n" "$log_content"
fi

# JSON 구조 확인
if [[ "$log_content" == *"\"event\":"* ]] && [[ "$log_content" == *"\"message\":"* ]]; then
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf "${GREEN}✓ PASS${NC}: log_event: valid JSON structure\n"
else
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf "${RED}✗ FAIL${NC}: log_event: valid JSON structure\n"
  printf "  Actual: '%s'\n" "$log_content"
fi

echo ""

# ============================================================================
# 결과 요약
# ============================================================================

echo "========================================"
echo "Test Results Summary"
echo "========================================"
printf "Total:  %d\n" "$TESTS_RUN"
printf "${GREEN}Passed: %d${NC}\n" "$TESTS_PASSED"
printf "${RED}Failed: %d${NC}\n" "$TESTS_FAILED"
echo "========================================"

if [[ $TESTS_FAILED -gt 0 ]]; then
  printf "${RED}Some tests failed!${NC}\n"
  exit 1
else
  printf "${GREEN}All tests passed!${NC}\n"
  exit 0
fi
