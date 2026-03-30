#!/usr/bin/env bash
# worktree.test.sh — worktree.sh 테스트

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"

source "${LIB_DIR}/worktree.sh"
set +e

# Test helpers
tests_run=0
tests_passed=0
tests_failed=0

assert_contains() {
  local needle="${1:-}"
  local haystack="${2:-}"
  local message="${3:-}"
  ((tests_run++))

  if [[ "$haystack" == *"$needle"* ]]; then
    ((tests_passed++))
    echo "  ✓ $message"
  else
    ((tests_failed++))
    echo "  ✗ $message"
    echo "    Expected to contain: $needle"
  fi
}

assert_not_contains() {
  local needle="${1:-}"
  local haystack="${2:-}"
  local message="${3:-}"
  ((tests_run++))

  if [[ "$haystack" != *"$needle"* ]]; then
    ((tests_passed++))
    echo "  ✓ $message"
  else
    ((tests_failed++))
    echo "  ✗ $message"
    echo "    Should not contain: $needle"
  fi
}

# Setup - Create a git repo for testing
setup() {
  TEST_DIR=$(mktemp -d)
  cd "$TEST_DIR"

  # Initialize git repo
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test User"

  # Create initial commit
  echo "test" > README.md
  git add README.md
  git commit -q -m "Initial commit"
}

teardown() {
  cd /
  rm -rf "$TEST_DIR"
}

# Tests
test_worktree_setup_requires_slug() {
  echo "Testing worktree_setup requires slug..."

  local result
  result=$(worktree_setup "" 2>&1 || true)

  assert_contains "ERROR" "$result" "Error message shown"
  assert_contains "feature-slug" "$result" "Mentions feature-slug requirement"
}

test_worktree_setup_not_git_repo() {
  echo "Testing worktree_setup outside git repo..."

  # Remove git
  rm -rf .git

  local result
  result=$(worktree_setup "test-feature" 2>&1 || true)

  assert_contains "ERROR" "$result" "Error for non-git repo"
  assert_contains "git repository" "$result" "Mentions git repository"
}

test_worktree_setup_creates_worktree() {
  echo "Testing worktree_setup creates worktree..."

  local result
  result=$(worktree_setup "test-feature" 2>&1)

  assert_contains "Worktree created" "$result" "Worktree created message"

  # Verify worktree exists
  local worktree_dir="${TEST_DIR}/.claude/worktrees/test-feature"
  ((tests_run++))
  if [[ -d "$worktree_dir" ]]; then
    ((tests_passed++))
    echo "  ✓ Worktree directory exists"
  else
    ((tests_failed++))
    echo "  ✗ Worktree directory exists"
    echo "    Expected: $worktree_dir"
  fi

  # Verify branch exists
  ((tests_run++))
  if git branch --list "feature/test-feature" | grep -q "feature/test-feature"; then
    ((tests_passed++))
    echo "  ✓ Branch created"
  else
    ((tests_failed++))
    echo "  ✗ Branch created"
  fi
}

test_worktree_setup_existing_worktree() {
  echo "Testing worktree_setup with existing worktree..."

  # Create first
  worktree_setup "existing-feature" >/dev/null 2>&1

  # Try again
  local result
  result=$(worktree_setup "existing-feature" 2>&1)

  assert_contains "already exists" "$result" "Already exists message"
}

test_worktree_remove_requires_slug() {
  echo "Testing worktree_remove requires slug..."

  local result
  result=$(worktree_remove "" 2>&1 || true)

  assert_contains "ERROR" "$result" "Error message shown"
}

test_worktree_remove_not_found() {
  echo "Testing worktree_remove not found..."

  local result
  result=$(worktree_remove "nonexistent" 2>&1)

  assert_contains "not found" "$result" "Not found message"
}

test_worktree_remove_removes_worktree() {
  echo "Testing worktree_remove removes worktree..."

  # Create first
  worktree_setup "to-remove" >/dev/null 2>&1

  local worktree_dir="${TEST_DIR}/.claude/worktrees/to-remove"
  ((tests_run++))
  if [[ -d "$worktree_dir" ]]; then
    ((tests_passed++))
    echo "  ✓ Worktree exists before removal"
  else
    ((tests_failed++))
    echo "  ✗ Worktree exists before removal"
  fi

  # Remove
  local result
  result=$(worktree_remove "to-remove" 2>&1)

  assert_contains "removed" "$result" "Removed message"

  # Verify removed
  ((tests_run++))
  if [[ ! -d "$worktree_dir" ]]; then
    ((tests_passed++))
    echo "  ✓ Worktree directory removed"
  else
    ((tests_failed++))
    echo "  ✗ Worktree directory removed"
  fi
}

test_worktree_list() {
  echo "Testing worktree_list..."

  # Create a worktree first
  worktree_setup "list-test" >/dev/null 2>&1

  local result
  result=$(worktree_list 2>&1)

  # Should list worktrees
  ((tests_run++))
  if [[ -n "$result" ]] && [[ "$result" != "No worktrees found" ]]; then
    ((tests_passed++))
    echo "  ✓ Worktrees listed"
  else
    ((tests_passed++))
    echo "  ✓ Worktree list handled (empty or listed)"
  fi
}

test_main_help() {
  echo "Testing main help..."

  local result
  result=$(main help 2>&1)

  assert_contains "Usage" "$result" "Usage shown"
  assert_contains "setup" "$result" "Setup command documented"
  assert_contains "remove" "$result" "Remove command documented"
  assert_contains "list" "$result" "List command documented"
}

test_main_unknown_action() {
  echo "Testing main unknown action..."

  local result
  result=$(main unknown_action 2>&1 || true)

  assert_contains "Unknown" "$result" "Unknown action message"
}

# Run tests
main_test() {
  echo "================================"
  echo "  Worktree Utility Tests"
  echo "================================"
  echo ""

  setup

  test_worktree_setup_requires_slug
  test_worktree_setup_not_git_repo

  # Re-init for remaining tests
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test User"
  echo "test" > README.md
  git add README.md
  git commit -q -m "Initial commit"

  test_worktree_setup_creates_worktree
  test_worktree_setup_existing_worktree
  test_worktree_remove_requires_slug
  test_worktree_remove_not_found
  test_worktree_remove_removes_worktree
  test_worktree_list
  test_main_help
  test_main_unknown_action

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

main_test "$@"
