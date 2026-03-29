#!/usr/bin/env bash
# subagent.test.sh — 서브에이전트 시스템 통합 테스트
# P0-2: 실제 서브에이전트 스포닝

set -euo pipefail

# 테스트 프레임워크 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

# 라이브러리 로드
source "${LIB_DIR}/json-utils.sh"
source "${LIB_DIR}/logging.sh"
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
  mkdir -p "${TEST_DIR}/.harness/logs"
  mkdir -p "${TEST_DIR}/.harness/subagents"
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

test_spawn_subagent_creates_directory() {
  setup

  # 태스크 파일 생성
  local task_file="${TEST_DIR}/task.md"
  echo "# Test Task\n\nImplement user authentication." > "$task_file"

  # 서브에이전트 스폰
  local subagent_id
  subagent_id=$(spawn_subagent "$task_file" "$TEST_DIR" "sonnet" "task_execution")

  # 검증
  local subagent_dir="${TEST_DIR}/.harness/subagents/${subagent_id}"

  if assert_file_exists "${subagent_dir}/state.json" "State file should exist" && \
     assert_file_exists "${subagent_dir}/task.md" "Task file should be copied" && \
     assert_file_exists "${subagent_dir}/context.md" "Context file should exist"; then
    pass "test_spawn_subagent_creates_directory"
  else
    fail "test_spawn_subagent_creates_directory"
  fi

  teardown
}

test_spawn_subagent_id_format() {
  setup

  local task_file="${TEST_DIR}/task.md"
  echo "# Task" > "$task_file"

  local subagent_id
  subagent_id=$(spawn_subagent "$task_file" "$TEST_DIR" "sonnet")

  # ID 형식 검증: subagent_<timestamp>_<random>
  if [[ "$subagent_id" =~ ^subagent_[0-9]+_[a-z0-9]+$ ]]; then
    pass "test_spawn_subagent_id_format"
  else
    fail "test_spawn_subagent_id_format (got: $subagent_id)"
  fi

  teardown
}

test_spawn_subagent_state_json() {
  setup

  local task_file="${TEST_DIR}/task.md"
  echo "# Task" > "$task_file"

  local subagent_id
  subagent_id=$(spawn_subagent "$task_file" "$TEST_DIR" "opus" "code_review")

  local state_file="${TEST_DIR}/.harness/subagents/${subagent_id}/state.json"
  local state
  state=$(cat "$state_file")

  if assert_json_value "$state" ".status" "pending" "Status should be pending" && \
     assert_json_value "$state" ".model" "claude-opus-4-6" "Model should be opus" && \
     assert_json_value "$state" ".purpose" "code_review" "Purpose should match"; then
    pass "test_spawn_subagent_state_json"
  else
    fail "test_spawn_subagent_state_json"
  fi

  teardown
}

test_prepare_subagent_context() {
  setup

  # PROJECT.md 생성
  cat > "${TEST_DIR}/PROJECT.md" << 'EOF'
# Test Project

This is a test project for subagent testing.

## Stack
- TypeScript
- Node.js
- Jest
EOF

  local subagent_dir="${TEST_DIR}/.harness/subagents/test_context"
  mkdir -p "$subagent_dir"

  # 컨텍스트 준비
  prepare_subagent_context "$TEST_DIR" "$subagent_dir" "task_execution"

  local context_file="${subagent_dir}/context.md"

  if assert_file_exists "$context_file" "Context file should exist"; then
    local context
    context=$(cat "$context_file")

    if assert_contains "Test Project" "$context" "Should contain project info" && \
       assert_contains "Purpose" "$context" "Should contain purpose section" && \
       assert_contains "Output" "$context" "Should contain output instructions"; then
      pass "test_prepare_subagent_context"
    else
      fail "test_prepare_subagent_context"
    fi
  else
    fail "test_prepare_subagent_context"
  fi

  teardown
}

test_get_subagent_status() {
  setup

  local task_file="${TEST_DIR}/task.md"
  echo "# Task" > "$task_file"

  local subagent_id
  subagent_id=$(spawn_subagent "$task_file" "$TEST_DIR" "haiku")

  local status
  status=$(get_subagent_status "$subagent_id" "$TEST_DIR")

  if assert_json_value "$status" ".status" "pending" "Initial status should be pending" && \
     assert_json_value "$status" ".model_short" "haiku" "Model should be haiku"; then
    pass "test_get_subagent_status"
  else
    fail "test_get_subagent_status"
  fi

  teardown
}

test_start_subagent_execution() {
  setup

  local task_file="${TEST_DIR}/task.md"
  echo "# Task" > "$task_file"

  local subagent_id
  subagent_id=$(spawn_subagent "$task_file" "$TEST_DIR" "sonnet")

  # 실행 시작
  start_subagent_execution "$subagent_id" "$TEST_DIR"

  local status
  status=$(get_subagent_status "$subagent_id" "$TEST_DIR")

  local started_at
  started_at=$(echo "$status" | jq -r '.started_at // "null"')

  if assert_json_value "$status" ".status" "running" "Status should be running" && \
     [[ "$started_at" != "null" ]]; then
    pass "test_start_subagent_execution"
  else
    fail "test_start_subagent_execution (started_at=$started_at)"
  fi

  teardown
}

test_complete_subagent() {
  setup

  local task_file="${TEST_DIR}/task.md"
  echo "# Task" > "$task_file"

  local subagent_id
  subagent_id=$(spawn_subagent "$task_file" "$TEST_DIR" "sonnet")

  # 실행 시작
  start_subagent_execution "$subagent_id" "$TEST_DIR"

  # 완료 처리
  complete_subagent "$subagent_id" "$TEST_DIR" "completed"

  local status
  status=$(get_subagent_status "$subagent_id" "$TEST_DIR")

  local duration_ms
  duration_ms=$(echo "$status" | jq -r '.duration_ms // "null"')

  if assert_json_value "$status" ".status" "completed" "Status should be completed" && \
     [[ "$duration_ms" != "null" ]]; then
    pass "test_complete_subagent"
  else
    fail "test_complete_subagent (duration_ms=$duration_ms)"
  fi

  teardown
}

test_list_active_subagents() {
  setup

  # 여러 서브에이전트 생성
  local task_file="${TEST_DIR}/task.md"
  echo "# Task" > "$task_file"

  local id1 id2 id3
  id1=$(spawn_subagent "$task_file" "$TEST_DIR" "sonnet")
  id2=$(spawn_subagent "$task_file" "$TEST_DIR" "sonnet")
  id3=$(spawn_subagent "$task_file" "$TEST_DIR" "sonnet")

  # 하나는 완료 처리
  start_subagent_execution "$id2" "$TEST_DIR"
  complete_subagent "$id2" "$TEST_DIR" "completed"

  # 활성 목록 조회
  local active
  active=$(list_active_subagents "$TEST_DIR")

  local active_count
  active_count=$(echo "$active" | jq 'length')

  # id1, id3이 활성 (id2는 완료)
  if [[ "$active_count" -eq 2 ]]; then
    pass "test_list_active_subagents"
  else
    fail "test_list_active_subagents (expected 2, got $active_count)"
  fi

  teardown
}

test_aggregate_subagent_results() {
  setup

  local task_file="${TEST_DIR}/task.md"
  echo "# Task" > "$task_file"

  # 서브에이전트 2개 생성 및 완료
  local id1 id2
  id1=$(spawn_subagent "$task_file" "$TEST_DIR" "sonnet")
  id2=$(spawn_subagent "$task_file" "$TEST_DIR" "haiku")

  start_subagent_execution "$id1" "$TEST_DIR"
  complete_subagent "$id1" "$TEST_DIR" "completed"

  start_subagent_execution "$id2" "$TEST_DIR"
  complete_subagent "$id2" "$TEST_DIR" "failed"

  # 결과 집계
  local results
  results=$(aggregate_subagent_results "$TEST_DIR" "${id1},${id2}")

  if assert_json_value "$results" ".summary.total" "2" "Total should be 2" && \
     assert_json_value "$results" ".summary.completed" "1" "Completed should be 1" && \
     assert_json_value "$results" ".summary.failed" "1" "Failed should be 1"; then
    pass "test_aggregate_subagent_results"
  else
    fail "test_aggregate_subagent_results"
  fi

  teardown
}

test_wait_for_subagents() {
  setup

  local task_file="${TEST_DIR}/task.md"
  echo "# Task" > "$task_file"

  local id1 id2
  id1=$(spawn_subagent "$task_file" "$TEST_DIR" "sonnet")
  id2=$(spawn_subagent "$task_file" "$TEST_DIR" "haiku")

  start_subagent_execution "$id1" "$TEST_DIR"
  complete_subagent "$id1" "$TEST_DIR" "completed"

  start_subagent_execution "$id2" "$TEST_DIR"
  complete_subagent "$id2" "$TEST_DIR" "failed"

  local results
  results=$(wait_for_subagents "$TEST_DIR" "${id1},${id2}" 1)

  if assert_json_value "$results" ".status" "partial_failure" "Overall status should reflect failures" && \
     assert_json_value "$results" ".summary.total" "2" "Total should be 2" && \
     assert_json_value "$results" ".summary.completed" "1" "Completed should be 1" && \
     assert_json_value "$results" ".summary.failed" "1" "Failed should be 1" && \
     assert_json_value "$results" ".summary.running" "0" "Running should be 0" && \
     assert_json_value "$results" ".summary.pending" "0" "Pending should be 0"; then
    pass "test_wait_for_subagents"
  else
    fail "test_wait_for_subagents"
  fi

  teardown
}

test_generate_agent_params() {
  setup

  local task_file="${TEST_DIR}/task.md"
  echo "# Task\n\nImplement feature X." > "$task_file"

  local subagent_id
  subagent_id=$(spawn_subagent "$task_file" "$TEST_DIR" "sonnet")

  # Agent 파라미터 생성
  local params
  params=$(generate_agent_params "$subagent_id" "$TEST_DIR")

  if assert_json_value "$params" ".subagent_type" "general-purpose" "Type should match" && \
     assert_json_value "$params" ".description" "$subagent_id" "Description should be ID" && \
     assert_json_value "$params" ".model" "claude-sonnet-4-6" "Model should match"; then
    pass "test_generate_agent_params"
  else
    fail "test_generate_agent_params"
  fi

  teardown
}

test_cleanup_completed_subagents() {
  setup

  local task_file="${TEST_DIR}/task.md"
  echo "# Task" > "$task_file"

  # 서브에이전트 생성 및 완료
  local id1 id2
  id1=$(spawn_subagent "$task_file" "$TEST_DIR" "sonnet")
  id2=$(spawn_subagent "$task_file" "$TEST_DIR" "sonnet")

  start_subagent_execution "$id1" "$TEST_DIR"
  complete_subagent "$id1" "$TEST_DIR" "completed"

  # id2는 pending 상태 유지

  # 정리 (0시간 = 즉시 정리)
  # Fixed: Use 0 to clean immediately completed subagents
  local cleaned
  cleaned=$(cleanup_completed_subagents "$TEST_DIR" 0)

  # id1은 정리되고 id2는 남아야 함 (id2는 pending 상태)
  local dir1="${TEST_DIR}/.harness/subagents/${id1}"
  local dir2="${TEST_DIR}/.harness/subagents/${id2}"

  if [[ ! -d "$dir1" ]] && [[ -d "$dir2" ]]; then
    pass "test_cleanup_completed_subagents"
  else
    fail "test_cleanup_completed_subagents (id1 exists: $([[ -d "$dir1" ]] && echo yes || echo no), id2 exists: $([[ -d "$dir2" ]] && echo yes || echo no))"
  fi

  teardown
}

# ============================================================================
# 메인 실행
# ============================================================================

main() {
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Subagent System - Integration Tests"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  # jq 확인
  if ! command -v jq &>/dev/null; then
    echo "ERROR: jq is required for tests"
    echo "Install: brew install jq"
    exit 1
  fi

  # 테스트 실행
  test_spawn_subagent_creates_directory
  test_spawn_subagent_id_format
  test_spawn_subagent_state_json
  test_prepare_subagent_context
  test_get_subagent_status
  test_start_subagent_execution
  test_complete_subagent
  test_list_active_subagents
  test_aggregate_subagent_results
  test_wait_for_subagents
  test_generate_agent_params
  test_cleanup_completed_subagents

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
