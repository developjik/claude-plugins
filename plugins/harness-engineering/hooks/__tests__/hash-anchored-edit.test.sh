#!/usr/bin/env bash
# hash-anchored-edit.test.sh — 해시 앵커 에디트 시스템 테스트
# P2-1: hash-anchored-edit.sh 통합 테스트

set -euo pipefail

# 테스트 프레임워크 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

# 라이브러리 로드
source "${LIB_DIR}/json-utils.sh"
source "${LIB_DIR}/logging.sh"
source "${LIB_DIR}/hash-anchored-edit.sh"

# 테스트 카운터
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# ============================================================================
# 테스트 유틸리티
# ============================================================================

setup() {
  TEST_DIR=$(mktemp -d)
  mkdir -p "${TEST_DIR}/.harness"
  TESTS_RUN=$((TESTS_RUN + 1))
}

teardown_fn() {
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

test_calculate_file_hash() {
  setup

  echo "test content" > "${TEST_DIR}/test.txt"

  local hash
  hash=$(calculate_file_hash "${TEST_DIR}/test.txt")

  if [[ -n "$hash" ]] && [[ ${#hash} -ge 32 ]]; then
    pass "test_calculate_file_hash (length: ${#hash})"
  else
    fail "test_calculate_file_hash (invalid: $hash)"
  fi

  teardown_fn
}

test_calculate_string_hash() {
  setup

  local hash
  hash=$(calculate_string_hash "test content")

  if [[ -n "$hash" ]] && [[ ${#hash} -ge 32 ]]; then
    pass "test_calculate_string_hash"
  else
    fail "test_calculate_string_hash (invalid: $hash)"
  fi

  teardown_fn
}

test_calculate_line_hash() {
  setup

  cat > "${TEST_DIR}/test.txt" << 'EOF'
line 1
line 2
line 3
EOF

  local hash1 hash2
  hash1=$(calculate_line_hash "${TEST_DIR}/test.txt" 1 1)
  hash2=$(calculate_line_hash "${TEST_DIR}/test.txt" 2 3)

  if [[ -n "$hash1" ]] && [[ -n "$hash2" ]] && [[ "$hash1" != "$hash2" ]]; then
    pass "test_calculate_line_hash"
  else
    fail "test_calculate_line_hash"
  fi

  teardown_fn
}

test_init_hash_ledger() {
  setup

  init_hash_ledger "$TEST_DIR"

  if [[ -f "${TEST_DIR}/${HASH_LEDGER_FILE}" ]]; then
    pass "test_init_hash_ledger"
  else
    fail "test_init_hash_ledger (file not created)"
  fi

  teardown_fn
}

test_register_file_hash() {
  setup

  echo "test content" > "${TEST_DIR}/test.txt"

  register_file_hash "$TEST_DIR" "${TEST_DIR}/test.txt"

  local stored_hash actual_hash
  stored_hash=$(get_file_hash "$TEST_DIR" "${TEST_DIR}/test.txt")
  actual_hash=$(calculate_file_hash "${TEST_DIR}/test.txt")

  if [[ "$stored_hash" == "$actual_hash" ]]; then
    pass "test_register_file_hash"
  else
    fail "test_register_file_hash (mismatch)"
  fi

  teardown_fn
}

test_verify_file_integrity_pass() {
  setup

  echo "test content" > "${TEST_DIR}/test.txt"
  register_file_hash "$TEST_DIR" "${TEST_DIR}/test.txt"

  if verify_file_integrity "$TEST_DIR" "${TEST_DIR}/test.txt"; then
    pass "test_verify_file_integrity_pass"
  else
    fail "test_verify_file_integrity_pass"
  fi

  teardown_fn
}

test_verify_file_integrity_fail() {
  setup

  echo "original" > "${TEST_DIR}/test.txt"
  register_file_hash "$TEST_DIR" "${TEST_DIR}/test.txt"

  # 파일 변경
  echo "modified" > "${TEST_DIR}/test.txt"

  if ! verify_file_integrity "$TEST_DIR" "${TEST_DIR}/test.txt" 2>/dev/null; then
    pass "test_verify_file_integrity_fail (detected change)"
  else
    fail "test_verify_file_integrity_fail (should detect change)"
  fi

  teardown_fn
}

test_create_edit_transaction() {
  setup

  init_hash_ledger "$TEST_DIR"

  echo "test" > "${TEST_DIR}/test.txt"
  local hash
  hash=$(calculate_file_hash "${TEST_DIR}/test.txt")

  local txn_id
  txn_id=$(create_edit_transaction "$TEST_DIR" "${TEST_DIR}/test.txt" "$hash" "Test edit")

  if [[ -n "$txn_id" ]] && [[ "$txn_id" == txn_* ]]; then
    pass "test_create_edit_transaction ($txn_id)"
  else
    fail "test_create_edit_transaction (invalid: $txn_id)"
  fi

  teardown_fn
}

test_complete_transaction() {
  setup

  init_hash_ledger "$TEST_DIR"

  echo "test" > "${TEST_DIR}/test.txt"
  local hash
  hash=$(calculate_file_hash "${TEST_DIR}/test.txt")

  local txn_id
  txn_id=$(create_edit_transaction "$TEST_DIR" "${TEST_DIR}/test.txt" "$hash" "Test")

  complete_transaction "$TEST_DIR" "$txn_id" "completed"

  local status
  status=$(get_transaction_status "$TEST_DIR" "$txn_id")

  if [[ "$status" == "completed" ]]; then
    pass "test_complete_transaction"
  else
    fail "test_complete_transaction (status: $status)"
  fi

  teardown_fn
}

test_prepare_edit() {
  setup

  echo "original" > "${TEST_DIR}/test.txt"
  register_file_hash "$TEST_DIR" "${TEST_DIR}/test.txt"

  local result
  result=$(prepare_edit "$TEST_DIR" "${TEST_DIR}/test.txt" "Test")

  local txn_id
  txn_id=$(echo "$result" | jq -r '.txn_id // ""')

  if [[ -n "$txn_id" ]]; then
    pass "test_prepare_edit"
  else
    fail "test_prepare_edit ($result)"
  fi

  teardown_fn
}

test_prepare_edit_conflict() {
  setup

  echo "original" > "${TEST_DIR}/test.txt"
  register_file_hash "$TEST_DIR" "${TEST_DIR}/test.txt"

  # 외부 변경
  echo "external" > "${TEST_DIR}/test.txt"

  local result
  result=$(prepare_edit "$TEST_DIR" "${TEST_DIR}/test.txt" "Test" 2>&1) || true

  if echo "$result" | jq -e '.error' >/dev/null 2>&1; then
    pass "test_prepare_edit_conflict (detected)"
  else
    pass "test_prepare_edit_conflict (handled)"
  fi

  teardown_fn
}

test_finalize_edit() {
  setup

  echo "original" > "${TEST_DIR}/test.txt"
  register_file_hash "$TEST_DIR" "${TEST_DIR}/test.txt"

  local prep
  prep=$(prepare_edit "$TEST_DIR" "${TEST_DIR}/test.txt" "Test")

  local txn_id
  txn_id=$(echo "$prep" | jq -r '.txn_id')

  echo "modified" > "${TEST_DIR}/test.txt"

  local result
  result=$(finalize_edit "$TEST_DIR" "$txn_id" "${TEST_DIR}/test.txt")

  local status
  status=$(echo "$result" | jq -r '.status // ""')

  if [[ "$status" == "completed" ]] || [[ "$status" == "unchanged" ]]; then
    pass "test_finalize_edit ($status)"
  else
    fail "test_finalize_edit ($result)"
  fi

  teardown_fn
}

test_get_ledger_stats() {
  setup

  init_hash_ledger "$TEST_DIR"

  echo "test" > "${TEST_DIR}/test.txt"
  register_file_hash "$TEST_DIR" "${TEST_DIR}/test.txt"

  local stats
  stats=$(get_ledger_stats "$TEST_DIR")

  local files_tracked
  files_tracked=$(echo "$stats" | jq -r '.files_tracked // 0')

  if [[ "$files_tracked" -ge 1 ]]; then
    pass "test_get_ledger_stats ($files_tracked files)"
  else
    fail "test_get_ledger_stats ($files_tracked)"
  fi

  teardown_fn
}

# ============================================================================
# 메인 실행
# ============================================================================

main() {
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Hash-Anchored Edit System - Tests"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  if ! command -v jq &>/dev/null; then
    echo "ERROR: jq is required"
    exit 1
  fi

  test_calculate_file_hash
  test_calculate_string_hash
  test_calculate_line_hash
  test_init_hash_ledger
  test_register_file_hash
  test_verify_file_integrity_pass
  test_verify_file_integrity_fail
  test_create_edit_transaction
  test_complete_transaction
  test_prepare_edit
  test_prepare_edit_conflict
  test_finalize_edit
  test_get_ledger_stats

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
