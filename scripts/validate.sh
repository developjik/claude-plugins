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

if [[ "$MODE" != "--quick" && "$MODE" != "--full" ]]; then
  echo "Usage: bash scripts/validate.sh [--quick|--full]"
  exit 1
fi

run_test_suite() {
  local test_file="${1:-}"
  local label="${2:-$(basename "$test_file")}"

  if bash "$test_file" >/tmp/harness-validate-test.log 2>&1; then
    echo -e "${GREEN}[OK]${NC} ${label}"
    return 0
  fi

  echo -e "${RED}[ERROR]${NC} ${label}"
  tail -20 /tmp/harness-validate-test.log || true
  return 1
}

run_quick_test_suites() {
  local test_file
  local quick_suites=(
    "hooks/__tests__/common.test.sh"
    "hooks/__tests__/feature-context.test.sh"
    "hooks/__tests__/hook-flow.test.sh"
    "hooks/__tests__/state-machine.test.sh"
    "hooks/__tests__/test-runner.test.sh"
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
if ! command -v claude >/dev/null 2>&1; then
  echo -e "${YELLOW}[WARN]${NC} claude CLI not found (optional for plugin validation)"
  WARNINGS=$((WARNINGS + 1))
else
  echo -e "${GREEN}[OK]${NC} claude CLI found"
fi

# jq 확인
if ! command -v jq >/dev/null 2>&1; then
  echo -e "${YELLOW}[WARN]${NC} jq not found (required for JSON validation)"
  WARNINGS=$((WARNINGS + 1))
else
  echo -e "${GREEN}[OK]${NC} jq found"
fi

# ============================================================================
# 2. Plugin Manifest 검증
# ============================================================================

echo ""
echo "--- 2. Plugin Manifest ---"

if [[ -f ".claude-plugin/plugin.json" ]]; then
  if command -v jq >/dev/null 2>&1; then
    if jq empty .claude-plugin/plugin.json 2>/dev/null; then
      echo -e "${GREEN}[OK]${NC} plugin.json is valid JSON"

      # 필수 필드 확인
      required_fields=("name" "description")
      for field in "${required_fields[@]}"; do
        if jq -e ".$field" .claude-plugin/plugin.json >/dev/null 2>&1; then
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
# 3. Hooks 검증
# ============================================================================

echo ""
echo "--- 3. Hooks ---"

# hooks.json 검증
if [[ -f "hooks/hooks.json" ]]; then
  if command -v jq >/dev/null 2>&1; then
    if jq empty hooks/hooks.json 2>/dev/null; then
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
    if bash -n "$hook" 2>/dev/null; then
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
    if bash -n "$lib" 2>/dev/null; then
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
# 4. Skills 검증
# ============================================================================

echo ""
echo "--- 4. Skills ---"

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
# 5. Agents 검증
# ============================================================================

echo ""
echo "--- 5. Agents ---"

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
# 6. Templates 검증
# ============================================================================

echo ""
echo "--- 6. Templates ---"

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
# 7. 단위 테스트 실행
# ============================================================================

echo ""
echo "--- 7. Test Suites ---"

if [[ "$MODE" == "--quick" ]]; then
  echo "Running core regression suites..."
  run_quick_test_suites
else
  echo "Running full test suite..."
  run_full_test_suites
fi

# ============================================================================
# 8. Plugin 검증 (claude CLI 있는 경우)
# ============================================================================

if command -v claude >/dev/null 2>&1; then
  echo ""
  echo "--- 8. Claude Plugin Validation ---"
  if claude plugin validate . 2>/dev/null; then
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
