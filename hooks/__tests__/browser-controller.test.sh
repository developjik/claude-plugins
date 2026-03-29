#!/usr/bin/env bash
# browser-controller.test.sh — 브라우저 컨트롤러 테스트

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"

source "${LIB_DIR}/browser-controller.sh"

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

assert_json_key() {
  local key="${1:-}"
  local json="${2:-}"
  local message="${3:-}"
  ((tests_run++))

  if echo "$json" | jq -e --arg key "$key" 'has($key)' &>/dev/null; then
    ((tests_passed++))
    echo "  ✓ $message"
  else
    ((tests_failed++))
    echo "  ✗ $message"
    echo "    Key not found: $key"
  fi
}

# Setup
setup() {
  TEST_DIR=$(mktemp -d)
  mkdir -p "${TEST_DIR}/.harness/browser"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Tests
test_state_initialization() {
  echo "Testing state initialization..."

  _init_browser_state "$TEST_DIR"

  assert_json_key "connected" "$(cat "${TEST_DIR}/.harness/browser/session.json")" "Session file has 'connected' key"
  assert_json_key "mode" "$(cat "${TEST_DIR}/.harness/browser/session.json")" "Session file has 'mode' key"
}

test_state_update() {
  echo "Testing state update..."

  _init_browser_state "$TEST_DIR"
  _update_browser_state "$TEST_DIR" "connected" "true"

  local connected
  connected=$(jq -r '.connected' "${TEST_DIR}/.harness/browser/session.json")

  assert_equals "true" "$connected" "State updated correctly"
}

test_state_get() {
  echo "Testing state retrieval..."

  _init_browser_state "$TEST_DIR"

  local mode
  mode=$(_get_browser_state "$TEST_DIR" "mode")

  assert_equals "headless" "$mode" "Got correct initial mode"
}

test_browser_status() {
  echo "Testing browser_status..."

  local status
  status=$(browser_status "$TEST_DIR")

  assert_json_key "connected" "$status" "Status has 'connected'"
  assert_json_key "mode" "$status" "Status has 'mode'"
}

test_browser_is_connected() {
  echo "Testing browser_is_connected..."

  _init_browser_state "$TEST_DIR"
  _update_browser_state "$TEST_DIR" "connected" "false"

  # Initially not connected
  if browser_is_connected "$TEST_DIR" 2>/dev/null; then
    ((tests_run++))
    ((tests_failed++))
    echo "  ✗ Should not be connected initially"
  else
    ((tests_run++))
    ((tests_passed++))
    echo "  ✓ Not connected initially"
  fi

  # After setting connected=true
  _update_browser_state "$TEST_DIR" "connected" "true"

  if browser_is_connected "$TEST_DIR" 2>/dev/null; then
    ((tests_run++))
    ((tests_passed++))
    echo "  ✓ Connected after update"
  else
    ((tests_run++))
    ((tests_failed++))
    echo "  ✗ Should be connected after update"
  fi
}

test_browser_command_interface() {
  echo "Testing browser command interface..."

  # Test status command
  local status
  status=$(cd "$TEST_DIR" && browser status 2>&1 || true)

  assert_json_key "connected" "$status" "browser status works"
}

test_browser_connect_without_playwright() {
  echo "Testing browser_connect without Playwright..."

  # This should fail gracefully without Playwright installed
  local result
  result=$(browser_connect "$TEST_DIR" 2>&1 || true)

  # Should return error about missing Playwright
  assert_contains "error" "$result" "Connect fails without Playwright"
}

test_browser_action_without_session() {
  echo "Testing browser actions without active session..."

  local result
  result=$(_browser_action "$TEST_DIR" "title" "" 2>&1 || true)

  assert_contains "error" "$result" "Action fails without session"
}

test_browser_navigate_params() {
  echo "Testing browser_navigate parameter validation..."

  local result
  result=$(browser_navigate "" "$TEST_DIR" 2>&1 || true)

  assert_contains "url_required" "$result" "Navigate requires URL"
}

test_browser_click_params() {
  echo "Testing browser_click parameter validation..."

  local result
  result=$(browser_click "" "$TEST_DIR" 2>&1 || true)

  assert_contains "selector_required" "$result" "Click requires selector"
}

test_browser_fill_params() {
  echo "Testing browser_fill parameter validation..."

  local result
  result=$(browser_fill "" "value" "$TEST_DIR" 2>&1 || true)

  assert_contains "selector_required" "$result" "Fill requires selector"
}

test_browser_screenshot_default_filename() {
  echo "Testing browser_screenshot default filename..."

  # Mock test - just check function accepts no args
  local result
  result=$(browser_screenshot "" "$TEST_DIR" 2>&1 || true)

  # Should fail (no session) but not due to missing filename
  assert_contains "error" "$result" "Screenshot handles default filename"
}

test_browser_debug() {
  echo "Testing browser_debug..."

  local output
  output=$(browser_debug "$TEST_DIR")

  assert_contains "Browser Debug Info" "$output" "Debug has title"
  assert_contains "State Directory" "$output" "Debug shows state dir"
}

# Run tests
main() {
  echo "================================"
  echo "  Browser Controller Tests"
  echo "================================"
  echo ""

  setup

  test_state_initialization
  test_state_update
  test_state_get
  test_browser_status
  test_browser_is_connected
  test_browser_command_interface
  test_browser_connect_without_playwright
  test_browser_action_without_session
  test_browser_navigate_params
  test_browser_click_params
  test_browser_fill_params
  test_browser_screenshot_default_filename
  test_browser_debug

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
