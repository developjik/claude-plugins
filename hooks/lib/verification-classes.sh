#!/usr/bin/env bash
# verification-classes.sh — 검증 클래스 시스템
# P0-1: GSD-2의 verification classes 벤치마킹
#
# DEPENDENCIES: test-runner.sh, json-utils.sh, logging.sh
#
# 검증 클래스:
# - Class A: 정적 분석 (린트, 타입체크) - 실행 불필요, <30초
# - Class B: 유닛 테스트 - <1분
# - Class C: 통합 테스트 - <5분
# - Class D: E2E 테스트 - <15분

set -euo pipefail

# ============================================================================
# 상수
# ============================================================================

readonly VERIFICATION_DIR=".harness/verification"
readonly CLASS_A_TIMEOUT=30
readonly CLASS_B_TIMEOUT=60
readonly CLASS_C_TIMEOUT=300
readonly CLASS_D_TIMEOUT=900

# ============================================================================
# 프로젝트 타입 감지
# Usage: detect_project_type <project_root>
# Returns: javascript|typescript|python|go|rust|java|ruby|unknown
# ============================================================================
detect_project_type() {
  local project_root="${1:-}"

  if [[ -f "${project_root}/tsconfig.json" ]]; then
    echo "typescript"
    return 0
  fi

  if [[ -f "${project_root}/package.json" ]]; then
    echo "javascript"
    return 0
  fi

  if [[ -f "${project_root}/pyproject.toml" ]] || \
     [[ -f "${project_root}/setup.py" ]] || \
     [[ -f "${project_root}/requirements.txt" ]]; then
    echo "python"
    return 0
  fi

  if [[ -f "${project_root}/go.mod" ]]; then
    echo "go"
    return 0
  fi

  if [[ -f "${project_root}/Cargo.toml" ]]; then
    echo "rust"
    return 0
  fi

  if [[ -f "${project_root}/pom.xml" ]] || \
     [[ -f "${project_root}/build.gradle" ]]; then
    echo "java"
    return 0
  fi

  if [[ -f "${project_root}/Gemfile" ]]; then
    echo "ruby"
    return 0
  fi

  echo "unknown"
}

# ============================================================================
# Class A: 정적 분석
# 실행 불필요, 30초 이내
# ============================================================================

run_verification_class_a() {
  local project_root="${1:-}"
  local results_dir="${project_root}/${VERIFICATION_DIR}"
  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)

  mkdir -p "$results_dir"

  local project_type
  project_type=$(detect_project_type "$project_root")

  local results='{"class": "A", "name": "Static Analysis", "checks": []}'
  local all_passed=true

  case "$project_type" in
    javascript|typescript)
      # ESLint
      results=$(run_check "$results" "eslint" \
        "cd '$project_root' && npm run lint -- --format json 2>/dev/null || true" \
        "Linting passed" "Linting failed")

      # TypeScript 타입 체크 (TypeScript 프로젝트만)
      if [[ "$project_type" == "typescript" ]]; then
        results=$(run_check "$results" "typecheck" \
          "cd '$project_root' && npx tsc --noEmit 2>/dev/null" \
          "Type check passed" "Type check failed")
      fi

      # Prettier (설정되어 있으면)
      if [[ -f "${project_root}/.prettierrc" ]] || \
         [[ -f "${project_root}/.prettierrc.json" ]] || \
         grep -q '"prettier"' "${project_root}/package.json" 2>/dev/null; then
        results=$(run_check "$results" "format" \
          "cd '$project_root' && npx prettier --check 'src/**/*.{js,jsx,ts,tsx}' 2>/dev/null || true" \
          "Formatting check passed" "Formatting check failed")
      fi
      ;;

    python)
      # flake8 또는 pylint
      if command -v flake8 &>/dev/null; then
        results=$(run_check "$results" "flake8" \
          "cd '$project_root' && flake8 . --count --statistics 2>/dev/null || true" \
          "Flake8 check passed" "Flake8 check failed")
      elif command -v pylint &>/dev/null; then
        results=$(run_check "$results" "pylint" \
          "cd '$project_root' && pylint **/*.py 2>/dev/null || true" \
          "Pylint check passed" "Pylint check failed")
      fi

      # mypy (타입 체크)
      if command -v mypy &>/dev/null && [[ -f "${project_root}/mypy.ini" ]]; then
        results=$(run_check "$results" "mypy" \
          "cd '$project_root' && mypy . 2>/dev/null || true" \
          "Mypy check passed" "Mypy check failed")
      fi

      # black (포맷팅)
      if command -v black &>/dev/null; then
        results=$(run_check "$results" "black" \
          "cd '$project_root' && black --check . 2>/dev/null || true" \
          "Black check passed" "Black check failed")
      fi
      ;;

    go)
      # go vet
      results=$(run_check "$results" "go_vet" \
        "cd '$project_root' && go vet ./... 2>/dev/null" \
        "Go vet passed" "Go vet failed")

      # gofmt
      results=$(run_check "$results" "gofmt" \
        "cd '$project_root' && gofmt -l . 2>/dev/null | grep -q . && exit 1 || exit 0" \
        "Formatting check passed" "Formatting check failed")

      # golint (설치되어 있으면)
      if command -v golint &>/dev/null; then
        results=$(run_check "$results" "golint" \
          "cd '$project_root' && golint ./... 2>/dev/null || true" \
          "Golint passed" "Golint failed")
      fi
      ;;

    rust)
      # cargo clippy
      results=$(run_check "$results" "clippy" \
        "cd '$project_root' && cargo clippy -- -D warnings 2>/dev/null" \
        "Clippy passed" "Clippy failed")

      # cargo fmt
      results=$(run_check "$results" "format" \
        "cd '$project_root' && cargo fmt --check 2>/dev/null" \
        "Formatting check passed" "Formatting check failed")
      ;;

    java)
      # Maven/Gradle checkstyle
      if [[ -f "${project_root}/pom.xml" ]]; then
        results=$(run_check "$results" "checkstyle" \
          "cd '$project_root' && mvn checkstyle:check 2>/dev/null || true" \
          "Checkstyle passed" "Checkstyle failed")
      elif [[ -f "${project_root}/build.gradle" ]]; then
        results=$(run_check "$results" "checkstyle" \
          "cd '$project_root' && ./gradlew checkstyleMain 2>/dev/null || true" \
          "Checkstyle passed" "Checkstyle failed")
      fi
      ;;
  esac

  # 결과 저장
  echo "$results" > "${results_dir}/class_a_${timestamp}.json"

  # 전체 통과 여부 확인
  local failed_count
  failed_count=$(echo "$results" | jq '[.checks[] | select(.status == "failed")] | length')

  if [[ "$failed_count" -gt 0 ]]; then
    echo "$results" | jq '. + {"passed": false, "failed_count": '"$failed_count"'}'
    return 1
  else
    echo "$results" | jq '. + {"passed": true, "failed_count": 0}'
    return 0
  fi
}

# ============================================================================
# Class B: 유닛 테스트
# 1분 이내
# ============================================================================

run_verification_class_b() {
  local project_root="${1:-}"
  local test_filter="${2:-}"
  local results_dir="${project_root}/${VERIFICATION_DIR}"
  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)

  mkdir -p "$results_dir"

  # test-runner.sh의 run_tests 함수 사용
  if ! declare -f run_tests &>/dev/null; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${SCRIPT_DIR}/test-runner.sh"
  fi

  local test_results
  test_results=$(timeout "$CLASS_B_TIMEOUT" run_tests "$project_root" "$test_filter" 2>/dev/null || \
    echo '{"error": "timeout", "passed": 0, "failed": 1}')

  # 결과에 클래스 정보 추가
  local results
  results=$(echo "$test_results" | jq '. + {"class": "B", "name": "Unit Tests"}')

  # 결과 저장
  echo "$results" > "${results_dir}/class_b_${timestamp}.json"

  local failed
  failed=$(echo "$results" | jq -r '.failed // 0')

  if [[ "$failed" -gt 0 ]]; then
    echo "$results" | jq '. + {"passed": false}'
    return 1
  else
    echo "$results" | jq '. + {"passed": true}'
    return 0
  fi
}

# ============================================================================
# Class C: 통합 테스트
# 5분 이내
# ============================================================================

run_verification_class_c() {
  local project_root="${1:-}"
  local results_dir="${project_root}/${VERIFICATION_DIR}"
  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)

  mkdir -p "$results_dir"

  local project_type
  project_type=$(detect_project_type "$project_root")

  local results='{"class": "C", "name": "Integration Tests", "checks": []}'

  # 통합 테스트 실행 (프레임워크별)
  case "$project_type" in
    javascript|typescript)
      # 통합 테스트 파일 패턴으로 실행
      if [[ -f "${project_root}/package.json" ]] && \
         grep -q '"test:integration"' "${project_root}/package.json" 2>/dev/null; then
        results=$(run_check "$results" "integration" \
          "cd '$project_root' && npm run test:integration 2>/dev/null || true" \
          "Integration tests passed" "Integration tests failed")
      else
        # *.integration.test.* 패턴 찾기
        local integration_files
        integration_files=$(find "${project_root}" -name "*.integration.test.*" -o -name "*.integration.spec.*" 2>/dev/null | head -5)

        if [[ -n "$integration_files" ]]; then
          results=$(run_check "$results" "integration" \
            "cd '$project_root' && npm test -- --testPathPattern='integration' 2>/dev/null || true" \
            "Integration tests passed" "Integration tests failed")
        else
          results=$(echo "$results" | jq '.checks += [{"name": "integration", "status": "skipped", "message": "No integration tests found"}]')
        fi
      fi
      ;;

    python)
      # pytest로 통합 테스트 실행
      if [[ -d "${project_root}/tests/integration" ]]; then
        results=$(run_check "$results" "integration" \
          "cd '$project_root' && python -m pytest tests/integration -v 2>/dev/null || true" \
          "Integration tests passed" "Integration tests failed")
      else
        results=$(echo "$results" | jq '.checks += [{"name": "integration", "status": "skipped", "message": "No integration tests found"}]')
      fi
      ;;

    go)
      # 통합 태그가 있는 테스트 실행
      results=$(run_check "$results" "integration" \
        "cd '$project_root' && go test -v -tags=integration ./... 2>/dev/null || true" \
        "Integration tests passed" "Integration tests failed")
      ;;

    *)
      results=$(echo "$results" | jq '.checks += [{"name": "integration", "status": "skipped", "message": "Unsupported project type"}]')
      ;;
  esac

  # 결과 저장
  echo "$results" > "${results_dir}/class_c_${timestamp}.json"

  local failed_count
  failed_count=$(echo "$results" | jq '[.checks[] | select(.status == "failed")] | length')

  if [[ "$failed_count" -gt 0 ]]; then
    echo "$results" | jq '. + {"passed": false, "failed_count": '"$failed_count"'}'
    return 1
  else
    echo "$results" | jq '. + {"passed": true, "failed_count": 0}'
    return 0
  fi
}

# ============================================================================
# Class D: E2E 테스트
# 15분 이내
# ============================================================================

run_verification_class_d() {
  local project_root="${1:-}"
  local results_dir="${project_root}/${VERIFICATION_DIR}"
  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)

  mkdir -p "$results_dir"

  local project_type
  project_type=$(detect_project_type "$project_root")

  local results='{"class": "D", "name": "E2E Tests", "checks": []}'

  # E2E 테스트 실행
  case "$project_type" in
    javascript|typescript)
      # Playwright 또는 Cypress
      if [[ -f "${project_root}/playwright.config.ts" ]] || \
         [[ -f "${project_root}/playwright.config.js" ]]; then
        results=$(run_check "$results" "playwright" \
          "cd '$project_root' && npx playwright test 2>/dev/null || true" \
          "E2E tests passed" "E2E tests failed")
      elif [[ -f "${project_root}/cypress.config.ts" ]] || \
           [[ -f "${project_root}/cypress.config.js" ]]; then
        results=$(run_check "$results" "cypress" \
          "cd '$project_root' && npx cypress run 2>/dev/null || true" \
          "E2E tests passed" "E2E tests failed")
      elif grep -q '"test:e2e"' "${project_root}/package.json" 2>/dev/null; then
        results=$(run_check "$results" "e2e" \
          "cd '$project_root' && npm run test:e2e 2>/dev/null || true" \
          "E2E tests passed" "E2E tests failed")
      else
        results=$(echo "$results" | jq '.checks += [{"name": "e2e", "status": "skipped", "message": "No E2E tests found"}]')
      fi
      ;;

    python)
      # pytest로 E2E 테스트 실행
      if [[ -d "${project_root}/tests/e2e" ]]; then
        results=$(run_check "$results" "e2e" \
          "cd '$project_root' && python -m pytest tests/e2e -v 2>/dev/null || true" \
          "E2E tests passed" "E2E tests failed")
      else
        results=$(echo "$results" | jq '.checks += [{"name": "e2e", "status": "skipped", "message": "No E2E tests found"}]')
      fi
      ;;

    go)
      # E2E 태그가 있는 테스트 실행
      results=$(run_check "$results" "e2e" \
        "cd '$project_root' && go test -v -tags=e2e ./... 2>/dev/null || true" \
        "E2E tests passed" "E2E tests failed")
      ;;

    *)
      results=$(echo "$results" | jq '.checks += [{"name": "e2e", "status": "skipped", "message": "Unsupported project type"}]')
      ;;
  esac

  # 결과 저장
  echo "$results" > "${results_dir}/class_d_${timestamp}.json"

  local failed_count
  failed_count=$(echo "$results" | jq '[.checks[] | select(.status == "failed")] | length')

  if [[ "$failed_count" -gt 0 ]]; then
    echo "$results" | jq '. + {"passed": false, "failed_count": '"$failed_count"'}'
    return 1
  else
    echo "$results" | jq '. + {"passed": true, "failed_count": 0}'
    return 0
  fi
}

# ============================================================================
# 헬퍼: 개별 체크 실행
# ============================================================================
run_check() {
  local results="${1:-}"
  local check_name="${2:-}"
  local check_cmd="${3:-}"
  local success_msg="${4:-"Check passed"}"
  local fail_msg="${5:-"Check failed"}"

  local status="passed"
  local message="$success_msg"
  local output=""

  # 타임아웃과 함께 실행
  if output=$(timeout 30 bash -c "$check_cmd" 2>&1); then
    status="passed"
    message="$success_msg"
  else
    local exit_code=$?
    if [[ $exit_code -eq 124 ]]; then
      status="timeout"
      message="Check timed out"
    else
      status="failed"
      message="$fail_msg"
    fi
  fi

  # 결과에 추가
  local check_entry
  check_entry=$(echo "$output" | head -10 | jq -Rs . | jq -c '{"name": "'"$check_name"'", "status": "'"$status"'", "message": "'"$message"'", "output": .}')
  echo "$results" | jq '.checks += ['"$check_entry"']'
}

# ============================================================================
# 통합 검증 실행
# Usage: run_verification <project_root> [classes] [--thorough]
# classes: a, ab, abc, abcd (default: ab)
# ============================================================================

run_verification() {
  local project_root="${1:-}"
  local classes="${2:-ab}"
  local thorough=false

  if [[ "${3:-}" == "--thorough" ]] || [[ "${4:-}" == "--thorough" ]]; then
    thorough=true
    classes="abcd"
  fi

  local results_dir="${project_root}/${VERIFICATION_DIR}"
  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)

  mkdir -p "$results_dir"

  local all_results='{"timestamp": "'"$timestamp"'", "classes": [], "summary": {"total": 0, "passed": 0, "failed": 0}}'
  local total_passed=0
  local total_failed=0

  echo "🔍 Running verification (classes: $classes)..."
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  # Class A
  if [[ "$classes" == *a* ]]; then
    echo "📊 Class A: Static Analysis..."
    local result_a
    if result_a=$(timeout "$CLASS_A_TIMEOUT" run_verification_class_a "$project_root" 2>/dev/null); then
      echo "  ✅ Passed"
      total_passed=$((total_passed + 1))
    else
      echo "  ❌ Failed"
      total_failed=$((total_failed + 1))
    fi
    all_results=$(echo "$all_results" | jq '.classes += ['"$result_a"']')
    echo ""
  fi

  # Class B
  if [[ "$classes" == *b* ]]; then
    echo "📊 Class B: Unit Tests..."
    local result_b
    if result_b=$(timeout "$CLASS_B_TIMEOUT" run_verification_class_b "$project_root" "" 2>/dev/null); then
      echo "  ✅ Passed"
      total_passed=$((total_passed + 1))
    else
      echo "  ❌ Failed"
      total_failed=$((total_failed + 1))
    fi
    all_results=$(echo "$all_results" | jq '.classes += ['"$result_b"']')
    echo ""
  fi

  # Class C
  if [[ "$classes" == *c* ]]; then
    echo "📊 Class C: Integration Tests..."
    local result_c
    if result_c=$(timeout "$CLASS_C_TIMEOUT" run_verification_class_c "$project_root" 2>/dev/null); then
      echo "  ✅ Passed"
      total_passed=$((total_passed + 1))
    else
      echo "  ❌ Failed"
      total_failed=$((total_failed + 1))
    fi
    all_results=$(echo "$all_results" | jq '.classes += ['"$result_c"']')
    echo ""
  fi

  # Class D
  if [[ "$classes" == *d* ]]; then
    echo "📊 Class D: E2E Tests..."
    local result_d
    if result_d=$(timeout "$CLASS_D_TIMEOUT" run_verification_class_d "$project_root" 2>/dev/null); then
      echo "  ✅ Passed"
      total_passed=$((total_passed + 1))
    else
      echo "  ❌ Failed"
      total_failed=$((total_failed + 1))
    fi
    all_results=$(echo "$all_results" | jq '.classes += ['"$result_d"']')
    echo ""
  fi

  # 요약 업데이트
  local success_rate
  success_rate=$(awk "BEGIN {printf \"%.2f\", $total_passed / ($total_passed + $total_failed)}")
  all_results=$(echo "$all_results" | jq -c '.summary = {"total": '"$((total_passed + total_failed))"', "passed": '"$total_passed"', "failed": '"$total_failed"', "success_rate": "'"$success_rate"'"}')

  # 결과 저장
  echo "$all_results" > "${results_dir}/verification_${timestamp}.json"

  # 요약 출력
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📈 Verification Summary"
  echo ""
  echo "  Total:   $((total_passed + total_failed))"
  echo "  Passed:  $total_passed"
  echo "  Failed:  $total_failed"
  echo ""

  if [[ "$total_failed" -eq 0 ]]; then
    echo "✅ All verification classes passed!"
    return 0
  else
    echo "❌ Some verification classes failed."
    return 1
  fi
}

# ============================================================================
# 검증 결과가 성공 임계값을 넘는지 확인
# Usage: check_verification_threshold <results_json> [threshold]
# threshold: 0.0 - 1.0 (default: 0.9)
# ============================================================================
check_verification_threshold() {
  local results="${1:-}"
  local threshold="${2:-0.9}"

  local passed failed total
  passed=$(echo "$results" | jq -r '.summary.passed // 0')
  failed=$(echo "$results" | jq -r '.summary.failed // 0')
  total=$((passed + failed))

  if [[ "$total" -eq 0 ]]; then
    echo '{"threshold_met": false, "reason": "no_checks_run"}'
    return 1
  fi

  local success_rate
  success_rate=$(awk "BEGIN {printf \"%.2f\", $passed / $total}")

  if awk "BEGIN {exit !($success_rate >= $threshold)}"; then
    echo '{"threshold_met": true, "success_rate": '"$success_rate"', "threshold": '"$threshold"'}'
    return 0
  else
    echo '{"threshold_met": false, "success_rate": '"$success_rate"', "threshold": '"$threshold"'}'
    return 1
  fi
}
