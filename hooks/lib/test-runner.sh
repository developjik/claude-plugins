#!/usr/bin/env bash
# test-runner.sh — 테스트 실행 및 결과 분석 라이브러리
# P0-1: 테스트 실행 통합
#
# DEPENDENCIES: json-utils.sh, logging.sh
#
# 지원 프레임워크:
# - JavaScript: jest, vitest, mocha
# - Python: pytest, unittest
# - Go: go test
# - Rust: cargo test
# - Java: maven, gradle
# - Ruby: rspec

set -euo pipefail

# ============================================================================
# 상수
# ============================================================================

readonly TEST_RESULTS_DIR=".harness/test-results"
readonly TEST_TIMEOUT=300  # 5분
readonly MAX_TEST_RETRIES=2

# ============================================================================
# 테스트 프레임워크 감지
# Usage: detect_test_framework <project_root>
# Returns: jest|vitest|mocha|pytest|unittest|go_test|cargo_test|maven|gradle|rspec|none
# ============================================================================
detect_test_framework() {
  local project_root="${1:-}"

  # JavaScript/TypeScript
  if [[ -f "${project_root}/package.json" ]]; then
    if grep -qE '"(jest|@types/jest)"' "${project_root}/package.json" 2>/dev/null; then
      echo "jest"
      return 0
    fi
    if grep -qE '"vitest"' "${project_root}/package.json" 2>/dev/null; then
      echo "vitest"
      return 0
    fi
    if grep -qE '"mocha"' "${project_root}/package.json" 2>/dev/null; then
      echo "mocha"
      return 0
    fi
    # vitest.config.* 파일 확인
    if ls "${project_root}"/vitest.config.* 1>/dev/null 2>&1; then
      echo "vitest"
      return 0
    fi
    # jest.config.* 파일 확인
    if ls "${project_root}"/jest.config.* 1>/dev/null 2>&1; then
      echo "jest"
      return 0
    fi
  fi

  # Python
  if [[ -f "${project_root}/pytest.ini" ]] || \
     [[ -f "${project_root}/pyproject.toml" ]] || \
     grep -qE "pytest" "${project_root}/requirements*.txt" 2>/dev/null || \
     grep -qE '"pytest"' "${project_root}/pyproject.toml" 2>/dev/null; then
    echo "pytest"
    return 0
  fi

  if [[ -f "${project_root}/setup.cfg" ]] && \
     grep -qE "\[tool:pytest\]" "${project_root}/setup.cfg" 2>/dev/null; then
    echo "pytest"
    return 0
  fi

  # Python unittest (기본)
  if ls "${project_root}"/test_*.py 1>/dev/null 2>&1 || \
     ls "${project_root}"/tests/test_*.py 1>/dev/null 2>&1; then
    echo "unittest"
    return 0
  fi

  # Go
  if [[ -f "${project_root}/go.mod" ]]; then
    echo "go_test"
    return 0
  fi

  # Rust
  if [[ -f "${project_root}/Cargo.toml" ]]; then
    echo "cargo_test"
    return 0
  fi

  # Java - Maven
  if [[ -f "${project_root}/pom.xml" ]]; then
    echo "maven"
    return 0
  fi

  # Java - Gradle
  if [[ -f "${project_root}/build.gradle" ]] || \
     [[ -f "${project_root}/build.gradle.kts" ]]; then
    echo "gradle"
    return 0
  fi

  # Ruby
  if [[ -f "${project_root}/Gemfile" ]] && \
     grep -qE "rspec" "${project_root}/Gemfile" 2>/dev/null; then
    echo "rspec"
    return 0
  fi

  echo "none"
}

# ============================================================================
# 테스트 실행 명령 생성
# Usage: get_test_command <framework> <project_root> [test_filter]
# Returns: 테스트 실행 명령어
# ============================================================================
get_test_command() {
  local framework="${1:-}"
  local project_root="${2:-}"
  local test_filter="${3:-}"

  case "$framework" in
    jest)
      if [[ -n "$test_filter" ]]; then
        echo "cd '$project_root' && npm test -- --testNamePattern='$test_filter' --json --outputFile=test-results.json"
      else
        echo "cd '$project_root' && npm test -- --json --outputFile=test-results.json"
      fi
      ;;
    vitest)
      if [[ -n "$test_filter" ]]; then
        echo "cd '$project_root' && npx vitest run --reporter=json --filter='$test_filter' > test-results.json"
      else
        echo "cd '$project_root' && npx vitest run --reporter=json > test-results.json"
      fi
      ;;
    mocha)
      if [[ -n "$test_filter" ]]; then
        echo "cd '$project_root' && npm test -- --grep='$test_filter' --reporter json > test-results.json"
      else
        echo "cd '$project_root' && npm test -- --reporter json > test-results.json"
      fi
      ;;
    pytest)
      if [[ -n "$test_filter" ]]; then
        echo "cd '$project_root' && python -m pytest -k '$test_filter' --json-report --json-report-file=test-results.json -q"
      else
        echo "cd '$project_root' && python -m pytest --json-report --json-report-file=test-results.json -q"
      fi
      ;;
    unittest)
      if [[ -n "$test_filter" ]]; then
        echo "cd '$project_root' && python -m unittest $test_filter -v 2>&1 | tee test-output.txt"
      else
        echo "cd '$project_root' && python -m unittest discover -v 2>&1 | tee test-output.txt"
      fi
      ;;
    go_test)
      if [[ -n "$test_filter" ]]; then
        echo "cd '$project_root' && go test -v -run '$test_filter' ./... -json > test-results.json"
      else
        echo "cd '$project_root' && go test -v ./... -json > test-results.json"
      fi
      ;;
    cargo_test)
      if [[ -n "$test_filter" ]]; then
        echo "cd '$project_root' && cargo test '$test_filter' --message-format=json > test-results.json"
      else
        echo "cd '$project_root' && cargo test --message-format=json > test-results.json"
      fi
      ;;
    maven)
      if [[ -n "$test_filter" ]]; then
        echo "cd '$project_root' && mvn test -Dtest='$test_filter' -DfailIfNoTests=false"
      else
        echo "cd '$project_root' && mvn test -DfailIfNoTests=false"
      fi
      ;;
    gradle)
      if [[ -n "$test_filter" ]]; then
        echo "cd '$project_root' && ./gradlew test --tests '$test_filter'"
      else
        echo "cd '$project_root' && ./gradlew test"
      fi
      ;;
    rspec)
      if [[ -n "$test_filter" ]]; then
        echo "cd '$project_root' && bundle exec rspec --format json --out test-results.json -e '$test_filter'"
      else
        echo "cd '$project_root' && bundle exec rspec --format json --out test-results.json"
      fi
      ;;
    *)
      echo ""
      ;;
  esac
}

# ============================================================================
# 테스트 실행
# Usage: run_tests <project_root> [test_filter] [test_type]
# Returns: JSON with pass/fail/skip counts
# ============================================================================
run_tests() {
  local project_root="${1:-}"
  local test_filter="${2:-}"
  local test_type="${3:-all}"  # all, unit, integration, e2e

  local framework
  framework=$(detect_test_framework "$project_root")

  if [[ "$framework" == "none" ]]; then
    echo '{"error": "no_test_framework", "framework": "none", "passed": 0, "failed": 0, "skipped": 0, "total": 0}'
    return 1
  fi

  # 결과 디렉토리 생성
  local results_dir="${project_root}/${TEST_RESULTS_DIR}"
  mkdir -p "$results_dir"

  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)
  local results_file="${results_dir}/${timestamp}.json"

  # 테스트 명령어 생성
  local test_cmd
  test_cmd=$(get_test_command "$framework" "$project_root" "$test_filter")

  if [[ -z "$test_cmd" ]]; then
    echo '{"error": "unsupported_framework", "framework": "'"$framework"'"}'
    return 1
  fi

  # 로그 기록
  if declare -f log_event &>/dev/null; then
    log_event "$project_root" "INFO" "test_start" "Starting tests" \
      "\"framework\":\"$framework\",\"filter\":\"$test_filter\""
  fi

  # 테스트 실행 (타임아웃 적용)
  local exit_code=0
  if ! timeout "$TEST_TIMEOUT" bash -c "$test_cmd" 2>&1; then
    exit_code=$?
  fi

  # 결과 파싱
  local results
  results=$(parse_test_output "$framework" "$project_root" "$exit_code")

  # 결과 저장
  echo "$results" > "$results_file"

  # 로그 기록
  local passed failed skipped total
  passed=$(echo "$results" | jq -r '.passed // 0')
  failed=$(echo "$results" | jq -r '.failed // 0')
  total=$(echo "$results" | jq -r '.total // 0')

  if declare -f log_event &>/dev/null; then
    log_event "$project_root" "INFO" "test_complete" "Tests completed" \
      "\"framework\":\"$framework\",\"passed\":$passed,\"failed\":$failed,\"total\":$total"
  fi

  echo "$results"
}

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
    maven|gradle)
      parse_java_test_output "$project_root" "$framework" "$exit_code"
      ;;
    *)
      # 일반적인 출력 파싱
      parse_generic_output "$project_root" "$exit_code"
      ;;
  esac
}

# ============================================================================
# Jest 출력 파싱
# ============================================================================
parse_jest_output() {
  local project_root="${1:-}"
  local exit_code="${2:-0}"
  local results_file="${project_root}/test-results.json"

  if [[ ! -f "$results_file" ]]; then
    # JSON 파일이 없으면 기본값 반환
    jq -n --argjson exit "$exit_code" \
      '{"framework": "jest", "passed": 0, "failed": (if $exit != 0 then 1 else 0 end), "skipped": 0, "total": 1, "exit_code": $exit}'
    return 0
  fi

  jq '{
    framework: "jest",
    passed: .numPassedTests // 0,
    failed: .numFailedTests // 0,
    skipped: (.numPendingTests // 0) + (.numTodoTests // 0),
    total: .numTotalTests // 0,
    exit_code: '"$exit_code"',
    duration_ms: (.testResults[0].perfStats.runtime // 0) * 1000,
    test_results: .testResults[0].assertionResults[:10]
  }' "$results_file" 2>/dev/null || \
  jq -n --argjson exit "$exit_code" \
    '{"framework": "jest", "passed": 0, "failed": 1, "skipped": 0, "total": 1, "exit_code": $exit, "error": "parse_error"}'
}

# ============================================================================
# Vitest 출력 파싱
# ============================================================================
parse_vitest_output() {
  local project_root="${1:-}"
  local exit_code="${2:-0}"
  local results_file="${project_root}/test-results.json"

  if [[ ! -f "$results_file" ]]; then
    jq -n --argjson exit "$exit_code" \
      '{"framework": "vitest", "passed": 0, "failed": (if $exit != 0 then 1 else 0 end), "skipped": 0, "total": 1, "exit_code": $exit}'
    return 0
  fi

  # Vitest JSON 형식 파싱
  jq '{
    framework: "vitest",
    passed: (.testResults // [] | map(select(.status == "passed")) | length),
    failed: (.testResults // [] | map(select(.status == "failed")) | length),
    skipped: (.testResults // [] | map(select(.status == "skipped")) | length),
    total: (.testResults // [] | length),
    exit_code: '"$exit_code"'
  }' "$results_file" 2>/dev/null || \
  jq -n --argjson exit "$exit_code" \
    '{"framework": "vitest", "passed": 0, "failed": 1, "skipped": 0, "total": 1, "exit_code": $exit}'
}

# ============================================================================
# Pytest 출력 파싱
# ============================================================================
parse_pytest_output() {
  local project_root="${1:-}"
  local exit_code="${2:-0}"
  local results_file="${project_root}/test-results.json"

  if [[ ! -f "$results_file" ]]; then
    # pytest-json-report가 없으면 일반 출력에서 파싱 시도
    local output_file="${project_root}/test-output.txt"
    if [[ -f "$output_file" ]]; then
      local passed failed skipped
      passed=$(grep -c "PASSED" "$output_file" 2>/dev/null || echo 0)
      failed=$(grep -c "FAILED" "$output_file" 2>/dev/null || echo 0)
      skipped=$(grep -c "SKIPPED" "$output_file" 2>/dev/null || echo 0)
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
  }' "$results_file" 2>/dev/null || \
  jq -n --argjson exit "$exit_code" \
    '{"framework": "pytest", "passed": 0, "failed": 1, "skipped": 0, "total": 1, "exit_code": $exit}'
}

# ============================================================================
# Go Test 출력 파싱
# ============================================================================
parse_go_test_output() {
  local project_root="${1:-}"
  local exit_code="${2:-0}"
  local results_file="${project_root}/test-results.json"

  if [[ ! -f "$results_file" ]]; then
    jq -n --argjson exit "$exit_code" \
      '{"framework": "go_test", "passed": 0, "failed": (if $exit != 0 then 1 else 0 end), "skipped": 0, "total": 1, "exit_code": $exit}'
    return 0
  fi

  # go test -json 출력 파싱
  local passed failed skipped total
  passed=$(grep -c '"Action":"pass"' "$results_file" 2>/dev/null || echo 0)
  failed=$(grep -c '"Action":"fail"' "$results_file" 2>/dev/null || echo 0)
  skipped=$(grep -c '"Action":"skip"' "$results_file" 2>/dev/null || echo 0)
  total=$((passed + failed + skipped))

  jq -n --argjson p "$passed" --argjson f "$failed" --argjson s "$skipped" --argjson t "$total" --argjson e "$exit_code" \
    '{"framework": "go_test", "passed": $p, "failed": $f, "skipped": $s, "total": $t, "exit_code": $e}'
}

# ============================================================================
# Cargo Test 출력 파싱
# ============================================================================
parse_cargo_test_output() {
  local project_root="${1:-}"
  local exit_code="${2:-0}"
  local results_file="${project_root}/test-results.json"

  if [[ ! -f "$results_file" ]]; then
    jq -n --argjson exit "$exit_code" \
      '{"framework": "cargo_test", "passed": 0, "failed": (if $exit != 0 then 1 else 0 end), "skipped": 0, "total": 1, "exit_code": $exit}'
    return 0
  fi

  # cargo test --message-format=json 파싱
  local passed failed ignored total
  passed=$(grep -c '"test.*ok"' "$results_file" 2>/dev/null || echo 0)
  failed=$(grep -c '"test.*FAILED"' "$results_file" 2>/dev/null || echo 0)
  ignored=$(grep -c '"test.*ignored"' "$results_file" 2>/dev/null || echo 0)
  total=$((passed + failed + ignored))

  jq -n --argjson p "$passed" --argjson f "$failed" --argjson i "$ignored" --argjson t "$total" --argjson e "$exit_code" \
    '{"framework": "cargo_test", "passed": $p, "failed": $f, "skipped": $i, "total": $t, "exit_code": $e}'
}

# ============================================================================
# Java Test (Maven/Gradle) 출력 파싱
# ============================================================================
parse_java_test_output() {
  local project_root="${1:-}"
  local framework="${2:-maven}"
  local exit_code="${3:-0}"

  # Java 테스트는 XML 리포트에서 파싱
  local report_dir
  if [[ "$framework" == "maven" ]]; then
    report_dir="${project_root}/target/surefire-reports"
  else
    report_dir="${project_root}/build/test-results/test"
  fi

  if [[ -d "$report_dir" ]]; then
    local test_files
    test_files=$(find "$report_dir" -name "TEST-*.xml" 2>/dev/null | head -20)

    if [[ -n "$test_files" ]]; then
      local passed failed skipped total
      passed=0
      failed=0
      skipped=0

      while IFS= read -r file; do
        passed=$((passed + $(grep -o 'tests="[0-9]*"' "$file" 2>/dev/null | head -1 | grep -o '[0-9]*' || echo 0)))
        failed=$((failed + $(grep -o 'failures="[0-9]*"' "$file" 2>/dev/null | head -1 | grep -o '[0-9]*' || echo 0)))
        skipped=$((skipped + $(grep -o 'skipped="[0-9]*"' "$file" 2>/dev/null | head -1 | grep -o '[0-9]*' || echo 0)))
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

# ============================================================================
# 일반 출력 파싱
# ============================================================================
parse_generic_output() {
  local project_root="${1:-}"
  local exit_code="${2:-0}"

  jq -n --argjson exit "$exit_code" \
    '{"framework": "unknown", "passed": (if $exit == 0 then 1 else 0 end), "failed": (if $exit != 0 then 1 else 0 end), "skipped": 0, "total": 1, "exit_code": $exit}'
}

# ============================================================================
# 커버리지 리포트 생성
# Usage: generate_coverage_report <project_root>
# Returns: JSON with coverage percentage
# ============================================================================
generate_coverage_report() {
  local project_root="${1:-}"
  local framework
  framework=$(detect_test_framework "$project_root")

  local coverage_file="${project_root}/${TEST_RESULTS_DIR}/coverage.json"

  case "$framework" in
    jest)
      if npm run test:coverage --prefix "$project_root" -- --reporter=json-summary --reporter=text 2>/dev/null; then
        if [[ -f "${project_root}/coverage/coverage-summary.json" ]]; then
          jq '.total.lines.pct' "${project_root}/coverage/coverage-summary.json" > "$coverage_file"
        fi
      fi
      ;;
    vitest)
      if npx vitest run --coverage --coverage.reporter=json --prefix "$project_root" 2>/dev/null; then
        if [[ -f "${project_root}/coverage/coverage-final.json" ]]; then
          # 평균 커버리지 계산
          jq '[.[]?.l] | add / length' "${project_root}/coverage/coverage-final.json" > "$coverage_file" 2>/dev/null || true
        fi
      fi
      ;;
    pytest)
      if python -m pytest --cov --cov-report=json --prefix "$project_root" 2>/dev/null; then
        if [[ -f "${project_root}/coverage.json" ]]; then
          jq '.totals.percent_covered' "${project_root}/coverage.json" > "$coverage_file"
        fi
      fi
      ;;
    go_test)
      if go test -coverprofile=coverage.out ./... --prefix "$project_root" 2>/dev/null; then
        go tool cover -func=coverage.out | tail -1 | awk '{print $3}' | tr -d '%' > "$coverage_file"
      fi
      ;;
  esac

  if [[ -f "$coverage_file" ]]; then
    cat "$coverage_file"
  else
    echo "0"
  fi
}

# ============================================================================
# 테스트 실패 시 자동 재시도
# Usage: run_tests_with_retry <project_root> [test_filter] [max_retries]
# ============================================================================
run_tests_with_retry() {
  local project_root="${1:-}"
  local test_filter="${2:-}"
  local max_retries="${3:-$MAX_TEST_RETRIES}"

  local attempt=1
  local results

  while [[ $attempt -le $max_retries ]]; do
    results=$(run_tests "$project_root" "$test_filter")

    local failed
    failed=$(echo "$results" | jq -r '.failed // 0')

    if [[ "$failed" -eq 0 ]]; then
      echo "$results"
      return 0
    fi

    if declare -f log_event &>/dev/null; then
      log_event "$project_root" "WARN" "test_retry" "Tests failed, retrying" \
        "\"attempt\":$attempt,\"max_retries\":$max_retries,\"failed\":$failed"
    fi

    attempt=$((attempt + 1))
    sleep 2  # 재시도 전 대기
  done

  echo "$results"
  return 1
}

# ============================================================================
# 테스트 결과 요약
# Usage: summarize_test_results <results_json>
# Returns: Human-readable summary
# ============================================================================
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

# ============================================================================
# 테스트 결과가 90% 이상인지 확인
# Usage: check_test_success_rate <results_json> [threshold]
# Returns: true/false
# ============================================================================
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
  else
    echo "false"
    return 1
  fi
}
