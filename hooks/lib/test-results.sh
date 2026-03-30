#!/usr/bin/env bash
# test-results.sh — test-runner result parsers and summaries

set -euo pipefail

# ============================================================================
# 테스트 출력 파싱
# Usage: parse_test_output <framework> <project_root> <exit_code>
# Returns: JSON with test results
# ============================================================================
parse_test_output() {
  local framework="${1:-}"
  local project_root="${2:-}"
  local exit_code="${3:-0}"

  case "$framework" in
    jest)
      parse_jest_output "$project_root" "$exit_code"
      ;;
    vitest)
      parse_vitest_output "$project_root" "$exit_code"
      ;;
    pytest)
      parse_pytest_output "$project_root" "$exit_code"
      ;;
    go_test)
      parse_go_test_output "$project_root" "$exit_code"
      ;;
    cargo_test)
      parse_cargo_test_output "$project_root" "$exit_code"
      ;;
    maven | gradle)
      parse_java_test_output "$project_root" "$framework" "$exit_code"
      ;;
    *)
      parse_generic_output "$project_root" "$exit_code"
      ;;
  esac
}

parse_jest_output() {
  local project_root="${1:-}"
  local exit_code="${2:-0}"
  local results_file="${project_root}/test-results.json"

  if [[ ! -f "$results_file" ]]; then
    jq -n --argjson exit "$exit_code" \
      '{"framework": "jest", "passed": 0, "failed": (if $exit != 0 then 1 else 0 end), "skipped": 0, "total": 1, "exit_code": $exit}'
    return 0
  fi

  local passed failed skipped total duration_ms assertion_results test_results

  passed=$(jq -r '.numPassedTests // 0' "$results_file" 2> /dev/null) || passed=""
  failed=$(jq -r '.numFailedTests // 0' "$results_file" 2> /dev/null) || failed=""
  skipped=$(jq -r '(.numPendingTests // 0) + (.numTodoTests // 0)' "$results_file" 2> /dev/null) || skipped=""
  total=$(jq -r '.numTotalTests // 0' "$results_file" 2> /dev/null) || total=""
  duration_ms=$(jq -r '(.testResults[0].perfStats.runtime // 0) * 1000' "$results_file" 2> /dev/null) || duration_ms=""
  assertion_results=$(jq -c '.testResults[0].assertionResults // []' "$results_file" 2> /dev/null) || assertion_results=""

  if [[ -n "$assertion_results" ]]; then
    test_results=$(printf '%s\n' "$assertion_results" | jq -c '.[0:10]' 2> /dev/null) || test_results=""
  else
    test_results=""
  fi

  if [[ -z "$passed" || -z "$failed" || -z "$skipped" || -z "$total" || -z "$duration_ms" || -z "$test_results" ]]; then
    jq -n --argjson exit "$exit_code" \
      '{"framework": "jest", "passed": 0, "failed": 1, "skipped": 0, "total": 1, "exit_code": $exit, "error": "parse_error"}'
    return 0
  fi

  jq -n \
    --argjson passed "$passed" \
    --argjson failed "$failed" \
    --argjson skipped "$skipped" \
    --argjson total "$total" \
    --argjson exit "$exit_code" \
    --argjson duration "$duration_ms" \
    --argjson test_results "$test_results" \
    '{
      framework: "jest",
      passed: $passed,
      failed: $failed,
      skipped: $skipped,
      total: $total,
      exit_code: $exit,
      duration_ms: $duration,
      test_results: $test_results
    }'
}

parse_vitest_output() {
  local project_root="${1:-}"
  local exit_code="${2:-0}"
  local results_file="${project_root}/test-results.json"

  if [[ ! -f "$results_file" ]]; then
    jq -n --argjson exit "$exit_code" \
      '{"framework": "vitest", "passed": 0, "failed": (if $exit != 0 then 1 else 0 end), "skipped": 0, "total": 1, "exit_code": $exit}'
    return 0
  fi

  jq '{
    framework: "vitest",
    passed: (.numPassedTests // (.testResults // [] | map(select(.status == "passed")) | length)),
    failed: (.numFailedTests // (.testResults // [] | map(select(.status == "failed")) | length)),
    skipped: ((.numPendingTests // 0) + (.numTodoTests // 0) + (.testResults // [] | map(select(.status == "skipped")) | length)),
    total: (.numTotalTests // (.testResults // [] | length)),
    exit_code: '"$exit_code"'
  }' "$results_file" 2> /dev/null \
    || jq -n --argjson exit "$exit_code" \
      '{"framework": "vitest", "passed": 0, "failed": 1, "skipped": 0, "total": 1, "exit_code": $exit}'
}

parse_pytest_output() {
  local project_root="${1:-}"
  local exit_code="${2:-0}"
  local results_file="${project_root}/test-results.json"

  if [[ ! -f "$results_file" ]]; then
    local output_file="${project_root}/test-output.txt"
    if [[ -f "$output_file" ]]; then
      local passed failed skipped
      passed=$(grep -c "PASSED" "$output_file" 2> /dev/null || echo 0)
      failed=$(grep -c "FAILED" "$output_file" 2> /dev/null || echo 0)
      skipped=$(grep -c "SKIPPED" "$output_file" 2> /dev/null || echo 0)
      local total=$((passed + failed + skipped))

      jq -n --argjson p "$passed" --argjson f "$failed" --argjson s "$skipped" --argjson t "$total" --argjson e "$exit_code" \
        '{"framework": "pytest", "passed": $p, "failed": $f, "skipped": $s, "total": $t, "exit_code": $e}'
      return 0
    fi

    jq -n --argjson exit "$exit_code" \
      '{"framework": "pytest", "passed": 0, "failed": (if $exit != 0 then 1 else 0 end), "skipped": 0, "total": 1, "exit_code": $exit}'
    return 0
  fi

  jq '{
    framework: "pytest",
    passed: (.summary.passed // 0),
    failed: (.summary.failed // 0),
    skipped: (.summary.skipped // 0) + (.summary.xfailed // 0),
    total: (.summary.total // 0),
    exit_code: '"$exit_code"',
    duration_s: (.duration // 0)
  }' "$results_file" 2> /dev/null \
    || jq -n --argjson exit "$exit_code" \
      '{"framework": "pytest", "passed": 0, "failed": 1, "skipped": 0, "total": 1, "exit_code": $exit}'
}

parse_go_test_output() {
  local project_root="${1:-}"
  local exit_code="${2:-0}"
  local results_file="${project_root}/test-results.json"

  if [[ ! -f "$results_file" ]]; then
    jq -n --argjson exit "$exit_code" \
      '{"framework": "go_test", "passed": 0, "failed": (if $exit != 0 then 1 else 0 end), "skipped": 0, "total": 1, "exit_code": $exit}'
    return 0
  fi

  local passed failed skipped total
  passed=$(grep -c '"Action":"pass"' "$results_file" 2> /dev/null || echo 0)
  failed=$(grep -c '"Action":"fail"' "$results_file" 2> /dev/null || echo 0)
  skipped=$(grep -c '"Action":"skip"' "$results_file" 2> /dev/null || echo 0)
  total=$((passed + failed + skipped))

  jq -n --argjson p "$passed" --argjson f "$failed" --argjson s "$skipped" --argjson t "$total" --argjson e "$exit_code" \
    '{"framework": "go_test", "passed": $p, "failed": $f, "skipped": $s, "total": $t, "exit_code": $e}'
}

parse_cargo_test_output() {
  local project_root="${1:-}"
  local exit_code="${2:-0}"
  local results_file="${project_root}/test-results.json"

  if [[ ! -f "$results_file" ]]; then
    jq -n --argjson exit "$exit_code" \
      '{"framework": "cargo_test", "passed": 0, "failed": (if $exit != 0 then 1 else 0 end), "skipped": 0, "total": 1, "exit_code": $exit}'
    return 0
  fi

  local passed failed ignored total
  passed=$(grep -c '"test.*ok"' "$results_file" 2> /dev/null || echo 0)
  failed=$(grep -c '"test.*FAILED"' "$results_file" 2> /dev/null || echo 0)
  ignored=$(grep -c '"test.*ignored"' "$results_file" 2> /dev/null || echo 0)
  total=$((passed + failed + ignored))

  jq -n --argjson p "$passed" --argjson f "$failed" --argjson i "$ignored" --argjson t "$total" --argjson e "$exit_code" \
    '{"framework": "cargo_test", "passed": $p, "failed": $f, "skipped": $i, "total": $t, "exit_code": $e}'
}

parse_java_test_output() {
  local project_root="${1:-}"
  local framework="${2:-maven}"
  local exit_code="${3:-0}"

  local report_dir
  if [[ "$framework" == "maven" ]]; then
    report_dir="${project_root}/target/surefire-reports"
  else
    report_dir="${project_root}/build/test-results/test"
  fi

  if [[ -d "$report_dir" ]]; then
    local test_files
    test_files=$(find "$report_dir" -name "TEST-*.xml" 2> /dev/null | head -20)

    if [[ -n "$test_files" ]]; then
      local passed failed skipped total
      passed=0
      failed=0
      skipped=0

      while IFS= read -r file; do
        passed=$((passed + $(grep -o 'tests="[0-9]*"' "$file" 2> /dev/null | head -1 | grep -o '[0-9]*' || echo 0)))
        failed=$((failed + $(grep -o 'failures="[0-9]*"' "$file" 2> /dev/null | head -1 | grep -o '[0-9]*' || echo 0)))
        skipped=$((skipped + $(grep -o 'skipped="[0-9]*"' "$file" 2> /dev/null | head -1 | grep -o '[0-9]*' || echo 0)))
      done <<< "$test_files"

      total=$((passed + failed + skipped))

      jq -n --arg fw "$framework" --argjson p "$passed" --argjson f "$failed" --argjson s "$skipped" --argjson t "$total" --argjson e "$exit_code" \
        '{"framework": $fw, "passed": $p, "failed": $f, "skipped": $s, "total": $t, "exit_code": $e}'
      return 0
    fi
  fi

  jq -n --arg fw "$framework" --argjson exit "$exit_code" \
    '{"framework": $fw, "passed": 0, "failed": (if $exit != 0 then 1 else 0 end), "skipped": 0, "total": 1, "exit_code": $exit}'
}

parse_generic_output() {
  local project_root="${1:-}"
  local exit_code="${2:-0}"

  jq -n --argjson exit "$exit_code" \
    '{"framework": "unknown", "passed": (if $exit == 0 then 1 else 0 end), "failed": (if $exit != 0 then 1 else 0 end), "skipped": 0, "total": 1, "exit_code": $exit}'
}

summarize_test_results() {
  local results="${1:-}"

  local framework passed failed skipped total exit_code
  framework=$(echo "$results" | jq -r '.framework // "unknown"')
  passed=$(echo "$results" | jq -r '.passed // 0')
  failed=$(echo "$results" | jq -r '.failed // 0')
  skipped=$(echo "$results" | jq -r '.skipped // 0')
  total=$(echo "$results" | jq -r '.total // 0')
  exit_code=$(echo "$results" | jq -r '.exit_code // 0')

  local status_icon="✅"
  if [[ "$failed" -gt 0 ]]; then
    status_icon="❌"
  elif [[ "$total" -eq 0 ]]; then
    status_icon="⚠️"
  fi

  echo "📊 Test Results Summary"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "Framework: $framework"
  echo "Status: $status_icon"
  echo ""
  echo "Total:   $total"
  echo "Passed:  $passed"
  echo "Failed:  $failed"
  echo "Skipped: $skipped"
  echo ""

  if [[ "$failed" -gt 0 ]]; then
    echo "⚠️  Some tests failed. Review the output above."
    return 1
  elif [[ "$total" -eq 0 ]]; then
    echo "⚠️  No tests were found or executed."
    return 1
  else
    echo "✅ All tests passed!"
    return 0
  fi
}

check_test_success_rate() {
  local results="${1:-}"
  local threshold="${2:-0.9}"

  local passed failed total
  passed=$(echo "$results" | jq -r '.passed // 0')
  failed=$(echo "$results" | jq -r '.failed // 0')
  total=$((passed + failed))

  if [[ "$total" -eq 0 ]]; then
    echo "false"
    return 1
  fi

  local success_rate
  success_rate=$(awk "BEGIN {printf \"%.2f\", $passed / $total}")

  if awk "BEGIN {exit !($success_rate >= $threshold)}"; then
    echo "true"
    return 0
  fi

  echo "false"
  return 1
}
