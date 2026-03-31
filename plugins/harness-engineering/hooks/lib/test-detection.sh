#!/usr/bin/env bash
# test-detection.sh — test-runner framework detection and command builders

set -euo pipefail

file_contains_pattern() {
  local file="${1:-}"
  local pattern="${2:-}"

  [[ -f "$file" ]] || return 1
  grep -qE "$pattern" "$file" 2> /dev/null
}

python_project_uses_pytest() {
  local project_root="${1:-}"
  local pytest_pattern='(^|[^[:alnum:]_])pytest([^[:alnum:]_]|$)'

  if [[ -f "${project_root}/pytest.ini" ]] \
    || file_contains_pattern "${project_root}/setup.cfg" '^\[tool:pytest\]' \
    || file_contains_pattern "${project_root}/tox.ini" '^\[pytest\]' \
    || file_contains_pattern "${project_root}/pyproject.toml" '^\[tool\.pytest\.ini_options\]' \
    || file_contains_pattern "${project_root}/pyproject.toml" "$pytest_pattern" \
    || file_contains_pattern "${project_root}/Pipfile" "$pytest_pattern"; then
    return 0
  fi

  local requirements_file
  while IFS= read -r -d '' requirements_file; do
    if grep -qE "$pytest_pattern" "$requirements_file" 2> /dev/null; then
      return 0
    fi
  done < <(
    find "$project_root" -maxdepth 2 -type f \
      \( -name 'requirements*.txt' -o -name '*requirements*.txt' \) \
      -print0 2> /dev/null
  )

  return 1
}

detect_js_package_manager() {
  local project_root="${1:-}"
  local package_json="${project_root}/package.json"

  if file_contains_pattern "$package_json" '"packageManager"[[:space:]]*:[[:space:]]*"pnpm@'; then
    echo "pnpm"
    return 0
  fi

  if file_contains_pattern "$package_json" '"packageManager"[[:space:]]*:[[:space:]]*"yarn@'; then
    echo "yarn"
    return 0
  fi

  if file_contains_pattern "$package_json" '"packageManager"[[:space:]]*:[[:space:]]*"bun@'; then
    echo "bun"
    return 0
  fi

  if [[ -f "${project_root}/bun.lockb" ]] || [[ -f "${project_root}/bun.lock" ]]; then
    echo "bun"
    return 0
  fi

  if [[ -f "${project_root}/pnpm-lock.yaml" ]]; then
    echo "pnpm"
    return 0
  fi

  if [[ -f "${project_root}/yarn.lock" ]]; then
    echo "yarn"
    return 0
  fi

  if [[ -f "${project_root}/package-lock.json" ]] || [[ -f "${project_root}/npm-shrinkwrap.json" ]]; then
    echo "npm"
    return 0
  fi

  echo "npm"
}

get_js_test_runner_command() {
  local package_manager="${1:-npm}"
  local test_binary="${2:-}"

  case "$package_manager" in
    npm)
      echo "npx ${test_binary}"
      ;;
    pnpm)
      echo "pnpm exec ${test_binary}"
      ;;
    yarn)
      echo "yarn ${test_binary}"
      ;;
    bun)
      echo "bunx ${test_binary}"
      ;;
    *)
      echo "npx ${test_binary}"
      ;;
  esac
}

# ============================================================================
# 테스트 프레임워크 감지
# Usage: detect_test_framework <project_root>
# Returns: jest|vitest|mocha|pytest|unittest|go_test|cargo_test|maven|gradle|rspec|none
# ============================================================================
detect_test_framework() {
  local project_root="${1:-}"

  if [[ -f "${project_root}/package.json" ]]; then
    if grep -qE '"(jest|@types/jest)"' "${project_root}/package.json" 2> /dev/null; then
      echo "jest"
      return 0
    fi
    if grep -qE '"vitest"' "${project_root}/package.json" 2> /dev/null; then
      echo "vitest"
      return 0
    fi
    if grep -qE '"mocha"' "${project_root}/package.json" 2> /dev/null; then
      echo "mocha"
      return 0
    fi
    if ls "${project_root}"/vitest.config.* 1> /dev/null 2>&1; then
      echo "vitest"
      return 0
    fi
    if ls "${project_root}"/jest.config.* 1> /dev/null 2>&1; then
      echo "jest"
      return 0
    fi
  fi

  if python_project_uses_pytest "$project_root"; then
    echo "pytest"
    return 0
  fi

  if ls "${project_root}"/test_*.py 1> /dev/null 2>&1 \
    || ls "${project_root}"/tests/test_*.py 1> /dev/null 2>&1; then
    echo "unittest"
    return 0
  fi

  if [[ -f "${project_root}/go.mod" ]]; then
    echo "go_test"
    return 0
  fi

  if [[ -f "${project_root}/Cargo.toml" ]]; then
    echo "cargo_test"
    return 0
  fi

  if [[ -f "${project_root}/pom.xml" ]]; then
    echo "maven"
    return 0
  fi

  if [[ -f "${project_root}/build.gradle" ]] \
    || [[ -f "${project_root}/build.gradle.kts" ]]; then
    echo "gradle"
    return 0
  fi

  if [[ -f "${project_root}/Gemfile" ]] \
    && grep -qE "rspec" "${project_root}/Gemfile" 2> /dev/null; then
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
  local js_package_manager=""
  local js_runner=""

  case "$framework" in
    jest | vitest | mocha)
      js_package_manager=$(detect_js_package_manager "$project_root")
      js_runner=$(get_js_test_runner_command "$js_package_manager" "$framework")
      ;;
  esac

  case "$framework" in
    jest)
      if [[ -n "$test_filter" ]]; then
        echo "cd '$project_root' && $js_runner --testNamePattern='$test_filter' --json --outputFile=test-results.json"
      else
        echo "cd '$project_root' && $js_runner --json --outputFile=test-results.json"
      fi
      ;;
    vitest)
      if [[ -n "$test_filter" ]]; then
        echo "cd '$project_root' && $js_runner run -t '$test_filter' --reporter=json --outputFile=test-results.json"
      else
        echo "cd '$project_root' && $js_runner run --reporter=json --outputFile=test-results.json"
      fi
      ;;
    mocha)
      if [[ -n "$test_filter" ]]; then
        echo "cd '$project_root' && $js_runner --grep='$test_filter' --reporter json > test-results.json"
      else
        echo "cd '$project_root' && $js_runner --reporter json > test-results.json"
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
