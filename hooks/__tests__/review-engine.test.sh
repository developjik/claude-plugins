#!/usr/bin/env bash
# review-engine.test.sh — 2단계 리뷰 시스템 테스트
# P1-1: review-engine.sh 통합 테스트

set -euo pipefail

# 테스트 프레임워크 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

# 라이브러리 로드
source "${LIB_DIR}/json-utils.sh"
source "${LIB_DIR}/logging.sh"
source "${LIB_DIR}/review-engine.sh"

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
  mkdir -p "${TEST_DIR}/docs/specs/test-feature"
  mkdir -p "${TEST_DIR}/src"
  mkdir -p "${TEST_DIR}/tests"
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

assert_json_contains() {
  local json="${1:-}"
  local path="${2:-}"
  local expected="${3:-}"
  local message="${4:-}"

  local actual
  actual=$(echo "$json" | jq -r "$path" 2>/dev/null)

  if [[ "$actual" == *"$expected"* ]]; then
    return 0
  else
    echo -e "${RED}✗ Assertion failed: $message${NC}"
    echo "  Path: $path"
    echo "  Expected to contain: $expected"
    echo "  Actual: $actual"
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

test_extract_expected_files() {
  setup

  # design.md 생성
  cat > "${TEST_DIR}/docs/specs/test-feature/design.md" << 'EOF'
# Design

## 파일 변경

- src/auth/login.ts
- src/auth/logout.ts
- src/middleware/auth.ts
- `tests/auth.test.ts`

## API

function login(username, password)
function logout()
EOF

  local files
  files=$(extract_expected_files "${TEST_DIR}/docs/specs/test-feature/design.md")

  local count
  count=$(echo "$files" | jq 'length')

  if [[ "$count" -ge 3 ]]; then
    pass "test_extract_expected_files ($count files found)"
  else
    fail "test_extract_expected_files (expected >=3, got $count)"
  fi

  teardown
}

test_check_file_existence_all_found() {
  setup

  # 파일 생성
  mkdir -p "${TEST_DIR}/src/auth"
  touch "${TEST_DIR}/src/auth/login.ts"
  touch "${TEST_DIR}/src/auth/logout.ts"

  local expected='["src/auth/login.ts", "src/auth/logout.ts", "src/auth/missing.ts"]'
  local result
  result=$(check_file_existence "$TEST_DIR" "$expected")

  if assert_json_value "$result" ".total" "3" "Total should be 3" && \
     assert_json_value "$result" ".found" "2" "Found should be 2"; then
    pass "test_check_file_existence_all_found"
  else
    fail "test_check_file_existence_all_found"
  fi

  teardown
}

test_check_file_existence_partial() {
  setup

  # 일부 파일만 생성
  mkdir -p "${TEST_DIR}/src"
  touch "${TEST_DIR}/src/exists.ts"

  local expected='["src/exists.ts", "src/missing1.ts", "src/missing2.ts"]'
  local result
  result=$(check_file_existence "$TEST_DIR" "$expected")

  if assert_json_value "$result" ".found" "1" "Found should be 1" && \
     assert_json_value "$result" ".missing | length" "2" "Missing should be 2"; then
    pass "test_check_file_existence_partial"
  else
    fail "test_check_file_existence_partial"
  fi

  teardown
}

test_extract_api_signatures() {
  setup

  # design.md 생성
  cat > "${TEST_DIR}/docs/specs/test-feature/design.md" << 'EOF'
# API

## Functions

function authenticate(user, pass) - Authenticates user
function validateToken(token) - Validates JWT token
const createSession = (userId) => Session
EOF

  local apis
  apis=$(extract_api_signatures "${TEST_DIR}/docs/specs/test-feature/design.md")

  local count
  count=$(echo "$apis" | jq 'length')

  if [[ "$count" -ge 1 ]]; then
    pass "test_extract_api_signatures ($count APIs found)"
  else
    fail "test_extract_api_signatures (expected >=1, got $count)"
  fi

  teardown
}

test_verify_spec_compliance() {
  setup

  # design.md 생성
  cat > "${TEST_DIR}/docs/specs/test-feature/design.md" << 'EOF'
# Design

## 파일 변경

- src/auth/login.ts
- src/auth/logout.ts

## API

function login()
function logout()
EOF

  # plan.md 생성
  cat > "${TEST_DIR}/docs/specs/test-feature/plan.md" << 'EOF'
# Plan

## 기능 요구사항

- FR-1: User can login
- FR-2: User can logout
EOF

  # 일부 파일 생성
  mkdir -p "${TEST_DIR}/src/auth"
  touch "${TEST_DIR}/src/auth/login.ts"

  local result
  result=$(verify_spec_compliance "$TEST_DIR" "test-feature")

  if assert_json_value "$result" ".feature_slug" "test-feature" "Feature slug should match" && \
     assert_json_value "$result" ".stage" "spec_compliance" "Stage should be spec_compliance"; then
    pass "test_verify_spec_compliance (score: $(echo "$result" | jq -r '.overall_score'))"
  else
    fail "test_verify_spec_compliance"
  fi

  teardown
}

test_verify_spec_compliance_perfect() {
  setup

  # design.md 생성
  cat > "${TEST_DIR}/docs/specs/test-feature/design.md" << 'EOF'
# Design

## 파일 변경

- src/perfect.ts
EOF

  # 모든 파일 생성
  mkdir -p "${TEST_DIR}/src"
  touch "${TEST_DIR}/src/perfect.ts"

  local result
  result=$(verify_spec_compliance "$TEST_DIR" "test-feature")

  local score
  score=$(echo "$result" | jq -r '.overall_score')

  if awk "BEGIN {exit !($score >= 0.9)}"; then
    pass "test_verify_spec_compliance_perfect (score: $score)"
  else
    fail "test_verify_spec_compliance_perfect (score: $score, expected >= 0.9)"
  fi

  teardown
}

test_spawn_subagent_for_review() {
  setup

  # 필요한 디렉토리 생성
  mkdir -p "${TEST_DIR}/.harness/subagents"

  local result
  result=$(spawn_subagent_for_review "$TEST_DIR" "test-feature" 2>/dev/null)

  if assert_json_value "$result" ".stage" "code_quality" "Stage should be code_quality" && \
     assert_json_value "$result" ".status" "pending_execution" "Status should be pending"; then
    pass "test_spawn_subagent_for_review"
  else
    fail "test_spawn_subagent_for_review"
  fi

  teardown
}

test_estimate_quality_score() {
  setup

  # 소스 파일 생성
  mkdir -p "${TEST_DIR}/src"
  touch "${TEST_DIR}/src/main.ts"
  touch "${TEST_DIR}/src/utils.ts"

  # 테스트 파일 생성
  touch "${TEST_DIR}/main.test.ts"
  touch "${TEST_DIR}/utils.test.ts"

  local score
  score=$(estimate_quality_score "$TEST_DIR")

  # 점수가 0-1 사이인지 확인
  if awk "BEGIN {exit !($score >= 0 && $score <= 1)}"; then
    pass "test_estimate_quality_score (score: $score)"
  else
    fail "test_estimate_quality_score (score: $score, expected 0-1)"
  fi

  teardown
}

test_calculate_match_rate() {
  setup

  local spec_result='{"overall_score": 0.9}'
  local quality_result='{"overall_score": 0.8}'

  local rate
  rate=$(calculate_match_rate "$spec_result" "$quality_result")

  # 0.9 * 0.6 + 0.8 * 0.4 = 0.54 + 0.32 = 0.86
  local expected="0.86"

  if [[ "${rate:0:4}" == "${expected:0:4}" ]]; then
    pass "test_calculate_match_rate (rate: $rate)"
  else
    fail "test_calculate_match_rate (rate: $rate, expected ~$expected)"
  fi

  teardown
}

test_run_two_stage_review() {
  setup

  # design.md 생성
  cat > "${TEST_DIR}/docs/specs/test-feature/design.md" << 'EOF'
# Design

## 파일 변경

- src/review-test.ts
EOF

  # plan.md 생성
  cat > "${TEST_DIR}/docs/specs/test-feature/plan.md" << 'EOF'
# Plan

## 기능 요구사항

- FR-1: Test feature
EOF

  # 파일 생성
  mkdir -p "${TEST_DIR}/src"
  touch "${TEST_DIR}/src/review-test.ts"

  # 결과 파일 경로 확인
  local result_dir="${TEST_DIR}/${REVIEW_DIR}"
  mkdir -p "$result_dir"

  # 함수 실행 (stdout 캡처)
  run_two_stage_review "$TEST_DIR" "test-feature" "--skip-quality" >/dev/null 2>&1

  # 저장된 결과 파일에서 읽기
  local result_file
  result_file=$(ls -t "${result_dir}"/two_stage_review_*.json 2>/dev/null | head -1)

  if [[ -f "$result_file" ]]; then
    local feature_slug combined_score
    feature_slug=$(jq -r '.feature_slug // empty' "$result_file" 2>/dev/null)
    combined_score=$(jq -r '.overall.combined_score // 0' "$result_file" 2>/dev/null)

    if [[ "$feature_slug" == "test-feature" ]] && [[ "$combined_score" != "null" ]]; then
      pass "test_run_two_stage_review (score: $combined_score)"
    else
      fail "test_run_two_stage_review (feature_slug: $feature_slug, score: $combined_score)"
    fi
  else
    fail "test_run_two_stage_review (no result file)"
  fi

  teardown
}

test_cleanup_old_reviews() {
  setup

  mkdir -p "${TEST_DIR}/${REVIEW_DIR}"

  # 최신 파일
  echo '{"test": 1}' > "${TEST_DIR}/${REVIEW_DIR}/new_review.json"

  # 오래된 파일 (타임스탬프 조작)
  echo '{"test": 2}' > "${TEST_DIR}/${REVIEW_DIR}/old_review.json"
  touch -t 202001010000 "${TEST_DIR}/${REVIEW_DIR}/old_review.json"

  local cleaned
  cleaned=$(cleanup_old_reviews "$TEST_DIR" 30)

  if [[ "$cleaned" -ge 1 ]]; then
    pass "test_cleanup_old_reviews ($cleaned files cleaned)"
  else
    fail "test_cleanup_old_reviews (expected >=1, got $cleaned)"
  fi

  teardown
}

test_get_review_history() {
  setup

  mkdir -p "${TEST_DIR}/${REVIEW_DIR}"

  # 리뷰 결과 파일 생성
  for i in 1 2 3; do
    cat > "${TEST_DIR}/${REVIEW_DIR}/two_stage_review_${i}.json" << EOF
{
  "timestamp": "2026032${i}_120000",
  "feature_slug": "feature-${i}",
  "overall": {
    "passed": true,
    "combined_score": 0.9${i}
  }
}
EOF
  done

  local history
  history=$(get_review_history "$TEST_DIR" 10)

  local count
  count=$(echo "$history" | jq 'length')

  if [[ "$count" -ge 3 ]]; then
    pass "test_get_review_history ($count reviews)"
  else
    fail "test_get_review_history (expected >=3, got $count)"
  fi

  teardown
}

# ============================================================================
# 메인 실행
# ============================================================================

main() {
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Two-Stage Review Engine - Integration Tests"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  # jq 확인
  if ! command -v jq &>/dev/null; then
    echo "ERROR: jq is required for tests"
    echo "Install: brew install jq"
    exit 1
  fi

  # 테스트 실행
  test_extract_expected_files
  test_check_file_existence_all_found
  test_check_file_existence_partial
  test_extract_api_signatures
  test_verify_spec_compliance
  test_verify_spec_compliance_perfect
  test_spawn_subagent_for_review
  test_estimate_quality_score
  test_calculate_match_rate
  test_run_two_stage_review
  test_cleanup_old_reviews
  test_get_review_history

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
