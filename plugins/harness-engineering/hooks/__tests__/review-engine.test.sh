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
source "${LIB_DIR}/subagent-spawner.sh"

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
	ORIGINAL_REVIEW_PYTHON_BIN="${HARNESS_REVIEW_PYTHON_BIN-__unset__}"
	ORIGINAL_REVIEW_NORMALIZER_SCRIPT="${HARNESS_REVIEW_NORMALIZER_SCRIPT-__unset__}"
	ORIGINAL_REVIEW_SCORE_SCRIPT="${HARNESS_REVIEW_SCORE_SCRIPT-__unset__}"
	TESTS_RUN=$((TESTS_RUN + 1))
}

teardown() {
	if [[ "$ORIGINAL_REVIEW_PYTHON_BIN" == "__unset__" ]]; then
		unset HARNESS_REVIEW_PYTHON_BIN
	else
		export HARNESS_REVIEW_PYTHON_BIN="$ORIGINAL_REVIEW_PYTHON_BIN"
	fi

	if [[ "$ORIGINAL_REVIEW_NORMALIZER_SCRIPT" == "__unset__" ]]; then
		unset HARNESS_REVIEW_NORMALIZER_SCRIPT
	else
		export HARNESS_REVIEW_NORMALIZER_SCRIPT="$ORIGINAL_REVIEW_NORMALIZER_SCRIPT"
	fi

	if [[ "$ORIGINAL_REVIEW_SCORE_SCRIPT" == "__unset__" ]]; then
		unset HARNESS_REVIEW_SCORE_SCRIPT
	else
		export HARNESS_REVIEW_SCORE_SCRIPT="$ORIGINAL_REVIEW_SCORE_SCRIPT"
	fi

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

test_extract_expected_files() {
	setup

	# design.md 생성
	cat >"${TEST_DIR}/docs/specs/test-feature/design.md" <<'EOF'
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

	if assert_json_value "$result" ".total" "3" "Total should be 3" &&
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

	if assert_json_value "$result" ".found" "1" "Found should be 1" &&
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
	cat >"${TEST_DIR}/docs/specs/test-feature/design.md" <<'EOF'
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

test_check_functional_requirements_requires_real_evidence() {
	setup

	cat >"${TEST_DIR}/docs/specs/test-feature/plan.md" <<'EOF'
# Plan

## 기능 요구사항

- [ ] FR-1.1: `src/auth/login.ts` 파일에 로그인 구현
- [ ] FR-1.2: `login()` API 제공
- [ ] FR-1.3: `tests/auth/login.test.ts` 테스트 추가
EOF

	mkdir -p "${TEST_DIR}/src"
	cat >"${TEST_DIR}/src/random.ts" <<'EOF'
export const noop = () => true;
EOF

	local result
	result=$(check_functional_requirements "$TEST_DIR" "${TEST_DIR}/docs/specs/test-feature/plan.md")

	if assert_json_value "$result" ".total" "3" "Total requirements should be 3" &&
		assert_json_value "$result" ".covered" "0" "Random src file should not cover all FRs" &&
		assert_json_value "$result" ".missing" "3" "All FRs should remain missing"; then
		pass "test_check_functional_requirements_requires_real_evidence"
	else
		fail "test_check_functional_requirements_requires_real_evidence"
	fi

	teardown
}

test_check_functional_requirements_reports_complete_with_tests() {
	setup

	cat >"${TEST_DIR}/docs/specs/test-feature/plan.md" <<'EOF'
# Plan

## 기능 요구사항

- [ ] FR-1.1: `src/auth/login.ts` 파일 생성
- [ ] FR-1.2: `login()` 함수 구현
- [ ] FR-1.3: `tests/auth/login.test.ts` 테스트 추가
EOF

	mkdir -p "${TEST_DIR}/src/auth"
	mkdir -p "${TEST_DIR}/tests/auth"

	cat >"${TEST_DIR}/src/auth/login.ts" <<'EOF'
export function login(username, password) {
  return Boolean(username) && Boolean(password);
}
EOF

	cat >"${TEST_DIR}/tests/auth/login.test.ts" <<'EOF'
import { login } from "../../src/auth/login";

describe("login", () => {
  it("returns true for valid credentials", () => {
    expect(login("user", "pass")).toBe(true);
  });
});
EOF

	local result
	result=$(check_functional_requirements "$TEST_DIR" "${TEST_DIR}/docs/specs/test-feature/plan.md")

	if assert_json_value "$result" ".complete" "3" "All FRs should be complete" &&
		assert_json_value "$result" ".missing" "0" "No FRs should be missing" &&
		assert_json_value "$result" ".details[1].status" "complete" "Function requirement should be complete"; then
		pass "test_check_functional_requirements_reports_complete_with_tests"
	else
		fail "test_check_functional_requirements_reports_complete_with_tests"
	fi

	teardown
}

test_verify_spec_compliance() {
	setup

	# design.md 생성
	cat >"${TEST_DIR}/docs/specs/test-feature/design.md" <<'EOF'
# Design

## 파일 변경

- src/auth/login.ts
- src/auth/logout.ts

## API

function login()
function logout()
EOF

	# plan.md 생성
	cat >"${TEST_DIR}/docs/specs/test-feature/plan.md" <<'EOF'
# Plan

## 기능 요구사항

- [ ] FR-1.1: `src/auth/login.ts` 파일에 로그인 구현
- [ ] FR-1.2: `login()` API 제공
- [ ] FR-1.3: `tests/auth/login.test.ts` 테스트 추가
- [ ] FR-2.1: `src/auth/logout.ts` 파일에 로그아웃 구현
- [ ] FR-2.2: `logout()` API 제공
EOF

	# 일부 파일 생성
	mkdir -p "${TEST_DIR}/src/auth"
	cat >"${TEST_DIR}/src/auth/login.ts" <<'EOF'
export function login() {
  return true;
}
EOF

	local result
	result=$(verify_spec_compliance "$TEST_DIR" "test-feature")

	if assert_json_value "$result" ".feature_slug" "test-feature" "Feature slug should match" &&
		assert_json_value "$result" ".stage" "spec_compliance" "Stage should be spec_compliance" &&
		assert_json_value "$result" ".passed" "false" "Partial evidence should not pass spec compliance" &&
		assert_json_value "$result" ".checks.functional_requirements.complete" "0" "No FR should be fully complete yet"; then
		pass "test_verify_spec_compliance (score: $(echo "$result" | jq -r '.overall_score'))"
	else
		fail "test_verify_spec_compliance"
	fi

	teardown
}

test_verify_spec_compliance_perfect() {
	setup

	# design.md 생성
	cat >"${TEST_DIR}/docs/specs/test-feature/design.md" <<'EOF'
# Design

## 파일 변경

- src/perfect.ts
- tests/perfect.test.ts

## API

function perfectFeature()
EOF

	# plan.md 생성
	cat >"${TEST_DIR}/docs/specs/test-feature/plan.md" <<'EOF'
# Plan

## 기능 요구사항

- [ ] FR-1.1: `src/perfect.ts` 파일 구현
- [ ] FR-1.2: `perfectFeature()` API 제공
- [ ] FR-1.3: `tests/perfect.test.ts` 테스트 추가
EOF

	# 모든 파일 생성
	mkdir -p "${TEST_DIR}/src"
	mkdir -p "${TEST_DIR}/tests"
	cat >"${TEST_DIR}/src/perfect.ts" <<'EOF'
export function perfectFeature() {
  return "done";
}
EOF
	cat >"${TEST_DIR}/tests/perfect.test.ts" <<'EOF'
import { perfectFeature } from "../src/perfect";

describe("perfectFeature", () => {
  it("returns done", () => {
    expect(perfectFeature()).toBe("done");
  });
});
EOF

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

	if assert_json_value "$result" ".stage" "code_quality" "Stage should be code_quality" &&
		assert_json_value "$result" ".status" "pending_execution" "Status should be pending" &&
		assert_json_value "$result" ".overall_score" "null" "Placeholder score should be removed" &&
		assert_file_exists "$(echo "$result" | jq -r '.execution_request_file // empty')" "Execution contract should be written"; then
		pass "test_spawn_subagent_for_review"
	else
		fail "test_spawn_subagent_for_review"
	fi

	teardown
}

test_process_review_result_completed() {
	setup

	mkdir -p "${TEST_DIR}/.harness/subagents"

	local spawn_result
	spawn_result=$(spawn_subagent_for_review "$TEST_DIR" "test-feature" 2>/dev/null)
	local subagent_id
	subagent_id=$(echo "$spawn_result" | jq -r '.subagent_id // empty')

	local review_payload
	review_payload=$(jq -n \
		'{
      overall_score: 0.72,
      summary: "Quality review completed with a few medium issues.",
      scores: {
        solid: 0.8,
        code_quality: 0.7,
        testing: 0.66
      },
      issues: [
        {
          severity: "medium",
          category: "code_quality",
          title: "Long function",
          details: "split handler into smaller units",
          file: "src/review-test.ts"
        }
      ]
    }')

	local result
	result=$(process_review_result "$TEST_DIR" "$subagent_id" "$review_payload")

	local state
	state=$(get_subagent_status "$subagent_id" "$TEST_DIR")

	if assert_json_value "$result" ".status" "completed" "Processed review should complete" &&
		assert_json_value "$result" ".overall_score" "0.72" "Actual score should be preserved" &&
		assert_json_value "$result" ".issues[0].title" "Long function" "Issues should be extracted" &&
		assert_json_value "$state" ".status" "completed" "Subagent should finalize successfully"; then
		pass "test_process_review_result_completed"
	else
		fail "test_process_review_result_completed"
	fi

	teardown
}

test_process_review_result_parse_failure() {
	setup

	mkdir -p "${TEST_DIR}/.harness/subagents"

	local spawn_result
	spawn_result=$(spawn_subagent_for_review "$TEST_DIR" "test-feature" 2>/dev/null)
	local subagent_id
	subagent_id=$(echo "$spawn_result" | jq -r '.subagent_id // empty')

	local result
	result=$(process_review_result "$TEST_DIR" "$subagent_id" "not valid json")

	local state
	state=$(get_subagent_status "$subagent_id" "$TEST_DIR")

	if assert_json_value "$result" ".status" "parse_failed" "Invalid JSON should fail parsing" &&
		assert_json_value "$result" ".failure_reason.code" "parse_failed" "Failure code should be explicit" &&
		assert_json_value "$state" ".status" "failed" "Subagent should finalize as failed"; then
		pass "test_process_review_result_parse_failure"
	else
		fail "test_process_review_result_parse_failure"
	fi

	teardown
}

test_process_review_result_completed_without_python_normalizer() {
	setup

	mkdir -p "${TEST_DIR}/.harness/subagents"
	export HARNESS_REVIEW_NORMALIZER_SCRIPT="${TEST_DIR}/missing_normalizer.py"

	local spawn_result
	spawn_result=$(spawn_subagent_for_review "$TEST_DIR" "test-feature" 2>/dev/null)
	local subagent_id
	subagent_id=$(echo "$spawn_result" | jq -r '.subagent_id // empty')

	local review_payload
	review_payload=$(jq -n \
		'{
      summary: "Fallback normalizer path",
      scores: {
        maintainability: 0.9,
        testing: 0.7
      },
      issues: [
        "Needs more assertions"
      ]
    }')

	local result
	result=$(process_review_result "$TEST_DIR" "$subagent_id" "$review_payload")

	if assert_json_value "$result" ".status" "completed" "Fallback normalizer should still complete" &&
		assert_json_value "$result" ".overall_score" "0.8" "Average score should be preserved" &&
		assert_json_value "$result" ".issues[0].title" "Needs more assertions" "String issues should normalize"; then
		pass "test_process_review_result_completed_without_python_normalizer"
	else
		fail "test_process_review_result_completed_without_python_normalizer"
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

test_calculate_match_rate_without_python_score_helper() {
	setup

	export HARNESS_REVIEW_SCORE_SCRIPT="${TEST_DIR}/missing_score.py"

	local spec_result='{"overall_score": 0.95}'
	local quality_result='{"overall_score": 0.55}'

	local rate
	rate=$(calculate_match_rate "$spec_result" "$quality_result")

	if [[ "${rate:0:4}" == "0.79" ]]; then
		pass "test_calculate_match_rate_without_python_score_helper (rate: $rate)"
	else
		fail "test_calculate_match_rate_without_python_score_helper (rate: $rate, expected ~0.79)"
	fi

	teardown
}

test_run_two_stage_review() {
	setup

	# design.md 생성
	cat >"${TEST_DIR}/docs/specs/test-feature/design.md" <<'EOF'
# Design

## 파일 변경

- src/review-test.ts
EOF

	# plan.md 생성
	cat >"${TEST_DIR}/docs/specs/test-feature/plan.md" <<'EOF'
# Plan

## 기능 요구사항

- FR-1: Test feature
EOF

	# 파일 생성
	mkdir -p "${TEST_DIR}/src"
	touch "${TEST_DIR}/src/review-test.ts"

	# 실제 Stage 2 결과 선행 생성
	mkdir -p "${TEST_DIR}/.harness/subagents"
	local spawn_result
	spawn_result=$(spawn_subagent_for_review "$TEST_DIR" "test-feature" 2>/dev/null)
	local subagent_id
	subagent_id=$(echo "$spawn_result" | jq -r '.subagent_id // empty')
	local review_payload
	review_payload=$(jq -n \
		'{
      overall_score: 0.42,
      summary: "Actual code quality review output",
      issues: [
        {
          severity: "high",
          category: "testing",
          title: "Missing edge-case test",
          details: "logout flow has no regression coverage"
        }
      ]
    }')
	process_review_result "$TEST_DIR" "$subagent_id" "$review_payload" >/dev/null 2>&1

	# 결과 파일 경로 확인
	local result_dir="${TEST_DIR}/${REVIEW_DIR}"
	mkdir -p "$result_dir"

	# 함수 실행 (stdout 캡처)
	run_two_stage_review "$TEST_DIR" "test-feature" >/dev/null 2>&1

	# 저장된 결과 파일에서 읽기
	local result_file
	result_file=$(ls -t "${result_dir}"/two_stage_review_*.json 2>/dev/null | head -1)

	if [[ -f "$result_file" ]]; then
		local feature_slug combined_score quality_status quality_score
		feature_slug=$(jq -r '.feature_slug // empty' "$result_file" 2>/dev/null)
		combined_score=$(jq -r '.overall.combined_score // 0' "$result_file" 2>/dev/null)
		quality_status=$(jq -r '.stage2_code_quality.status // empty' "$result_file" 2>/dev/null)
		quality_score=$(jq -r '.stage2_code_quality.overall_score // 0' "$result_file" 2>/dev/null)

		if [[ "$feature_slug" == "test-feature" ]] && [[ "$combined_score" != "null" ]] && [[ "$quality_status" == "completed" ]] && [[ "$quality_score" == "0.42" ]]; then
			pass "test_run_two_stage_review (score: $combined_score)"
		else
			fail "test_run_two_stage_review (feature_slug: $feature_slug, score: $combined_score, quality_status: $quality_status, quality_score: $quality_score)"
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
	echo '{"test": 1}' >"${TEST_DIR}/${REVIEW_DIR}/new_review.json"

	# 오래된 파일 (타임스탬프 조작)
	echo '{"test": 2}' >"${TEST_DIR}/${REVIEW_DIR}/old_review.json"
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
		cat >"${TEST_DIR}/${REVIEW_DIR}/two_stage_review_${i}.json" <<EOF
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
	test_check_functional_requirements_requires_real_evidence
	test_check_functional_requirements_reports_complete_with_tests
	test_verify_spec_compliance
	test_verify_spec_compliance_perfect
	test_spawn_subagent_for_review
	test_process_review_result_completed
	test_process_review_result_parse_failure
	test_process_review_result_completed_without_python_normalizer
	test_estimate_quality_score
	test_calculate_match_rate
	test_calculate_match_rate_without_python_score_helper
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
