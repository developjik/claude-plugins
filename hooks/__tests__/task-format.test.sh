#!/usr/bin/env bash
# task-format.test.sh — Hybrid Task Format Tests

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"

source "${LIB_DIR}/task-format.sh"
set +e

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

# Setup test files
setup() {
  TEST_DIR=$(mktemp -d)
  mkdir -p "${TEST_DIR}/tasks"

  # Create test XML task
  cat > "${TEST_DIR}/tasks/001.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<task id="001" wave="1" depends="" type="implementation" priority="high">
  <title>Create login endpoint</title>
  <description>
    Implement the authentication login endpoint with JWT support.
  </description>
  <files>
    <file>src/auth/login.ts</file>
    <file>src/auth/types.ts</file>
  </files>
  <requirements>
    - Use jose for JWT (not jsonwebtoken)
    - Validate credentials against users table
    - Return httpOnly cookie on success
    - Rate limit: 5 requests per minute per IP
  </requirements>
  <action>
    1. Install jose package
    2. Create LoginRequest and LoginResponse types
    3. Implement POST /auth/login endpoint
    4. Add rate limiting middleware
  </action>
  <acceptance_criteria>
    - curl POST /auth/login returns 200 + Set-Cookie with valid credentials
    - curl POST /auth/login returns 401 with invalid credentials
    - Rate limiting blocks after 5 requests
  </acceptance_criteria>
  <verify>
    npm run test -- auth.test.ts
    npm run lint
  </verify>
  <done>
    - Login endpoint working
    - Tests passing
    - Lint clean
  </done>
</task>
EOF

  # Create test MD task
  cat > "${TEST_DIR}/tasks/002.md" << 'EOF'
# Task 002: Create registration endpoint

**Wave:** 2
**Type:** implementation
**Priority:** medium
**Depends:** 001

## Description

Implement the user registration endpoint with email verification.

## Files

- `src/auth/register.ts`
- `src/auth/email.ts`

## Requirements

- Validate email format
- Hash password with bcrypt
- Send verification email
- Store user in database

## Action

```bash
# Implementation steps
1. Create RegisterRequest and RegisterResponse types
2. Implement POST /auth/register endpoint
3. Add email verification service
4. Create user repository methods
```

## Acceptance Criteria

- Valid registration returns 201 with user ID
- Duplicate email returns 409
- Verification email sent successfully

## Verify

```bash
npm run test -- register.test.ts
npm run lint
```

## Done

- Registration endpoint working
- Email verification working
- Tests passing

## Notes

- Consider rate limiting for registration
- May need CAPTCHA for production
EOF
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Tests
test_detect_format() {
  echo "Testing format detection..."

  local xml_format md_format
  xml_format=$(detect_task_format "${TEST_DIR}/tasks/001.xml")
  md_format=$(detect_task_format "${TEST_DIR}/tasks/002.md")

  assert_equals "xml" "$xml_format" "Detect XML format"
  assert_equals "md" "$md_format" "Detect Markdown format"
}

test_xml_validation() {
  echo "Testing XML validation..."

  local result
  result=$(validate_task_xml "${TEST_DIR}/tasks/001.xml")

  assert_contains '"valid": true' "$result" "Valid XML task passes validation"
}

test_xml_to_md() {
  echo "Testing XML to Markdown conversion..."

  local output="${TEST_DIR}/tasks/001_converted.md"
  xml_to_md "${TEST_DIR}/tasks/001.xml" "$output"

  assert_equals "0" "$?" "Conversion succeeds"
  assert_contains "# Task 001" "$(cat "$output")" "Title in converted MD"
  assert_contains "Create login endpoint" "$(cat "$output")" "Description in converted MD"
  assert_contains "src/auth/login.ts" "$(cat "$output")" "Files in converted MD"
}

test_md_to_xml() {
  echo "Testing Markdown to XML conversion..."

  local output="${TEST_DIR}/tasks/002_converted.xml"
  md_to_xml "${TEST_DIR}/tasks/002.md" "$output"

  assert_equals "0" "$?" "Conversion succeeds"
  assert_contains '<task id="002"' "$(cat "$output")" "Task element with ID"
  assert_contains "Create registration endpoint" "$(cat "$output")" "Title in converted XML"
  assert_contains "src/auth/register.ts" "$(cat "$output")" "Files in converted XML"
}

test_parse_xml_task() {
  echo "Testing XML task parsing..."

  local json
  json=$(parse_xml_task "${TEST_DIR}/tasks/001.xml")

  assert_equals "001" "$(echo "$json" | jq -r '.id')" "Parse task ID"
  assert_equals "1" "$(echo "$json" | jq -r '.wave')" "Parse wave number"
  assert_equals "Create login endpoint" "$(echo "$json" | jq -r '.title')" "Parse title"
  assert_equals "high" "$(echo "$json" | jq -r '.priority')" "Parse priority"
  assert_equals "2" "$(echo "$json" | jq -r '.files | length')" "Parse files count"
}

test_parse_md_task() {
  echo "Testing Markdown task parsing..."

  local json
  json=$(parse_md_task "${TEST_DIR}/tasks/002.md")

  assert_equals "002" "$(echo "$json" | jq -r '.id')" "Parse task ID"
  assert_equals "2" "$(echo "$json" | jq -r '.wave')" "Parse wave number"
  assert_equals "Create registration endpoint" "$(echo "$json" | jq -r '.title')" "Parse title"
  assert_equals "medium" "$(echo "$json" | jq -r '.priority')" "Parse priority"
  assert_equals "001" "$(echo "$json" | jq -r '.depends')" "Parse depends"
}

test_roundtrip_xml() {
  echo "Testing XML roundtrip (XML -> MD -> XML)..."

  local original="${TEST_DIR}/tasks/001.xml"
  local md_temp="${TEST_DIR}/tasks/001_temp.md"
  local xml_final="${TEST_DIR}/tasks/001_final.xml"

  xml_to_md "$original" "$md_temp"
  md_to_xml "$md_temp" "$xml_final"

  # Compare key fields
  local orig_title final_title
  orig_title=$(parse_xml_task "$original" | jq -r '.title')
  final_title=$(parse_xml_task "$xml_final" | jq -r '.title')

  assert_equals "$orig_title" "$final_title" "Title preserved in roundtrip"
}

test_roundtrip_md() {
  echo "Testing MD roundtrip (MD -> XML -> MD)..."

  local original="${TEST_DIR}/tasks/002.md"
  local xml_temp="${TEST_DIR}/tasks/002_temp.xml"
  local md_final="${TEST_DIR}/tasks/002_final.md"

  md_to_xml "$original" "$xml_temp"
  xml_to_md "$xml_temp" "$md_final"

  # Compare key fields
  local orig_title final_title
  orig_title=$(parse_md_task "$original" | jq -r '.title')
  final_title=$(parse_md_task "$md_final" | jq -r '.title')

  assert_equals "$orig_title" "$final_title" "Title preserved in roundtrip"
}

# Run tests
main() {
  echo "================================"
  echo "  Task Format Conversion Tests"
  echo "================================"
  echo ""

  setup

  test_detect_format
  test_xml_validation
  test_xml_to_md
  test_md_to_xml
  test_parse_xml_task
  test_parse_md_task
  test_roundtrip_xml
  test_roundtrip_md

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
