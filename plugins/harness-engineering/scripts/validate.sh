#!/usr/bin/env bash
# validate.sh — Harness Engineering 검증 스크립트
# 사용법: bash scripts/validate.sh [--quick|--full]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ERRORS=0
WARNINGS=0

MODE="${1:---quick}"
TEST_SUITE_TIMEOUT_SECONDS="${HARNESS_TEST_SUITE_TIMEOUT_SECONDS:-}"

if [[ "$MODE" != "--quick" && "$MODE" != "--full" ]]; then
  echo "Usage: bash scripts/validate.sh [--quick|--full]"
  exit 1
fi

if [[ -z "$TEST_SUITE_TIMEOUT_SECONDS" ]] && [[ "${CI:-}" == "true" ]]; then
  TEST_SUITE_TIMEOUT_SECONDS=180
fi

run_test_suite() {
  local test_file="${1:-}"
  local label="${2:-$(basename "$test_file")}"
  local log_file exit_code

  log_file="$(mktemp "${TMPDIR:-/tmp}/harness-validate-test.XXXXXX")"

  echo "Running ${label}..."

  if [[ -n "$TEST_SUITE_TIMEOUT_SECONDS" ]] && command -v python3 > /dev/null 2>&1; then
    if python3 - "$test_file" "$log_file" "$TEST_SUITE_TIMEOUT_SECONDS" << 'PY'; then
import subprocess
import sys

test_file, log_file, timeout = sys.argv[1], sys.argv[2], int(sys.argv[3])

with open(log_file, "w", encoding="utf-8") as handle:
    try:
        subprocess.run(
            ["bash", test_file],
            stdout=handle,
            stderr=subprocess.STDOUT,
            check=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        handle.write(f"\n[TIMEOUT] exceeded {timeout}s while running {test_file}\n")
        sys.exit(124)
    except subprocess.CalledProcessError as exc:
        sys.exit(exc.returncode)
PY
      echo -e "${GREEN}[OK]${NC} ${label}"
      rm -f "$log_file"
      return 0
    fi

    exit_code=$?
  elif bash "$test_file" > "$log_file" 2>&1; then
    echo -e "${GREEN}[OK]${NC} ${label}"
    rm -f "$log_file"
    return 0
  else
    exit_code=$?
  fi

  if [[ "$exit_code" -eq 124 ]]; then
    echo -e "${RED}[ERROR]${NC} ${label} timed out after ${TEST_SUITE_TIMEOUT_SECONDS}s"
  else
    echo -e "${RED}[ERROR]${NC} ${label}"
  fi

  tail -20 "$log_file" || true
  rm -f "$log_file"
  return 1
}

run_shell_lint() {
  local lint_script="scripts/lint-shell.sh"

  if [[ ! -f "$lint_script" ]]; then
    echo -e "${YELLOW}[WARN]${NC} ${lint_script} not found"
    WARNINGS=$((WARNINGS + 1))
    return 0
  fi

  if ! command -v shellcheck > /dev/null 2>&1 || ! command -v shfmt > /dev/null 2>&1; then
    echo -e "${YELLOW}[WARN]${NC} shellcheck/shfmt not found (shell lint skipped)"
    WARNINGS=$((WARNINGS + 1))
    return 0
  fi

  if bash "$lint_script" --check > /tmp/harness-shell-lint.log 2>&1; then
    echo -e "${GREEN}[OK]${NC} shellcheck/shfmt passed"
    return 0
  fi

  echo -e "${RED}[ERROR]${NC} shellcheck/shfmt failed"
  tail -40 /tmp/harness-shell-lint.log || true
  return 1
}

run_quick_test_suites() {
  local test_file
  local quick_suites=(
    "hooks/__tests__/common.test.sh"
    "hooks/__tests__/feature-context.test.sh"
    "hooks/__tests__/hook-flow.test.sh"
    "hooks/__tests__/skill-evaluation.test.sh"
    "hooks/__tests__/state-machine.test.sh"
    "hooks/__tests__/test-runner.test.sh"
    "hooks/__tests__/wave-plan-contract.test.sh"
  )

  for test_file in "${quick_suites[@]}"; do
    if [[ ! -f "$test_file" ]]; then
      echo -e "${YELLOW}[WARN]${NC} Missing core test: $test_file"
      WARNINGS=$((WARNINGS + 1))
      continue
    fi

    if ! run_test_suite "$test_file" "$(basename "$test_file")"; then
      ERRORS=$((ERRORS + 1))
    fi
  done
}

run_full_test_suites() {
  local test_file
  local ran_any=false

  for test_file in hooks/__tests__/*.test.sh; do
    [[ -f "$test_file" ]] || continue
    ran_any=true

    if ! run_test_suite "$test_file" "$(basename "$test_file")"; then
      ERRORS=$((ERRORS + 1))
    fi
  done

  if [[ "$ran_any" == false ]]; then
    echo -e "${YELLOW}[WARN]${NC} No test suites found"
    WARNINGS=$((WARNINGS + 1))
  fi
}

count_test_cases() {
  local count
  if command -v rg > /dev/null 2>&1; then
    count=$(rg -n '^test_[a-zA-Z0-9_]+' hooks/__tests__/*.sh 2> /dev/null | wc -l | tr -d ' ')
  else
    count=$(find hooks/__tests__ -maxdepth 1 -name '*.sh' -exec grep -En '^test_[a-zA-Z0-9_]+' {} + 2> /dev/null | wc -l | tr -d ' ')
  fi
  echo "${count:-0}"
}

check_literal_present() {
  local file_path="${1:-}"
  local expected="${2:-}"
  local label="${3:-$file_path}"

  if grep -Fq -- "$expected" "$file_path" 2> /dev/null; then
    echo -e "${GREEN}[OK]${NC} ${label}"
    return 0
  fi

  echo -e "${RED}[ERROR]${NC} ${label}"
  echo "        expected: $expected"
  return 1
}

check_markdown_links() {
  local doc_file="${1:-}"
  local doc_dir target resolved broken found_any
  doc_dir="$(cd "$(dirname "$doc_file")" && pwd)"
  broken=0
  found_any=false

  while IFS= read -r target; do
    [[ -n "$target" ]] || continue
    found_any=true

    case "$target" in
      http://* | https://* | mailto:* | file://* | app://* | plugin://* | collection://* | discussion://* | notion://* | view://*)
        continue
        ;;
      \#*)
        continue
        ;;
    esac

    target="${target%%\#*}"
    target="${target%%\?*}"
    [[ -n "$target" ]] || continue

    if [[ "$target" == /* ]]; then
      resolved="$target"
    else
      resolved="${doc_dir}/${target}"
    fi

    if [[ ! -e "$resolved" ]]; then
      echo -e "${RED}[ERROR]${NC} Broken link in ${doc_file}: ${target}"
      ERRORS=$((ERRORS + 1))
      broken=$((broken + 1))
    fi
  done < <(perl -ne '
    if (/^```/) { $in_fence = !$in_fence; next; }
    next if $in_fence;
    s/`[^`]*`//g;
    while(/\[[^][]*\]\(([^)]+)\)/g){ print "$1\n" }
  ' "$doc_file")

  if [[ "$found_any" == false ]] || [[ "$broken" -eq 0 ]]; then
    echo -e "${GREEN}[OK]${NC} ${doc_file} links"
  fi
}

validate_doc_consistency() {
  local skill_count agent_count suite_count case_count
  skill_count=$(find skills -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
  agent_count=$(find agents -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')
  suite_count=$(find hooks/__tests__ -maxdepth 1 -name '*.test.sh' | wc -l | tr -d ' ')
  case_count=$(count_test_cases)

  echo ""
  echo "--- 8. Documentation Consistency ---"

  while IFS= read -r doc_file; do
    [[ -n "$doc_file" ]] || continue
    check_markdown_links "$doc_file"
  done < <(
    printf '%s\n' "README.md"
    find docs -type f -name '*.md' | sort
  )

  if ! check_literal_present "README.md" "${agent_count}개 전문 에이전트(인지 모드)와 ${skill_count}개 실행 스킬" "README summary counts"; then
    ERRORS=$((ERRORS + 1))
  fi

  if ! check_literal_present "README.md" "├── agents/                         # 에이전트 (${agent_count}개)" "README agent tree count"; then
    ERRORS=$((ERRORS + 1))
  fi

  if ! check_literal_present "README.md" "├── skills/                         # 스킬 (${skill_count}개)" "README skill tree count"; then
    ERRORS=$((ERRORS + 1))
  fi

  if ! check_literal_present "README.md" "훅 테스트 (${suite_count} suites / ${case_count} cases)" "README test count"; then
    ERRORS=$((ERRORS + 1))
  fi

  if ! check_literal_present "docs/specs/fresh-context/plan.md" "- **Agent 시스템**: ${agent_count}개 전문 에이전트" "fresh-context agent count"; then
    ERRORS=$((ERRORS + 1))
  fi

  if ! check_literal_present "docs/specs/fresh-context/plan.md" "- **Skill 시스템**: ${skill_count}개 실행 스킬" "fresh-context skill count"; then
    ERRORS=$((ERRORS + 1))
  fi

  if ! check_literal_present "docs/analysis/analysis-report.md" "| **harness-engineering** | ${skill_count} |" "analysis-report skill count"; then
    ERRORS=$((ERRORS + 1))
  fi

  if ! check_literal_present "docs/analysis/project-analysis.md" "├── skills/                   # 스킬 (실행 절차, ${skill_count}개)" "project-analysis skill count"; then
    ERRORS=$((ERRORS + 1))
  fi
}

validate_wave_planner_boundary() {
  local search_pattern='resolve_task_dependency_layers_(bash|python)[[:space:]]*\('
  local allowed_files=(
    "hooks/lib/wave-graph.sh"
    "hooks/__tests__/wave-plan-contract.test.sh"
    "scripts/validate.sh"
  )
  local matches="" allowed_file match file_path is_allowed disallowed=0

  echo ""
  echo "--- 9. Wave Planner Boundary ---"

  if command -v rg > /dev/null 2>&1; then
    matches=$(rg -n "$search_pattern" hooks scripts 2> /dev/null || true)
  else
    matches=$(grep -REn "$search_pattern" hooks scripts 2> /dev/null || true)
  fi

  while IFS= read -r match; do
    [[ -n "$match" ]] || continue
    file_path="${match%%:*}"
    is_allowed=false

    for allowed_file in "${allowed_files[@]}"; do
      if [[ "$file_path" == "$allowed_file" ]]; then
        is_allowed=true
        break
      fi
    done

    if [[ "$is_allowed" == false ]]; then
      echo -e "${RED}[ERROR]${NC} Direct planner backend usage outside allowed boundary: ${match}"
      disallowed=$((disallowed + 1))
    fi
  done <<< "$matches"

  if [[ "$disallowed" -eq 0 ]]; then
    echo -e "${GREEN}[OK]${NC} Wave planner backend boundary intact"
    return 0
  fi

  ERRORS=$((ERRORS + disallowed))
  return 1
}

echo "========================================"
echo "Harness Engineering Validation"
echo "========================================"
echo "Mode: ${MODE#--}"
echo ""

# ============================================================================
# 1. 기본 검증
# ============================================================================

echo "--- 1. Basic Checks ---"

# Claude CLI 확인
if ! command -v claude > /dev/null 2>&1; then
  echo -e "${YELLOW}[WARN]${NC} claude CLI not found (optional for plugin validation)"
  WARNINGS=$((WARNINGS + 1))
else
  echo -e "${GREEN}[OK]${NC} claude CLI found"
fi

# jq 확인
if ! command -v jq > /dev/null 2>&1; then
  echo -e "${YELLOW}[WARN]${NC} jq not found (required for JSON validation)"
  WARNINGS=$((WARNINGS + 1))
else
  echo -e "${GREEN}[OK]${NC} jq found"
fi

# ============================================================================
# 2. Shell 정적 분석
# ============================================================================

echo ""
echo "--- 2. Shell Static Analysis ---"

if ! run_shell_lint; then
  ERRORS=$((ERRORS + 1))
fi

# ============================================================================
# 3. Plugin Manifest 검증
# ============================================================================

echo ""
echo "--- 3. Plugin Manifest ---"

if [[ -f ".claude-plugin/plugin.json" ]]; then
  if command -v jq > /dev/null 2>&1; then
    if jq empty .claude-plugin/plugin.json 2> /dev/null; then
      echo -e "${GREEN}[OK]${NC} plugin.json is valid JSON"

      # 필수 필드 확인
      required_fields=("name" "description")
      for field in "${required_fields[@]}"; do
        if jq -e ".$field" .claude-plugin/plugin.json > /dev/null 2>&1; then
          echo -e "${GREEN}[OK]${NC} Required field '$field' present"
        else
          echo -e "${RED}[ERROR]${NC} Missing required field '$field' in plugin.json"
          ERRORS=$((ERRORS + 1))
        fi
      done
    else
      echo -e "${RED}[ERROR]${NC} plugin.json is not valid JSON"
      ERRORS=$((ERRORS + 1))
    fi
  fi
else
  echo -e "${YELLOW}[WARN]${NC} .claude-plugin/plugin.json not found"
  WARNINGS=$((WARNINGS + 1))
fi

# ============================================================================
# 4. Hooks 검증
# ============================================================================

echo ""
echo "--- 4. Hooks ---"

# hooks.json 검증
if [[ -f "hooks/hooks.json" ]]; then
  if command -v jq > /dev/null 2>&1; then
    if jq empty hooks/hooks.json 2> /dev/null; then
      echo -e "${GREEN}[OK]${NC} hooks.json is valid JSON"
    else
      echo -e "${RED}[ERROR]${NC} hooks.json is not valid JSON"
      ERRORS=$((ERRORS + 1))
    fi
  fi
else
  echo -e "${YELLOW}[WARN]${NC} hooks/hooks.json not found"
  WARNINGS=$((WARNINGS + 1))
fi

# 훅 스크립트 문법 검사
hook_count=0
for hook in hooks/*.sh; do
  if [[ -f "$hook" ]]; then
    if bash -n "$hook" 2> /dev/null; then
      hook_count=$((hook_count + 1))
    else
      echo -e "${RED}[ERROR]${NC} Syntax error in $hook"
      ERRORS=$((ERRORS + 1))
    fi
  fi
done
echo -e "${GREEN}[OK]${NC} $hook_count hook scripts passed syntax check"

# lib 모듈 검증
lib_count=0
for lib in hooks/lib/*.sh; do
  if [[ -f "$lib" ]]; then
    if bash -n "$lib" 2> /dev/null; then
      lib_count=$((lib_count + 1))
    else
      echo -e "${RED}[ERROR]${NC} Syntax error in $lib"
      ERRORS=$((ERRORS + 1))
    fi
  fi
done
if [[ $lib_count -gt 0 ]]; then
  echo -e "${GREEN}[OK]${NC} $lib_count lib modules passed syntax check"
fi

# ============================================================================
# 5. Skills 검증
# ============================================================================

echo ""
echo "--- 5. Skills ---"

skill_count=0
skill_errors=0

for skill_dir in skills/*/; do
  if [[ -d "$skill_dir" ]]; then
    skill_name=$(basename "$skill_dir")
    skill_file="${skill_dir}SKILL.md"

    if [[ -f "$skill_file" ]]; then
      skill_count=$((skill_count + 1))

      # Frontmatter 검증
      if grep -q "^---" "$skill_file"; then
        # 필수 필드 확인
        required_fields=("name" "description" "user-invocable")
        missing_fields=0

        for field in "${required_fields[@]}"; do
          if ! grep -q "^${field}:" "$skill_file"; then
            echo -e "${YELLOW}[WARN]${NC} Skill '$skill_name' missing field '$field'"
            missing_fields=$((missing_fields + 1))
          fi
        done

        if [[ $missing_fields -eq 0 ]]; then
          : # OK, no output for passing skills
        else
          skill_errors=$((skill_errors + 1))
        fi
      else
        echo -e "${RED}[ERROR]${NC} Skill '$skill_name' missing frontmatter"
        skill_errors=$((skill_errors + 1))
      fi
    else
      echo -e "${RED}[ERROR]${NC} Missing SKILL.md in $skill_dir"
      skill_errors=$((skill_errors + 1))
    fi
  fi
done

if [[ $skill_errors -eq 0 ]]; then
  echo -e "${GREEN}[OK]${NC} All $skill_count skills validated"
else
  echo -e "${RED}[ERROR]${NC} $skill_errors skills have validation errors"
  ERRORS=$((ERRORS + skill_errors))
fi

# ============================================================================
# 6. Agents 검증
# ============================================================================

echo ""
echo "--- 6. Agents ---"

agent_count=0
agent_errors=0

for agent_file in agents/*.md; do
  if [[ -f "$agent_file" ]]; then
    agent_name=$(basename "$agent_file" .md)
    agent_count=$((agent_count + 1))

    # Agent 파일이 비어있지 않은지 확인
    if [[ ! -s "$agent_file" ]]; then
      echo -e "${RED}[ERROR]${NC} Agent '$agent_name' is empty"
      agent_errors=$((agent_errors + 1))
    fi
  fi
done

if [[ $agent_errors -eq 0 ]]; then
  echo -e "${GREEN}[OK]${NC} All $agent_count agents validated"
else
  echo -e "${RED}[ERROR]${NC} $agent_errors agents have validation errors"
  ERRORS=$((ERRORS + agent_errors))
fi

# ============================================================================
# 7. Templates 검증
# ============================================================================

echo ""
echo "--- 7. Templates ---"

template_count=0
required_templates=("plan.md" "design.md" "wrapup.md" "clarify.md")

for template in "${required_templates[@]}"; do
  if [[ -f "docs/templates/$template" ]]; then
    template_count=$((template_count + 1))
  else
    echo -e "${YELLOW}[WARN]${NC} Missing template: docs/templates/$template"
    WARNINGS=$((WARNINGS + 1))
  fi
done

echo -e "${GREEN}[OK]${NC} $template_count templates found"

# ============================================================================
# 8. 문서 일관성 검증
# ============================================================================

validate_doc_consistency

# ============================================================================
# 9. Wave Planner 경계 검증
# ============================================================================

validate_wave_planner_boundary

# ============================================================================
# 10. 단위 테스트 실행
# ============================================================================

echo ""
echo "--- 10. Test Suites ---"

if [[ "$MODE" == "--quick" ]]; then
  echo "Running core regression suites..."
  run_quick_test_suites
else
  echo "Running full test suite..."
  run_full_test_suites
fi

# ============================================================================
# 11. Plugin 검증 (claude CLI 있는 경우)
# ============================================================================

if command -v claude > /dev/null 2>&1; then
  echo ""
  echo "--- 11. Claude Plugin Validation ---"
  if [[ "${CI:-}" == "true" ]] && [[ "${HARNESS_VALIDATE_CLAUDE_IN_CI:-0}" != "1" ]]; then
    echo -e "${YELLOW}[WARN]${NC} Claude plugin validation skipped in CI"
    WARNINGS=$((WARNINGS + 1))
  elif claude plugin validate . 2> /dev/null; then
    echo -e "${GREEN}[OK]${NC} Claude plugin validation passed"
  else
    echo -e "${YELLOW}[WARN]${NC} Claude plugin validation failed (may be expected)"
    WARNINGS=$((WARNINGS + 1))
  fi
fi

# ============================================================================
# 결과 요약
# ============================================================================

echo ""
echo "========================================"
echo "Validation Summary"
echo "========================================"

if [[ $ERRORS -gt 0 ]]; then
  echo -e "${RED}✗ FAILED${NC}: $ERRORS error(s), $WARNINGS warning(s)"
  exit 1
elif [[ $WARNINGS -gt 0 ]]; then
  echo -e "${YELLOW}⚠ PASSED WITH WARNINGS${NC}: $WARNINGS warning(s)"
  exit 0
else
  echo -e "${GREEN}✓ ALL CHECKS PASSED${NC}"
  exit 0
fi
