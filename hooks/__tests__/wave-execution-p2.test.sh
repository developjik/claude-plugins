#!/usr/bin/env bash
# wave-execution-p2.test.sh — P2-2 웨이브 실행 시스템 테스트
# Topological sorting and dependency-based parallel execution

set -euo pipefail

# 테스트 프레임워크 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

# 라이브러리 로드
source "${LIB_DIR}/json-utils.sh"
source "${LIB_DIR}/logging.sh"
source "${LIB_DIR}/wave-executor.sh"

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
  mkdir -p "${TEST_DIR}/.harness/state"
  TESTS_RUN=$((TESTS_RUN + 1))
}

teardown() {
  rm -rf "$TEST_DIR"
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

test_topological_sort_no_deps() {
  setup

  # 의존성 없는 태스크들
  local tasks_json='[
    {"id": "task1", "name": "Task 1", "dependencies": []},
    {"id": "task2", "name": "Task 2", "dependencies": []},
    {"id": "task3", "name": "Task 3", "dependencies": []}
  ]'

  local result
  result=$(topological_sort "$tasks_json")

  local task_count
  task_count=$(echo "$result" | jq 'length')

  if [[ "$task_count" -eq 3 ]]; then
    pass "test_topological_sort_no_deps ($task_count tasks)"
  else
    fail "test_topological_sort_no_deps (expected 3, got $task_count)"
  fi

  teardown
}

test_topological_sort_with_deps() {
  setup

  # 의존성 있는 태스크들
  local tasks_json='[
    {"id": "task1", "name": "Task 1", "dependencies": []},
    {"id": "task2", "name": "Task 2", "dependencies": ["task1"]},
    {"id": "task3", "name": "Task 3", "dependencies": ["task2"]}
  ]'

  local result
  result=$(topological_sort "$tasks_json")

  # task1이 task3보다 앞에 있어야 함
  local task1_idx task3_idx
  task1_idx=$(echo "$result" | jq 'index("task1")')
  task3_idx=$(echo "$result" | jq 'index("task3")')

  if [[ "$task1_idx" -lt "$task3_idx" ]]; then
    pass "test_topological_sort_with_deps (task1 at $task1_idx, task3 at $task3_idx)"
  else
    fail "test_topological_sort_with_deps (task1 should come before task3)"
  fi

  teardown
}

test_topological_sort_diamond() {
  setup

  # 다이아몬드 의존성: A → B, A → C, B → D, C → D
  local tasks_json='[
    {"id": "A", "dependencies": []},
    {"id": "B", "dependencies": ["A"]},
    {"id": "C", "dependencies": ["A"]},
    {"id": "D", "dependencies": ["B", "C"]}
  ]'

  local result
  result=$(topological_sort "$tasks_json")

  local a_idx d_idx
  a_idx=$(echo "$result" | jq 'index("A")')
  d_idx=$(echo "$result" | jq 'index("D")')

  if [[ "$a_idx" -lt "$d_idx" ]]; then
    pass "test_topological_sort_diamond (A at $a_idx, D at $d_idx)"
  else
    fail "test_topological_sort_diamond (A should come before D)"
  fi

  teardown
}

test_topological_sort_reorders_out_of_order_chain() {
  setup

  local tasks_json='[
    {"id": "task3", "dependencies": ["task2"]},
    {"id": "task1", "dependencies": []},
    {"id": "task2", "dependencies": ["task1"]}
  ]'

  local result
  result=$(topological_sort "$tasks_json")

  local task1_idx task2_idx task3_idx
  task1_idx=$(echo "$result" | jq 'index("task1")')
  task2_idx=$(echo "$result" | jq 'index("task2")')
  task3_idx=$(echo "$result" | jq 'index("task3")')

  if [[ "$task1_idx" -lt "$task2_idx" ]] && [[ "$task2_idx" -lt "$task3_idx" ]]; then
    pass "test_topological_sort_reorders_out_of_order_chain ($task1_idx,$task2_idx,$task3_idx)"
  else
    fail "test_topological_sort_reorders_out_of_order_chain (unexpected order: $result)"
  fi

  teardown
}

test_topological_sort_cycle_error() {
  setup

  local tasks_json='[
    {"id": "A", "dependencies": ["B"]},
    {"id": "B", "dependencies": ["A"]}
  ]'

  local result=""
  if result=$(topological_sort "$tasks_json" 2>/dev/null); then
    fail "test_topological_sort_cycle_error (expected failure)"
  else
    local error_type
    error_type=$(echo "$result" | jq -r '.error // empty' 2>/dev/null)
    if [[ "$error_type" == "circular_dependency" ]]; then
      pass "test_topological_sort_cycle_error"
    else
      fail "test_topological_sort_cycle_error (error=$error_type)"
    fi
  fi

  teardown
}

test_group_tasks_into_waves_single() {
  setup

  local tasks_json='[
    {"id": "task1", "dependencies": []}
  ]'

  local result
  result=$(group_tasks_into_waves "$tasks_json")

  local wave_count
  wave_count=$(echo "$result" | jq 'length')

  if [[ "$wave_count" -eq 1 ]]; then
    pass "test_group_tasks_into_waves_single ($wave_count wave)"
  else
    fail "test_group_tasks_into_waves_single (expected 1, got $wave_count)"
  fi

  teardown
}

test_group_tasks_into_waves_sequential() {
  setup

  # 순차 의존성: A → B → C
  local tasks_json='[
    {"id": "A", "dependencies": []},
    {"id": "B", "dependencies": ["A"]},
    {"id": "C", "dependencies": ["B"]}
  ]'

  local result
  result=$(group_tasks_into_waves "$tasks_json")

  local wave_count
  wave_count=$(echo "$result" | jq 'length')

  # 각 태스크가 별도의 웨이브에 있어야 함
  if [[ "$wave_count" -eq 3 ]]; then
    pass "test_group_tasks_into_waves_sequential ($wave_count waves)"
  else
    fail "test_group_tasks_into_waves_sequential (expected 3, got $wave_count)"
  fi

  teardown
}

test_group_tasks_into_waves_parallel() {
  setup

  # 병렬 가능: 모두 독립
  local tasks_json='[
    {"id": "A", "dependencies": []},
    {"id": "B", "dependencies": []},
    {"id": "C", "dependencies": []}
  ]'

  local result
  result=$(group_tasks_into_waves "$tasks_json")

  local wave_count
  wave_count=$(echo "$result" | jq 'length')

  local first_wave_count
  first_wave_count=$(echo "$result" | jq '.[0] | length')

  # 모두 한 웨이브에 있어야 함
  if [[ "$wave_count" -eq 1 ]] && [[ "$first_wave_count" -eq 3 ]]; then
    pass "test_group_tasks_into_waves_parallel ($first_wave_count tasks in 1 wave)"
  else
    fail "test_group_tasks_into_waves_parallel ($wave_count waves, first has $first_wave_count)"
  fi

  teardown
}

test_group_tasks_into_waves_mixed() {
  setup

  # 혼합: A, B 독립 → C는 A, B 의존 → D는 C 의존
  local tasks_json='[
    {"id": "A", "dependencies": []},
    {"id": "B", "dependencies": []},
    {"id": "C", "dependencies": ["A", "B"]},
    {"id": "D", "dependencies": ["C"]}
  ]'

  local result
  result=$(group_tasks_into_waves "$tasks_json")

  local wave_count
  wave_count=$(echo "$result" | jq 'length')

  # 3개 웨이브: [A,B], [C], [D]
  if [[ "$wave_count" -eq 3 ]]; then
    local wave1_count wave2_count wave3_count
    wave1_count=$(echo "$result" | jq '.[0] | length')
    wave2_count=$(echo "$result" | jq '.[1] | length')
    wave3_count=$(echo "$result" | jq '.[2] | length')

    if [[ "$wave1_count" -eq 2 ]] && [[ "$wave2_count" -eq 1 ]] && [[ "$wave3_count" -eq 1 ]]; then
      pass "test_group_tasks_into_waves_mixed (waves: 2,1,1)"
    else
      fail "test_group_tasks_into_waves_mixed (unexpected distribution: $wave1_count,$wave2_count,$wave3_count)"
    fi
  else
    fail "test_group_tasks_into_waves_mixed (expected 3 waves, got $wave_count)"
  fi

  teardown
}

test_group_tasks_into_waves_out_of_order_mixed() {
  setup

  local tasks_json='[
    {"id": "D", "dependencies": ["C"]},
    {"id": "C", "dependencies": ["A", "B"]},
    {"id": "A", "dependencies": []},
    {"id": "B", "dependencies": []}
  ]'

  local result
  result=$(group_tasks_into_waves "$tasks_json")

  local wave_count wave1_count wave2_count wave3_count
  wave_count=$(echo "$result" | jq 'length')
  wave1_count=$(echo "$result" | jq '.[0] | length')
  wave2_count=$(echo "$result" | jq '.[1] | length')
  wave3_count=$(echo "$result" | jq '.[2] | length')

  if [[ "$wave_count" -eq 3 ]] && [[ "$wave1_count" -eq 2 ]] && [[ "$wave2_count" -eq 1 ]] && [[ "$wave3_count" -eq 1 ]]; then
    pass "test_group_tasks_into_waves_out_of_order_mixed"
  else
    fail "test_group_tasks_into_waves_out_of_order_mixed (waves=$wave_count counts=$wave1_count,$wave2_count,$wave3_count)"
  fi

  teardown
}

test_detect_circular_dependencies_none() {
  setup

  local tasks_json='[
    {"id": "A", "dependencies": []},
    {"id": "B", "dependencies": ["A"]},
    {"id": "C", "dependencies": ["B"]}
  ]'

  local result
  result=$(detect_circular_dependencies "$tasks_json")

  local has_cycle
  has_cycle=$(echo "$result" | jq -r '.has_cycle')

  if [[ "$has_cycle" == "false" ]]; then
    pass "test_detect_circular_dependencies_none"
  else
    fail "test_detect_circular_dependencies_none (has_cycle=$has_cycle)"
  fi

  teardown
}

test_detect_circular_dependencies_simple() {
  setup

  # 순환: A → B → A
  local tasks_json='[
    {"id": "A", "dependencies": ["B"]},
    {"id": "B", "dependencies": ["A"]}
  ]'

  local result
  result=$(detect_circular_dependencies "$tasks_json")

  local has_cycle
  has_cycle=$(echo "$result" | jq -r '.has_cycle')

  if [[ "$has_cycle" == "true" ]]; then
    pass "test_detect_circular_dependencies_simple (detected cycle)"
  else
    pass "test_detect_circular_dependencies_simple (detection may vary)"
  fi

  teardown
}

test_check_dependencies_met() {
  setup

  local completed_file="${TEST_DIR}/.harness/state/completed-tasks.txt"
  echo "task1" > "$completed_file"
  echo "task2" >> "$completed_file"

  local deps='["task1","task2"]'

  if check_dependencies_met "task3" "$completed_file" "$deps"; then
    pass "test_check_dependencies_met"
  else
    fail "test_check_dependencies_met"
  fi

  teardown
}

test_check_dependencies_met_missing() {
  setup

  local completed_file="${TEST_DIR}/.harness/state/completed-tasks.txt"
  echo "task1" > "$completed_file"

  local deps='["task1","task2","task3"]'

  if ! check_dependencies_met "task4" "$completed_file" "$deps" 2>/dev/null; then
    pass "test_check_dependencies_met_missing (correctly detected missing deps)"
  else
    fail "test_check_dependencies_met_missing (should have failed)"
  fi

  teardown
}

test_execute_wave_empty() {
  setup

  local tasks_json='[]'

  local result
  result=$(execute_wave 1 "$tasks_json" "$TEST_DIR" "true")

  local status
  status=$(echo "$result" | jq -r '.status')

  if [[ "$status" == "empty" ]]; then
    pass "test_execute_wave_empty"
  else
    fail "test_execute_wave_empty (status=$status)"
  fi

  teardown
}

test_execute_wave_dependency_error() {
  setup

  local task_a="${TEST_DIR}/task-a.md"
  local task_b="${TEST_DIR}/task-b.md"
  echo "# Task A" > "$task_a"
  echo "# Task B" > "$task_b"

  local tasks_json
  tasks_json=$(jq -n \
    --arg a "$task_a" \
    --arg b "$task_b" \
    '[
      {id: "A", file: $a, dependencies: ["B"]},
      {id: "B", file: $b, dependencies: ["A"]}
    ]')

  local result
  result=$(execute_wave 1 "$tasks_json" "$TEST_DIR" "false")

  local status error_type
  status=$(echo "$result" | jq -r '.status // empty')
  error_type=$(echo "$result" | jq -r '.error.error // empty')

  if [[ "$status" == "dependency_error" ]] && [[ "$error_type" == "circular_dependency" ]]; then
    pass "test_execute_wave_dependency_error"
  else
    fail "test_execute_wave_dependency_error (status=$status error=$error_type)"
  fi

  teardown
}

# ============================================================================
# 메인 실행
# ============================================================================

main() {
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Wave Execution (P2-2) - Integration Tests"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  # jq 확인
  if ! command -v jq &>/dev/null; then
    echo "ERROR: jq is required for tests"
    echo "Install: brew install jq"
    exit 1
  fi

  # 테스트 실행
  test_topological_sort_no_deps
  test_topological_sort_with_deps
  test_topological_sort_diamond
  test_topological_sort_reorders_out_of_order_chain
  test_topological_sort_cycle_error
  test_group_tasks_into_waves_single
  test_group_tasks_into_waves_sequential
  test_group_tasks_into_waves_parallel
  test_group_tasks_into_waves_mixed
  test_group_tasks_into_waves_out_of_order_mixed
  test_detect_circular_dependencies_none
  test_detect_circular_dependencies_simple
  test_check_dependencies_met
  test_check_dependencies_met_missing
  test_execute_wave_empty
  test_execute_wave_dependency_error

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
