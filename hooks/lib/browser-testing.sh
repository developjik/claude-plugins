#!/usr/bin/env bash
# browser-testing.sh — 브라우저 테스트 통합 시스템
# P1-4: Playwright 기반 E2E 테스트 자동화
#
# DEPENDENCIES: json-utils.sh, logging.sh, test-runner.sh
#
# 지원 프레임워크:
# - Playwright (JavaScript/TypeScript)
# - Cypress (JavaScript/TypeScript)
# - Selenium (다양한 언어)

set -euo pipefail

# ============================================================================
# 상수
# ============================================================================

readonly BROWSER_TEST_DIR=".harness/browser-tests"
readonly PLAYWRIGHT_CONFIG="playwright.config.ts"
readonly CYPRESS_CONFIG="cypress.config.ts"
readonly DEFAULT_BROWSERS="chromium"
readonly BROWSER_TIMEOUT=300000  # 5분
readonly RETRY_COUNT=2

# ============================================================================
# Playwright 설정
# ============================================================================

# Playwright 자동 설정
# Usage: setup_playwright <project_root> [browser]
setup_playwright() {
  local project_root="${1:-}"
  local browser="${2:-$DEFAULT_BROWSERS}"

  local result='{"success": false, "steps": [], "errors": []}'

  # 1. Node.js 확인
  if ! command -v node &>/dev/null; then
    result=$(echo "$result" | jq '.errors += ["Node.js not installed"]')
    echo "$result"
    return 1
  fi

  result=$(echo "$result" | jq '.steps += ["Node.js found"]')

  # 2. package.json 확인
  local package_json="${project_root}/package.json"
  if [[ ! -f "$package_json" ]]; then
    result=$(echo "$result" | jq '.errors += ["package.json not found"]')
    echo "$result"
    return 1
  fi

  result=$(echo "$result" | jq '.steps += ["package.json found"]')

  # 3. Playwright 설치 확인
  local has_playwright=false
  if grep -q '"@playwright/test"' "$package_json" 2>/dev/null; then
    has_playwright=true
    result=$(echo "$result" | jq '.steps += ["Playwright already installed"]')
  else
    # Playwright 설치 제안
    result=$(echo "$result" | jq '.steps += ["Playwright not installed - run: npm install -D @playwright/test"]')
  fi

  # 4. 설정 파일 확인/생성
  local config_file="${project_root}/${PLAYWRIGHT_CONFIG}"
  if [[ ! -f "$config_file" ]]; then
    # 기본 설정 생성
    generate_playwright_config "$project_root" "$browser"
    result=$(echo "$result" | jq '.steps += ["Generated default playwright.config.ts"]')
  else
    result=$(echo "$result" | jq '.steps += ["playwright.config.ts exists"]')
  fi

  # 5. 브라우저 설치 확인
  local browsers_installed=false
  if $has_playwright && npx playwright --version &>/dev/null; then
    browsers_installed=true
    result=$(echo "$result" | jq '.steps += ["Browsers available"]')
  else
    result=$(echo "$result" | jq '.steps += ["Run: npx playwright install"]')
  fi

  # 6. 테스트 디렉토리 확인
  local test_dir="${project_root}/tests/e2e"
  if [[ ! -d "$test_dir" ]]; then
    mkdir -p "$test_dir"
    result=$(echo "$result" | jq '.steps += ["Created tests/e2e directory"]')
  fi

  result=$(echo "$result" | jq '.success = true')
  echo "$result"
}

# Playwright 기본 설정 생성
# Usage: generate_playwright_config <project_root> [browser]
generate_playwright_config() {
  local project_root="${1:-}"
  local browser="${2:-chromium}"
  local config_file="${project_root}/${PLAYWRIGHT_CONFIG}"

  cat > "$config_file" << 'EOF'
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests/e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: [
    ['html', { outputFolder: '.harness/browser-tests/report' }],
    ['json', { outputFile: '.harness/browser-tests/results.json' }]
  ],
  use: {
    baseURL: process.env.BASE_URL || 'http://localhost:3000',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
  webServer: {
    command: 'npm run dev',
    url: 'http://localhost:3000',
    reuseExistingServer: !process.env.CI,
    timeout: 120000,
  },
});
EOF

  echo "$config_file"
}

# ============================================================================
# 브라우저 테스트 실행
# ============================================================================

# 브라우저 테스트 실행
# Usage: run_browser_tests <project_root> [options]
# Options: --browser=<browser> --filter=<pattern> --headed --debug
run_browser_tests() {
  local project_root="${1:-}"
  shift

  local browser="$DEFAULT_BROWSERS"
  local filter=""
  local headed=false
  local debug=false

  # 옵션 파싱
  for arg in "$@"; do
    case "$arg" in
      --browser=*) browser="${arg#*=}" ;;
      --filter=*) filter="${arg#*=}" ;;
      --headed) headed=true ;;
      --debug) debug=true ;;
    esac
  done

  # 결과 디렉토리 생성
  local results_dir="${project_root}/${BROWSER_TEST_DIR}"
  mkdir -p "$results_dir"

  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)

  # 프레임워크 감지
  local framework
  framework=$(detect_browser_test_framework "$project_root")

  local result='{"success": false, "framework": "'"$framework"'", "timestamp": "'"$timestamp"'"}'

  case "$framework" in
    playwright)
      result=$(run_playwright_tests "$project_root" "$browser" "$filter" "$headed" "$debug")
      ;;
    cypress)
      result=$(run_cypress_tests "$project_root" "$browser" "$filter")
      ;;
    *)
      result=$(echo "$result" | jq '.error = "Unsupported framework"')
      ;;
  esac

  # 결과 저장
  echo "$result" > "${results_dir}/browser_test_${timestamp}.json"

  echo "$result"
}

# Playwright 테스트 실행
run_playwright_tests() {
  local project_root="${1:-}"
  local browser="${2:-chromium}"
  local filter="${3:-}"
  local headed="${4:-false}"
  local debug="${5:-false}"

  local results_dir="${project_root}/${BROWSER_TEST_DIR}"
  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)

  # Playwright 명령어 구성
  local cmd="npx playwright test --project=$browser --reporter=json"

  if [[ -n "$filter" ]]; then
    cmd="$cmd --grep=\"$filter\""
  fi

  if [[ "$headed" == "true" ]]; then
    cmd="$cmd --headed"
  fi

  if [[ "$debug" == "true" ]]; then
    cmd="$cmd --debug"
  fi

  # 타임아웃과 함께 실행
  local output_file="${results_dir}/playwright_output_${timestamp}.json"
  local exit_code=0

  if timeout "$BROWSER_TIMEOUT" bash -c "cd '$project_root' && $cmd > '$output_file' 2>&1"; then
    exit_code=0
  else
    exit_code=$?
  fi

  # 결과 파싱
  local parsed
  parsed=$(parse_playwright_results "$output_file" "$exit_code")

  echo "$parsed"
}

# Cypress 테스트 실행
run_cypress_tests() {
  local project_root="${1:-}"
  local browser="${2:-chromium}"
  local filter="${3:-}"

  local results_dir="${project_root}/${BROWSER_TEST_DIR}"
  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)

  local cmd="npx cypress run --browser=$browser --reporter=json"

  if [[ -n "$filter" ]]; then
    cmd="$cmd --spec=\"$filter\""
  fi

  local output_file="${results_dir}/cypress_output_${timestamp}.json"
  local exit_code=0

  if timeout "$BROWSER_TIMEOUT" bash -c "cd '$project_root' && $cmd > '$output_file' 2>&1"; then
    exit_code=0
  else
    exit_code=$?
  fi

  # 결과 파싱
  local parsed
  parsed=$(parse_cypress_results "$output_file" "$exit_code")

  echo "$parsed"
}

# ============================================================================
# 결과 파싱
# ============================================================================

# Playwright 결과 파싱
# Usage: parse_playwright_results <output_file> <exit_code>
parse_playwright_results() {
  local output_file="${1:-}"
  local exit_code="${2:-0}"

  if [[ ! -f "$output_file" ]]; then
    jq -c -n --argjson exit "$exit_code" \
      '{"success": false, "error": "No output file", "exit_code": $exit}'
    return 1
  fi

  # Playwright JSON 결과에서 통계 추출
  local total passed failed skipped duration

  # JSON이 유효한지 확인
  if jq -e . "$output_file" > /dev/null 2>&1; then
    # Playwright 리포트 형식에 따라 파싱
    local stats
    stats=$(jq -r '
      if .stats then
        {total: .stats.tests, passed: .stats.passed, failed: .stats.failed, skipped: .stats.skipped, duration: .stats.duration}
      else
        {total: 0, passed: 0, failed: 0, skipped: 0, duration: 0}
      end
    ' "$output_file" 2>/dev/null || echo '{"total":0,"passed":0,"failed":0,"skipped":0,"duration":0}')

    total=$(echo "$stats" | jq -r '.total')
    passed=$(echo "$stats" | jq -r '.passed')
    failed=$(echo "$stats" | jq -r '.failed')
    skipped=$(echo "$stats" | jq -r '.skipped')
    duration=$(echo "$stats" | jq -r '.duration')
  else
    # JSON이 유효하지 않으면 기본값
    total=0
    passed=0
    failed=1
    skipped=0
    duration=0
  fi

  local success=false
  if [[ "$failed" -eq 0 ]] && [[ "$exit_code" -eq 0 ]]; then
    success=true
  fi

  jq -c -n \
    --argjson success "$success" \
    --arg framework "playwright" \
    --argjson total "$total" \
    --argjson passed "$passed" \
    --argjson failed "$failed" \
    --argjson skipped "$skipped" \
    --argjson duration "$duration" \
    --argjson exit_code "$exit_code" \
    '{
      success: $success,
      framework: $framework,
      summary: {
        total: $total,
        passed: $passed,
        failed: $failed,
        skipped: $skipped,
        duration_ms: $duration
      },
      exit_code: $exit_code
    }'
}

# Cypress 결과 파싱
parse_cypress_results() {
  local output_file="${1:-}"
  local exit_code="${2:-0}"

  if [[ ! -f "$output_file" ]]; then
    jq -c -n --argjson exit "$exit_code" \
      '{"success": false, "error": "No output file", "exit_code": $exit}'
    return 1
  fi

  local total passed failed skipped duration

  if jq -e . "$output_file" > /dev/null 2>&1; then
    local stats
    stats=$(jq -r '
      if .stats then
        {total: .stats.tests, passed: .stats.passes, failed: .stats.failures, skipped: 0, duration: .stats.duration}
      else
        {total: 0, passed: 0, failed: 0, skipped: 0, duration: 0}
      end
    ' "$output_file" 2>/dev/null || echo '{"total":0,"passed":0,"failed":0,"skipped":0,"duration":0}')

    total=$(echo "$stats" | jq -r '.total')
    passed=$(echo "$stats" | jq -r '.passed')
    failed=$(echo "$stats" | jq -r '.failed')
    skipped=$(echo "$stats" | jq -r '.skipped')
    duration=$(echo "$stats" | jq -r '.duration')
  else
    total=0
    passed=0
    failed=1
    skipped=0
    duration=0
  fi

  local success=false
  if [[ "$failed" -eq 0 ]] && [[ "$exit_code" -eq 0 ]]; then
    success=true
  fi

  jq -c -n \
    --argjson success "$success" \
    --arg framework "cypress" \
    --argjson total "$total" \
    --argjson passed "$passed" \
    --argjson failed "$failed" \
    --argjson skipped "$skipped" \
    --argjson duration "$duration" \
    --argjson exit_code "$exit_code" \
    '{
      success: $success,
      framework: $framework,
      summary: {
        total: $total,
        passed: $passed,
        failed: $failed,
        skipped: $skipped,
        duration_ms: $duration
      },
      exit_code: $exit_code
    }'
}

# ============================================================================
# 프레임워크 감지
# ============================================================================

# 브라우저 테스트 프레임워크 감지
# Usage: detect_browser_test_framework <project_root>
detect_browser_test_framework() {
  local project_root="${1:-}"
  local package_json="${project_root}/package.json"

  # 1. package.json에서 확인
  if [[ -f "$package_json" ]]; then
    if grep -q '"@playwright/test"' "$package_json" 2>/dev/null; then
      echo "playwright"
      return 0
    fi

    if grep -q '"cypress"' "$package_json" 2>/dev/null; then
      echo "cypress"
      return 0
    fi
  fi

  # 2. 설정 파일로 확인
  if [[ -f "${project_root}/${PLAYWRIGHT_CONFIG}" ]]; then
    echo "playwright"
    return 0
  fi

  if [[ -f "${project_root}/${CYPRESS_CONFIG}" ]]; then
    echo "cypress"
    return 0
  fi

  echo "none"
}

# ============================================================================
# 브라우저 관리
# ============================================================================

# 브라우저 가용성 확인
# Usage: check_browser_availability <project_root> [browser]
check_browser_availability() {
  local project_root="${1:-}"
  local browser="${2:-chromium}"

  local result='{"available": false, "browser": "'"$browser"'", "issues": []}'

  # Playwright 브라우저 확인
  local framework
  framework=$(detect_browser_test_framework "$project_root")

  if [[ "$framework" == "playwright" ]]; then
    if npx playwright --version &>/dev/null; then
      result=$(echo "$result" | jq '.available = true')
    else
      result=$(echo "$result" | jq '.issues += ["Playwright browsers not installed. Run: npx playwright install"]')
    fi
  elif [[ "$framework" == "cypress" ]]; then
    if npx cypress --version &>/dev/null; then
      result=$(echo "$result" | jq '.available = true')
    else
      result=$(echo "$result" | jq '.issues += ["Cypress not properly installed"]')
    fi
  else
    result=$(echo "$result" | jq '.issues += ["No browser test framework detected"]')
  fi

  echo "$result"
}

# 브라우저 설치
# Usage: install_browsers <project_root> [browser]
install_browsers() {
  local project_root="${1:-}"
  local browser="${2:-chromium}"

  local framework
  framework=$(detect_browser_test_framework "$project_root")

  local result='{"success": false, "framework": "'"$framework"'", "browser": "'"$browser"'"}'

  if [[ "$framework" == "playwright" ]]; then
    if cd "$project_root" && npx playwright install "$browser" 2>&1; then
      result=$(echo "$result" | jq '.success = true')
    else
      result=$(echo "$result" | jq '.error = "Failed to install browsers"')
    fi
  elif [[ "$framework" == "cypress" ]]; then
    if cd "$project_root" && npx cypress install 2>&1; then
      result=$(echo "$result" | jq '.success = true')
    else
      result=$(echo "$result" | jq '.error = "Failed to install Cypress"')
    fi
  else
    result=$(echo "$result" | jq '.error = "No supported framework found"')
  fi

  echo "$result"
}

# ============================================================================
# 리포트 생성
# ============================================================================

# HTML 리포트 생성
# Usage: generate_html_report <project_root> [results_file]
generate_html_report() {
  local project_root="${1:-}"
  local results_file="${2:-}"

  local results_dir="${project_root}/${BROWSER_TEST_DIR}"
  mkdir -p "$results_dir"

  # 결과 파일이 없으면 최신 파일 찾기
  if [[ -z "$results_file" ]] || [[ ! -f "$results_file" ]]; then
    results_file=$(ls -t "${results_dir}"/browser_test_*.json 2>/dev/null | head -1)
  fi

  if [[ -z "$results_file" ]] || [[ ! -f "$results_file" ]]; then
    echo '{"error": "No results file found"}'
    return 1
  fi

  local report_file="${results_dir}/report.html"
  local timestamp
  timestamp=$(date -u '+%Y-%m-%d %H:%M:%S UTC')

  local results
  results=$(cat "$results_file")

  local success framework total passed failed skipped duration
  success=$(echo "$results" | jq -r '.success')
  framework=$(echo "$results" | jq -r '.framework')
  total=$(echo "$results" | jq -r '.summary.total // 0')
  passed=$(echo "$results" | jq -r '.summary.passed // 0')
  failed=$(echo "$results" | jq -r '.summary.failed // 0')
  skipped=$(echo "$results" | jq -r '.summary.skipped // 0')
  duration=$(echo "$results" | jq -r '.summary.duration_ms // 0')

  local status_color="#10b981"
  local status_text="PASSED"
  if [[ "$success" != "true" ]]; then
    status_color="#ef4444"
    status_text="FAILED"
  fi

  cat > "$report_file" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Browser Test Report</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; margin: 0; padding: 20px; background: #f3f4f6; }
    .container { max-width: 800px; margin: 0 auto; background: white; border-radius: 8px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); padding: 24px; }
    h1 { margin: 0 0 8px; font-size: 24px; }
    .timestamp { color: #6b7280; font-size: 14px; margin-bottom: 24px; }
    .status-badge { display: inline-block; padding: 4px 12px; border-radius: 9999px; color: white; font-weight: 600; font-size: 14px; }
    .metrics { display: grid; grid-template-columns: repeat(5, 1fr); gap: 16px; margin-top: 24px; }
    .metric { text-align: center; padding: 16px; background: #f9fafb; border-radius: 8px; }
    .metric-value { font-size: 32px; font-weight: 700; color: #1f2937; }
    .metric-label { font-size: 12px; color: #6b7280; text-transform: uppercase; margin-top: 4px; }
    .passed { color: #10b981; }
    .failed { color: #ef4444; }
    .skipped { color: #f59e0b; }
    .framework { margin-top: 24px; padding: 12px; background: #f3f4f6; border-radius: 6px; font-size: 14px; }
  </style>
</head>
<body>
  <div class="container">
    <h1>Browser Test Report</h1>
    <p class="timestamp">$timestamp</p>

    <span class="status-badge" style="background-color: $status_color;">$status_text</span>

    <div class="metrics">
      <div class="metric">
        <div class="metric-value">$total</div>
        <div class="metric-label">Total</div>
      </div>
      <div class="metric">
        <div class="metric-value passed">$passed</div>
        <div class="metric-label">Passed</div>
      </div>
      <div class="metric">
        <div class="metric-value failed">$failed</div>
        <div class="metric-label">Failed</div>
      </div>
      <div class="metric">
        <div class="metric-value skipped">$skipped</div>
        <div class="metric-label">Skipped</div>
      </div>
      <div class="metric">
        <div class="metric-value">${duration}ms</div>
        <div class="metric-label">Duration</div>
      </div>
    </div>

    <div class="framework">
      <strong>Framework:</strong> $framework
    </div>
  </div>
</body>
</html>
EOF

  echo "{\"report_file\": \"$report_file\", \"success\": $success}"
}

# ============================================================================
# 테스트 히스토리
# ============================================================================

# 테스트 히스토리 조회
# Usage: get_browser_test_history <project_root> [limit]
get_browser_test_history() {
  local project_root="${1:-}"
  local limit="${2:-10}"

  local results_dir="${project_root}/${BROWSER_TEST_DIR}"

  if [[ ! -d "$results_dir" ]]; then
    echo '[]'
    return 0
  fi

  local history='[]'
  local count=0

  for file in $(ls -t "${results_dir}"/browser_test_*.json 2>/dev/null); do
    if [[ $count -ge $limit ]]; then
      break
    fi

    local entry
    entry=$(jq -c '{
      timestamp: .timestamp,
      success: .success,
      framework: .framework,
      passed: .summary.passed,
      failed: .summary.failed,
      total: .summary.total
    }' "$file" 2>/dev/null)

    if [[ -n "$entry" ]]; then
      history=$(echo "$history" | jq ". + [$entry]")
      count=$((count + 1))
    fi
  done

  echo "$history"
}

# ============================================================================
# 정리
# ============================================================================

# 오래된 결과 정리
# Usage: cleanup_old_browser_results <project_root> [max_age_days]
cleanup_old_browser_results() {
  local project_root="${1:-}"
  local max_age_days="${2:-7}"

  local results_dir="${project_root}/${BROWSER_TEST_DIR}"

  if [[ ! -d "$results_dir" ]]; then
    echo "0"
    return 0
  fi

  local cleaned=0
  local now
  now=$(date +%s)
  local max_age_seconds=$((max_age_days * 86400))

  for file in "$results_dir"/*.json "$results_dir"/*.html; do
    if [[ -f "$file" ]]; then
      local file_ts
      file_ts=$(stat -f %m "$file" 2>/dev/null || stat -c %Y "$file" 2>/dev/null || echo 0)
      local age=$((now - file_ts))

      if [[ $age -gt $max_age_seconds ]]; then
        rm -f "$file"
        cleaned=$((cleaned + 1))
      fi
    fi
  done

  echo "$cleaned"
}

# ============================================================================
# 통합 실행
# ============================================================================

# 전체 브라우저 테스트 실행
# Usage: run_full_browser_test_suite <project_root> [options]
run_full_browser_test_suite() {
  local project_root="${1:-}"
  shift

  echo "========================================"
  echo "Browser Test Suite"
  echo "========================================"
  echo ""

  # 1. 프레임워크 감지
  local framework
  framework=$(detect_browser_test_framework "$project_root")

  if [[ "$framework" == "none" ]]; then
    echo "No browser test framework detected."
    echo ""
    echo "Install one of the following:"
    echo "  - Playwright: npm install -D @playwright/test"
    echo "  - Cypress:    npm install -D cypress"
    return 1
  fi

  echo "Framework: $framework"
  echo ""

  # 2. 설정 확인
  echo "Checking setup..."
  local setup_result
  setup_result=$(setup_playwright "$project_root" 2>/dev/null)

  if echo "$setup_result" | jq -e '.success' > /dev/null 2>&1; then
    echo "  Setup OK"
  else
    echo "  Setup issues found:"
    echo "$setup_result" | jq -r '.errors[]? // empty' | while read -r err; do
      echo "    - $err"
    done
  fi
  echo ""

  # 3. 브라우저 확인
  echo "Checking browser availability..."
  local browser_status
  browser_status=$(check_browser_availability "$project_root")

  if echo "$browser_status" | jq -e '.available' > /dev/null 2>&1; then
    echo "  Browsers ready"
  else
    echo "  Browser issues:"
    echo "$browser_status" | jq -r '.issues[]? // empty' | while read -r issue; do
      echo "    - $issue"
    done
    echo ""
    echo "Installing browsers..."
    install_browsers "$project_root"
  fi
  echo ""

  # 4. 테스트 실행
  echo "Running browser tests..."
  echo ""

  local test_result
  test_result=$(run_browser_tests "$project_root" "$@")

  local success total passed failed duration
  success=$(echo "$test_result" | jq -r '.success')
  total=$(echo "$test_result" | jq -r '.summary.total // 0')
  passed=$(echo "$test_result" | jq -r '.summary.passed // 0')
  failed=$(echo "$test_result" | jq -r '.summary.failed // 0')
  duration=$(echo "$test_result" | jq -r '.summary.duration_ms // 0')

  # 5. 결과 요약
  echo ""
  echo "========================================"
  echo "Results"
  echo "========================================"
  echo ""
  echo "  Total:   $total"
  echo "  Passed:  $passed"
  echo "  Failed:  $failed"
  echo "  Duration: ${duration}ms"
  echo ""

  if [[ "$success" == "true" ]]; then
    echo "  Status: PASSED"
  else
    echo "  Status: FAILED"
  fi
  echo ""

  # 6. HTML 리포트 생성
  local report
  report=$(generate_html_report "$project_root")
  echo "Report: $(echo "$report" | jq -r '.report_file')"

  echo "$test_result"
}
