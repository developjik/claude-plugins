#!/usr/bin/env bash
# browser-test-runner.sh — browser-testing runner and parser helpers

set -euo pipefail

browser_test_results_dir() {
  local project_root="${1:-}"
  echo "${project_root}/${BROWSER_TEST_DIR}"
}

browser_test_timestamp() {
  date +%Y%m%d_%H%M%S
}

# ============================================================================
# Playwright 설정
# ============================================================================

# Playwright 자동 설정
# Usage: setup_playwright <project_root> [browser]
setup_playwright() {
  local project_root="${1:-}"
  local browser="${2:-$DEFAULT_BROWSERS}"

  local result='{"success": false, "steps": [], "errors": []}'

  if ! command -v node &> /dev/null; then
    result=$(echo "$result" | jq '.errors += ["Node.js not installed"]')
    echo "$result"
    return 1
  fi

  result=$(echo "$result" | jq '.steps += ["Node.js found"]')

  local package_json="${project_root}/package.json"
  if [[ ! -f "$package_json" ]]; then
    result=$(echo "$result" | jq '.errors += ["package.json not found"]')
    echo "$result"
    return 1
  fi

  result=$(echo "$result" | jq '.steps += ["package.json found"]')

  local has_playwright=false
  if grep -q '"@playwright/test"' "$package_json" 2> /dev/null; then
    has_playwright=true
    result=$(echo "$result" | jq '.steps += ["Playwright already installed"]')
  else
    result=$(echo "$result" | jq '.steps += ["Playwright not installed - run: npm install -D @playwright/test"]')
  fi

  local config_file="${project_root}/${PLAYWRIGHT_CONFIG}"
  if [[ ! -f "$config_file" ]]; then
    generate_playwright_config "$project_root" "$browser" > /dev/null
    result=$(echo "$result" | jq '.steps += ["Generated default playwright.config.ts"]')
  else
    result=$(echo "$result" | jq '.steps += ["playwright.config.ts exists"]')
  fi

  if $has_playwright && npx playwright --version &> /dev/null; then
    result=$(echo "$result" | jq '.steps += ["Browsers available"]')
  else
    result=$(echo "$result" | jq '.steps += ["Run: npx playwright install"]')
  fi

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

  cat > "$config_file" << EOF
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
      name: '${browser}',
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

  for arg in "$@"; do
    case "$arg" in
      --browser=*) browser="${arg#*=}" ;;
      --filter=*) filter="${arg#*=}" ;;
      --headed) headed=true ;;
      --debug) debug=true ;;
    esac
  done

  local results_dir timestamp framework result
  results_dir=$(browser_test_results_dir "$project_root")
  timestamp=$(browser_test_timestamp)
  framework=$(detect_browser_test_framework "$project_root")

  mkdir -p "$results_dir"

  result='{"success": false, "framework": "'"$framework"'", "timestamp": "'"$timestamp"'"}'

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

  echo "$result" > "${results_dir}/browser_test_${timestamp}.json"
  echo "$result"
}

run_playwright_tests() {
  local project_root="${1:-}"
  local browser="${2:-chromium}"
  local filter="${3:-}"
  local headed="${4:-false}"
  local debug="${5:-false}"

  local results_dir timestamp cmd output_file exit_code parsed
  results_dir=$(browser_test_results_dir "$project_root")
  timestamp=$(browser_test_timestamp)

  cmd="npx playwright test --project=$browser --reporter=json"

  if [[ -n "$filter" ]]; then
    cmd="$cmd --grep=\"$filter\""
  fi

  if [[ "$headed" == "true" ]]; then
    cmd="$cmd --headed"
  fi

  if [[ "$debug" == "true" ]]; then
    cmd="$cmd --debug"
  fi

  output_file="${results_dir}/playwright_output_${timestamp}.json"
  exit_code=0

  if timeout "$BROWSER_TIMEOUT" bash -c "cd '$project_root' && $cmd > '$output_file' 2>&1"; then
    exit_code=0
  else
    exit_code=$?
  fi

  parsed=$(parse_playwright_results "$output_file" "$exit_code")
  echo "$parsed"
}

run_cypress_tests() {
  local project_root="${1:-}"
  local browser="${2:-chromium}"
  local filter="${3:-}"

  local results_dir timestamp cmd output_file exit_code parsed
  results_dir=$(browser_test_results_dir "$project_root")
  timestamp=$(browser_test_timestamp)

  cmd="npx cypress run --browser=$browser --reporter=json"

  if [[ -n "$filter" ]]; then
    cmd="$cmd --spec=\"$filter\""
  fi

  output_file="${results_dir}/cypress_output_${timestamp}.json"
  exit_code=0

  if timeout "$BROWSER_TIMEOUT" bash -c "cd '$project_root' && $cmd > '$output_file' 2>&1"; then
    exit_code=0
  else
    exit_code=$?
  fi

  parsed=$(parse_cypress_results "$output_file" "$exit_code")
  echo "$parsed"
}

# ============================================================================
# 결과 파싱
# ============================================================================

parse_playwright_results() {
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
        {total: .stats.tests, passed: .stats.passed, failed: .stats.failed, skipped: .stats.skipped, duration: .stats.duration}
      else
        {total: 0, passed: 0, failed: 0, skipped: 0, duration: 0}
      end
    ' "$output_file" 2> /dev/null || echo '{"total":0,"passed":0,"failed":0,"skipped":0,"duration":0}')

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
    ' "$output_file" 2> /dev/null || echo '{"total":0,"passed":0,"failed":0,"skipped":0,"duration":0}')

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

detect_browser_test_framework() {
  local project_root="${1:-}"
  local package_json="${project_root}/package.json"

  if [[ -f "$package_json" ]]; then
    if grep -q '"@playwright/test"' "$package_json" 2> /dev/null; then
      echo "playwright"
      return 0
    fi

    if grep -q '"cypress"' "$package_json" 2> /dev/null; then
      echo "cypress"
      return 0
    fi
  fi

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

check_browser_availability() {
  local project_root="${1:-}"
  local browser="${2:-chromium}"

  local result='{"available": false, "browser": "'"$browser"'", "issues": []}'
  local framework
  framework=$(detect_browser_test_framework "$project_root")

  if [[ "$framework" == "playwright" ]]; then
    if npx playwright --version &> /dev/null; then
      result=$(echo "$result" | jq '.available = true')
    else
      result=$(echo "$result" | jq '.issues += ["Playwright browsers not installed. Run: npx playwright install"]')
    fi
  elif [[ "$framework" == "cypress" ]]; then
    if npx cypress --version &> /dev/null; then
      result=$(echo "$result" | jq '.available = true')
    else
      result=$(echo "$result" | jq '.issues += ["Cypress not properly installed"]')
    fi
  else
    result=$(echo "$result" | jq '.issues += ["No browser test framework detected"]')
  fi

  echo "$result"
}

install_browsers() {
  local project_root="${1:-}"
  local browser="${2:-chromium}"

  local framework result
  framework=$(detect_browser_test_framework "$project_root")
  result='{"success": false, "framework": "'"$framework"'", "browser": "'"$browser"'"}'

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
