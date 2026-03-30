#!/usr/bin/env bash
# skill-chain.test.sh — skill-chain.sh 테스트

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"

source "${LIB_DIR}/skill-chain.sh"

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

# Setup
setup() {
  TEST_DIR=$(mktemp -d)
  export CLAUDE_PROJECT_DIR="$TEST_DIR"
  export CLAUDE_PLUGIN_ROOT="$TEST_DIR"

  mkdir -p "${TEST_DIR}/docs/specs/test-feature"
  mkdir -p "${TEST_DIR}/skills"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Tests
test_get_skill_requires_empty() {
  echo "Testing get_skill_requires with non-existent skill..."

  local result
  result=$(get_skill_requires "nonexistent")

  assert_equals "" "$result" "Empty string for non-existent skill"
}

test_get_skill_requires_with_requires() {
  echo "Testing get_skill_requires with requires field..."

  # Create a skill with requires
  mkdir -p "${TEST_DIR}/skills/test-skill"
  cat > "${TEST_DIR}/skills/test-skill/SKILL.md" << 'EOF'
---
name: test-skill
requires: plan
---
# Test Skill
EOF

  local result
  result=$(get_skill_requires "test-skill")

  assert_equals "plan" "$result" "Returns requires value"
}

test_get_skill_requires_without_requires() {
  echo "Testing get_skill_requires without requires field..."

  # Create a skill without requires
  mkdir -p "${TEST_DIR}/skills/no-requires-skill"
  cat > "${TEST_DIR}/skills/no-requires-skill/SKILL.md" << 'EOF'
---
name: no-requires-skill
---
# No Requires Skill
EOF

  local result
  result=$(get_skill_requires "no-requires-skill")

  assert_equals "" "$result" "Empty string when no requires"
}

test_check_prerequisite_doc_clarify() {
  echo "Testing check_prerequisite_doc for clarify..."

  # Create clarify doc
  touch "${TEST_DIR}/docs/specs/test-feature/clarify.md"

  if check_prerequisite_doc "test-feature" "clarify"; then
    ((tests_run++))
    ((tests_passed++))
    echo "  ✓ Clarify doc check passes when exists"
  else
    ((tests_run++))
    ((tests_failed++))
    echo "  ✗ Clarify doc check passes when exists"
  fi
}

test_check_prerequisite_doc_missing() {
  echo "Testing check_prerequisite_doc when missing..."

  if ! check_prerequisite_doc "test-feature" "plan" 2>/dev/null; then
    ((tests_run++))
    ((tests_passed++))
    echo "  ✓ Plan doc check fails when missing"
  else
    ((tests_run++))
    ((tests_failed++))
    echo "  ✗ Plan doc check fails when missing"
  fi
}

test_check_prerequisite_doc_check_phase() {
  echo "Testing check_prerequisite_doc for check phase..."

  # check phase always returns 0 (skipped)
  if check_prerequisite_doc "test-feature" "check"; then
    ((tests_run++))
    ((tests_passed++))
    echo "  ✓ Check phase always passes"
  else
    ((tests_run++))
    ((tests_failed++))
    echo "  ✗ Check phase always passes"
  fi
}

test_check_prerequisite_doc_wrapup_phase() {
  echo "Testing check_prerequisite_doc for wrapup phase..."

  # wrapup phase always returns 0 (skipped)
  if check_prerequisite_doc "test-feature" "wrapup"; then
    ((tests_run++))
    ((tests_passed++))
    echo "  ✓ Wrapup phase always passes"
  else
    ((tests_run++))
    ((tests_failed++))
    echo "  ✗ Wrapup phase always passes"
  fi
}

test_validate_skill_chain_no_requires() {
  echo "Testing validate_skill_chain with no requires..."

  # Should pass when no requires
  if validate_skill_chain "no-requires-skill" "test-feature"; then
    ((tests_run++))
    ((tests_passed++))
    echo "  ✓ Passes when no requires"
  else
    ((tests_run++))
    ((tests_failed++))
    echo "  ✗ Passes when no requires"
  fi
}

test_validate_skill_chain_missing_prerequisite() {
  echo "Testing validate_skill_chain with missing prerequisite..."

  local result
  result=$(validate_skill_chain "test-skill" "test-feature" 2>&1 || true)

  assert_equals "MISSING_PREREQUISITE" "$result" "Returns MISSING_PREREQUISITE"
}

test_validate_skill_chain_satisfied() {
  echo "Testing validate_skill_chain with satisfied prerequisite..."

  # Create the required doc
  touch "${TEST_DIR}/docs/specs/test-feature/plan.md"

  if validate_skill_chain "test-skill" "test-feature"; then
    ((tests_run++))
    ((tests_passed++))
    echo "  ✓ Passes when prerequisite satisfied"
  else
    ((tests_run++))
    ((tests_failed++))
    echo "  ✗ Passes when prerequisite satisfied"
  fi
}

test_generate_chain_block_message() {
  echo "Testing generate_chain_block_message..."

  local result
  result=$(generate_chain_block_message "implement" "design" "test-feature")

  assert_contains '"decision": "block"' "$result" "Contains block decision"
  assert_contains '"error_code": "E501"' "$result" "Contains error code"
  assert_contains "design" "$result" "Contains required phase"
  assert_contains "test-feature" "$result" "Contains feature slug"
}

test_generate_chain_warning_message() {
  echo "Testing generate_chain_warning_message..."

  local result
  result=$(generate_chain_warning_message "implement" "design" "test-feature")

  assert_contains '"decision": "allow"' "$result" "Contains allow decision"
  assert_contains '"warning"' "$result" "Contains warning"
  assert_contains "W501" "$result" "Contains warning code"
}

test_infer_skill_from_agent() {
  echo "Testing infer_skill_from_agent..."

  local result

  result=$(infer_skill_from_agent "strategist")
  assert_equals "plan" "$result" "strategist -> plan"

  result=$(infer_skill_from_agent "architect")
  assert_equals "design" "$result" "architect -> design"

  result=$(infer_skill_from_agent "engineer")
  assert_equals "implement" "$result" "engineer -> implement"

  result=$(infer_skill_from_agent "guardian")
  assert_equals "check" "$result" "guardian -> check"

  result=$(infer_skill_from_agent "librarian")
  assert_equals "wrapup" "$result" "librarian -> wrapup"

  result=$(infer_skill_from_agent "debugger")
  assert_equals "debug" "$result" "debugger -> debug"
}

test_infer_skill_from_agent_with_prefix() {
  echo "Testing infer_skill_from_agent with prefix..."

  local result
  result=$(infer_skill_from_agent "harness-engineering:strategist")
  assert_equals "plan" "$result" "Extracts skill from prefixed agent (strategist -> plan)"
}

test_check_and_validate_chain_strict() {
  echo "Testing check_and_validate_chain strict mode..."

  # Ensure plan.md does NOT exist (may have been created by previous tests)
  rm -f "${TEST_DIR}/docs/specs/test-feature/plan.md"

  # Use existing test-skill created by previous test
  local result

  # Capture output even on failure
  set +e
  result=$(check_and_validate_chain "test-skill" "test-feature" "true" 2>&1)
  local exit_code=$?
  set -e

  # Should block in strict mode
  assert_contains "block" "$result" "Blocks in strict mode"
}

test_check_and_validate_chain_non_strict() {
  echo "Testing check_and_validate_chain non-strict mode..."

  # Remove plan.md to test warning
  rm -f "${TEST_DIR}/docs/specs/test-feature/plan.md"

  local result
  result=$(check_and_validate_chain "test-skill" "test-feature" "false" 2>&1 || true)

  # Should warn but allow in non-strict mode
  assert_contains "allow" "$result" "Allows in non-strict mode"
  assert_contains "warning" "$result" "Warns in non-strict mode"
}

# Run tests
main() {
  echo "================================"
  echo "  Skill Chain Utility Tests"
  echo "================================"
  echo ""

  setup

  test_get_skill_requires_empty
  test_get_skill_requires_with_requires
  test_get_skill_requires_without_requires
  test_check_prerequisite_doc_clarify
  test_check_prerequisite_doc_missing
  test_check_prerequisite_doc_check_phase
  test_check_prerequisite_doc_wrapup_phase
  test_validate_skill_chain_no_requires
  test_validate_skill_chain_missing_prerequisite
  test_validate_skill_chain_satisfied
  test_generate_chain_block_message
  test_generate_chain_warning_message
  test_infer_skill_from_agent
  test_infer_skill_from_agent_with_prefix
  test_check_and_validate_chain_strict
  test_check_and_validate_chain_non_strict

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
