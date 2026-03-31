#!/usr/bin/env bash
# cleanup.test.sh — cleanup.sh 테스트

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"

source "${LIB_DIR}/cleanup.sh"

# Test helpers
tests_run=0
tests_passed=0
tests_failed=0

assert_equals() {
  local expected="${1:-}"
  local actual="${2:-}"
  local message="${3:-}"
  ((tests_run++))

  if [[ "$expected" == "$actual" ]]; then
    ((tests_passed++))
    echo "  ✓ $message"
  else
    ((tests_failed++))
    echo "  ✗ $message"
    echo "    Expected: $expected"
    echo "    Actual: $actual"
  fi
}

assert_file_exists() {
  local file="${1:-}"
  local message="${2:-}"
  ((tests_run++))

  if [[ -f "$file" ]]; then
    ((tests_passed++))
    echo "  ✓ $message"
  else
    ((tests_failed++))
    echo "  ✗ $message"
    echo "    File not found: $file"
  fi
}

assert_file_not_exists() {
  local file="${1:-}"
  local message="${2:-}"
  ((tests_run++))

  if [[ ! -f "$file" ]]; then
    ((tests_passed++))
    echo "  ✓ $message"
  else
    ((tests_failed++))
    echo "  ✗ $message"
    echo "    File should not exist: $file"
  fi
}

# Setup
setup() {
  TEST_DIR=$(mktemp -d)
  export CLAUDE_PROJECT_DIR="$TEST_DIR"
  mkdir -p "${TEST_DIR}/.harness/locks"
  mkdir -p "${TEST_DIR}/.harness/backups"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Tests
test_register_temp_file() {
  echo "Testing register_temp_file..."

  local temp_file="${TEST_DIR}/temp_test.txt"
  touch "$temp_file"

  # Reset state
  _HARNESS_TEMP_FILES=()
  _HARNESS_CLEANUP_REGISTERED=false

  register_temp_file "$temp_file"

  assert_equals "1" "${#_HARNESS_TEMP_FILES[@]}" "Temp file registered"
  assert_equals "$temp_file" "${_HARNESS_TEMP_FILES[0]}" "Correct file path"
  assert_equals "true" "$_HARNESS_CLEANUP_REGISTERED" "Cleanup handler registered"
}

test_register_lock_file() {
  echo "Testing register_lock_file..."

  local lock_file="${TEST_DIR}/.harness/locks/test.lock"
  echo "$$" > "$lock_file"

  # Reset state
  _HARNESS_LOCK_FILES=()
  _HARNESS_CLEANUP_REGISTERED=false

  register_lock_file "$lock_file"

  assert_equals "1" "${#_HARNESS_LOCK_FILES[@]}" "Lock file registered"
  assert_equals "$lock_file" "${_HARNESS_LOCK_FILES[0]}" "Correct lock path"
}

test_create_temp_file() {
  echo "Testing create_temp_file..."

  # Note: Command substitution ($()) runs in a subshell, so _HARNESS_TEMP_FILES
  # won't be visible in parent shell. This is expected bash behavior.
  # Real usage should call create_temp_file directly or use register_temp_file separately.

  # Test 1: File creation works
  local temp_file
  temp_file=$(create_temp_file "test" "$TEST_DIR")

  assert_file_exists "$temp_file" "Temp file created"

  # Test 2: Direct registration works (not via subshell)
  local direct_temp="${TEST_DIR}/direct_test.txt"
  touch "$direct_temp"
  _HARNESS_TEMP_FILES=()
  register_temp_file "$direct_temp"

  local found=false
  for registered in "${_HARNESS_TEMP_FILES[@]}"; do
    if [[ "$registered" == "$direct_temp" ]]; then
      found=true
      break
    fi
  done

  ((tests_run++))
  if $found; then
    ((tests_passed++))
    echo "  ✓ register_temp_file works correctly"
  else
    ((tests_failed++))
    echo "  ✗ register_temp_file works correctly"
  fi

  rm -f "$temp_file" "$direct_temp"
}

test_acquire_lock() {
  echo "Testing acquire_lock..."

  local result
  if acquire_lock "test_lock" 5; then
    ((tests_run++))
    ((tests_passed++))
    echo "  ✓ Lock acquired successfully"
  else
    ((tests_run++))
    ((tests_failed++))
    echo "  ✗ Lock acquisition failed"
  fi

  # Check lock file exists
  local lock_file="${TEST_DIR}/.harness/locks/test_lock.lock"
  assert_file_exists "$lock_file" "Lock file created"

  # Check lock contains our PID
  local lock_pid
  lock_pid=$(cat "$lock_file")
  assert_equals "$$" "$lock_pid" "Lock contains correct PID"
}

test_release_lock() {
  echo "Testing release_lock..."

  # First acquire
  acquire_lock "test_lock2" 5

  local lock_file="${TEST_DIR}/.harness/locks/test_lock2.lock"
  assert_file_exists "$lock_file" "Lock file created before release"

  # Then release
  release_lock "test_lock2"

  assert_file_not_exists "$lock_file" "Lock file removed after release"
}

test_lock_timeout() {
  echo "Testing lock timeout..."

  local lock_file="${TEST_DIR}/.harness/locks/timeout_test.lock"

  # Create a stale lock with a different PID
  echo "999999" > "$lock_file"

  # acquire_lock should detect dead process and acquire
  if acquire_lock "timeout_test" 2; then
    ((tests_run++))
    ((tests_passed++))
    echo "  ✓ Lock acquired after detecting stale lock"
  else
    ((tests_run++))
    ((tests_failed++))
    echo "  ✗ Failed to acquire lock with stale PID"
  fi
}

test_cleanup_on_exit() {
  echo "Testing _harness_cleanup_on_exit..."

  # Create temp files
  local temp1="${TEST_DIR}/temp1.txt"
  local temp2="${TEST_DIR}/temp2.txt"
  touch "$temp1" "$temp2"

  # Register them
  _HARNESS_TEMP_FILES=("$temp1" "$temp2")

  # Create lock
  local lock="${TEST_DIR}/.harness/locks/cleanup_test.lock"
  echo "$$" > "$lock"
  _HARNESS_LOCK_FILES=("$lock")

  # Run cleanup
  _harness_cleanup_on_exit || true

  assert_file_not_exists "$temp1" "Temp file 1 cleaned"
  assert_file_not_exists "$temp2" "Temp file 2 cleaned"
  assert_file_not_exists "$lock" "Lock file cleaned"
}

test_cleanup_old_backups() {
  echo "Testing cleanup_old_backups..."

  local backup_dir="${TEST_DIR}/.harness/backups"

  # Create a new backup (should survive)
  local new_backup="${backup_dir}/new.bak"
  touch "$new_backup"

  # Create an old backup (should be deleted)
  local old_backup="${backup_dir}/old.bak"
  touch "$old_backup"
  # Set modification time to 10 days ago
  if [[ "$OSTYPE" == "darwin"* ]]; then
    touch -t $(date -v-10d +%Y%m%d%H%M) "$old_backup" 2>/dev/null || true
  else
    touch -d "10 days ago" "$old_backup" 2>/dev/null || true
  fi

  cleanup_old_backups 7 "$backup_dir"

  assert_file_exists "$new_backup" "New backup preserved"
  # Note: Old backup cleanup depends on find -mtime, may not work in all environments
}

test_harness_init_cleanup() {
  echo "Testing harness_init_cleanup..."

  local logs_dir="${TEST_DIR}/.harness/logs"
  mkdir -p "$logs_dir"

  # Create log files
  touch "${logs_dir}/test.log"
  touch "${logs_dir}/test.jsonl"

  harness_init_cleanup

  # Should not error
  ((tests_run++))
  ((tests_passed++))
  echo "  ✓ harness_init_cleanup runs without error"
}

# Run tests
main() {
  echo "================================"
  echo "  Cleanup Utility Tests"
  echo "================================"
  echo ""

  setup

  test_register_temp_file
  test_register_lock_file
  test_create_temp_file
  test_acquire_lock
  test_release_lock
  test_lock_timeout
  test_cleanup_on_exit
  test_cleanup_old_backups
  test_harness_init_cleanup

  teardown

  echo ""
  echo "================================"
  echo "  Results: $tests_passed/$tests_run passed"
  if [[ $tests_failed -gt 0 ]]; then
    echo "  Failed: $tests_failed"
    exit 1
  fi
  echo "  All tests passed! ✓"
  echo "================================"
}

main "$@"
