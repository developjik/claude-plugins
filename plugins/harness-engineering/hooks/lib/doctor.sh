#!/usr/bin/env bash
# doctor.sh — 설치 진단 유틸리티
# /harness doctor 커맨드에서 호출
#
# DEPENDENCIES: (none)

# ============================================================================
# 진단 함수
# ============================================================================

# 색상 코드 (터미널 지원 시)
if [ -t 1 ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  NC='\033[0m'
else
  RED=''
  GREEN=''
  YELLOW=''
  BLUE=''
  NC=''
fi

# 상태 아이콘
PASS="✓"
FAIL="✗"
WARN="⚠"
INFO="ℹ"

# 진단 결과 카운터
DOCTOR_PASSED=0
DOCTOR_FAILED=0
DOCTOR_WARNINGS=0

# 결과 출력 함수
doctor_pass() {
  local message="$1"
  echo -e "${GREEN}${PASS} PASS${NC}: $message"
  DOCTOR_PASSED=$((DOCTOR_PASSED + 1))
}

doctor_fail() {
  local message="$1"
  local hint="${2:-}"
  echo -e "${RED}${FAIL} FAIL${NC}: $message"
  [ -n "$hint" ] && echo -e "  ${YELLOW}→ $hint${NC}"
  DOCTOR_FAILED=$((DOCTOR_FAILED + 1))
}

doctor_warn() {
  local message="$1"
  local hint="${2:-}"
  echo -e "${YELLOW}${WARN} WARN${NC}: $message"
  [ -n "$hint" ] && echo -e "  ${BLUE}→ $hint${NC}"
  DOCTOR_WARNINGS=$((DOCTOR_WARNINGS + 1))
}

doctor_info() {
  local message="$1"
  echo -e "${BLUE}${INFO} INFO${NC}: $message"
}

# ============================================================================
# 1. 의존성 확인
# ============================================================================

check_dependencies() {
  echo ""
  echo "=== 1. 의존성 확인 ==="

  # jq
  if command -v jq >/dev/null 2>&1; then
    local jq_version
    jq_version=$(jq --version 2>/dev/null || echo "unknown")
    doctor_pass "jq 설치됨 ($jq_version)"
  else
    doctor_fail "jq 미설치" "brew install jq 또는 apt install jq"
  fi

  # git
  if command -v git >/dev/null 2>&1; then
    local git_version
    git_version=$(git --version 2>/dev/null | head -1 || echo "unknown")
    doctor_pass "git 설치됨 ($git_version)"
  else
    doctor_fail "git 미설치" "brew install git 또는 apt install git"
  fi

  # sed
  if command -v sed >/dev/null 2>&1; then
    doctor_pass "sed 설치됨"
  else
    doctor_fail "sed 미설치" "기본 시스템 유틸리티"
  fi

  # tr
  if command -v tr >/dev/null 2>&1; then
    doctor_pass "tr 설치됨"
  else
    doctor_fail "tr 미설치" "coreutils 패키지 확인"
  fi

  # readlink (macOS는 greadlink 필요할 수 있음)
  if command -v readlink >/dev/null 2>&1; then
    doctor_pass "readlink 설치됨"
  elif command -v greadlink >/dev/null 2>&1; then
    doctor_pass "greadlink 설치됨 (macOS)"
  else
    doctor_warn "readlink/greadlink 미설치" "일부 경로 검증 기능이 제한될 수 있음"
  fi
}

# ============================================================================
# 2. 플러그인 구조 확인
# ============================================================================

check_plugin_structure() {
  echo ""
  echo "=== 2. 플러그인 구조 확인 ==="

  local plugin_root="${CLAUDE_PLUGIN_ROOT:-}"
  local project_root="${CLAUDE_PROJECT_DIR:-$(pwd)}"

  # 플러그인 루트 확인
  if [ -n "$plugin_root" ]; then
    doctor_pass "CLAUDE_PLUGIN_ROOT 설정됨: $plugin_root"
  else
    doctor_warn "CLAUDE_PLUGIN_ROOT 미설정" "현재 디렉토리에서 상대 경로 사용"
    plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  fi

  # 필수 디렉토리 확인
  local required_dirs=("agents" "skills" "hooks" "docs")
  for dir in "${required_dirs[@]}"; do
    if [ -d "${plugin_root}/${dir}" ]; then
      doctor_pass "디렉토리 존재: ${dir}/"
    else
      doctor_fail "디렉토리 누락: ${dir}/"
    fi
  done

  # hooks.json 확인
  if [ -f "${plugin_root}/hooks/hooks.json" ]; then
    doctor_pass "hooks/hooks.json 존재"
  else
    doctor_fail "hooks/hooks.json 누락"
  fi

  # 에이전트 파일 확인
  local agents=("strategist" "architect" "engineer" "guardian" "librarian" "debugger")
  local agent_count=0
  for agent in "${agents[@]}"; do
    if [ -f "${plugin_root}/agents/${agent}.md" ]; then
      agent_count=$((agent_count + 1))
    fi
  done
  if [ $agent_count -eq ${#agents[@]} ]; then
    doctor_pass "모든 에이전트 파일 존재 (${agent_count}/${#agents[@]})"
  else
    doctor_warn "일부 에이전트 파일 누락 (${agent_count}/${#agents[@]})"
  fi
}

# ============================================================================
# 3. 훅 스크립트 권한 확인
# ============================================================================

check_hook_permissions() {
  echo ""
  echo "=== 3. 훅 스크립트 권한 확인 ==="

  local plugin_root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
  local hook_scripts=(
    "hooks/session-start.sh"
    "hooks/session-end.sh"
    "hooks/pre-tool.sh"
    "hooks/post-tool.sh"
    "hooks/on-agent-start.sh"
    "hooks/on-agent-stop.sh"
  )

  for script in "${hook_scripts[@]}"; do
    local script_path="${plugin_root}/${script}"
    if [ -f "$script_path" ]; then
      if [ -x "$script_path" ]; then
        doctor_pass "실행 권한: ${script}"
      else
        doctor_warn "실행 권한 없음: ${script}" "chmod +x ${script}"
      fi
    else
      doctor_fail "파일 없음: ${script}"
    fi
  done
}

# ============================================================================
# 4. 런타임 디렉토리 테스트
# ============================================================================

check_runtime_directory() {
  echo ""
  echo "=== 4. 런타임 디렉토리 테스트 ==="

  local project_root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
  local harness_dir="${project_root}/.harness"

  # .harness 디렉토리 생성 테스트
  if mkdir -p "${harness_dir}/logs" "${harness_dir}/state" "${harness_dir}/backups" 2>/dev/null; then
    doctor_pass ".harness/ 디렉토리 생성 가능"

    # 쓰기 테스트
    local test_file="${harness_dir}/logs/doctor-test-$(date +%s).log"
    if echo "doctor test" > "$test_file" 2>/dev/null; then
      doctor_pass "로그 파일 쓰기 가능"
      rm -f "$test_file"
    else
      doctor_fail "로그 파일 쓰기 실패" "권한 확인 필요"
    fi

    # Git 저장소인 경우 .git/info/exclude 확인
    if [ -d "${project_root}/.git" ]; then
      doctor_info "Git 저장소 감지됨"
      local exclude_file="${project_root}/.git/info/exclude"
      if [ -f "$exclude_file" ] && grep -q ".harness" "$exclude_file" 2>/dev/null; then
        doctor_pass ".harness/가 .git/info/exclude에 등록됨"
      else
        doctor_warn ".harness/가 .git/info/exclude에 미등록" "세션 시작 시 자동 등록됨"
      fi
    fi
  else
    doctor_fail ".harness/ 디렉토리 생성 실패" "프로젝트 디렉토리 권한 확인"
  fi
}

# ============================================================================
# 5. 샘플 워크플로우 테스트
# ============================================================================

check_sample_workflow() {
  echo ""
  echo "=== 5. 샘플 워크플로우 테스트 ==="

  local plugin_root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
  local project_root="${CLAUDE_PROJECT_DIR:-$(pwd)}"

  # JSON 파싱 테스트
  local test_json='{"tool_name":"Bash","tool_input":{"command":"echo test"}}'
  if [ -f "${plugin_root}/hooks/lib/json-utils.sh" ]; then
    source "${plugin_root}/hooks/lib/json-utils.sh"
    local result
    result=$(json_query "$test_json" '.tool_name' 2>/dev/null)
    if [ "$result" = "Bash" ]; then
      doctor_pass "JSON 파싱 정상"
    else
      doctor_warn "JSON 파싱 결과 불일치: '$result'"
    fi
  else
    doctor_warn "json-utils.sh 미발견"
  fi

  # 훅 스크립트 문법 검사
  local pre_tool="${plugin_root}/hooks/pre-tool.sh"
  if [ -f "$pre_tool" ]; then
    if bash -n "$pre_tool" 2>/dev/null; then
      doctor_pass "pre-tool.sh 문법 검사 통과"
    else
      doctor_fail "pre-tool.sh 문법 오류"
    fi
  fi

  # 보안 검증 모듈 테스트
  if [ -f "${plugin_root}/hooks/lib/validation.sh" ]; then
    source "${plugin_root}/hooks/lib/validation.sh"
    if ! validate_file_path "../../../etc/passwd" "/home/user/project" 2>/dev/null; then
      doctor_pass "경로 순회 검증 정상 작동"
    else
      doctor_warn "경로 순회 검증이 차단하지 않음"
    fi
  else
    doctor_warn "validation.sh 미발견"
  fi
}

# ============================================================================
# 6. 설정 파일 확인
# ============================================================================

check_config_files() {
  echo ""
  echo "=== 6. 설정 파일 확인 ==="

  local project_root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
  local harness_dir="${project_root}/.harness"

  # config.yaml
  if [ -f "${harness_dir}/config.yaml" ]; then
    doctor_pass "config.yaml 존재"
    # 자동화 레벨 확인
    if grep -q "automation:" "${harness_dir}/config.yaml" 2>/dev/null; then
      doctor_info "자동화 설정 존재"
    fi
  else
    doctor_info "config.yaml 없음 (기본값 사용)"
  fi

  # 템플릿 디렉토리
  local plugin_root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
  local templates=("clarify.md" "plan.md" "design.md" "wrapup.md")
  local template_count=0
  for template in "${templates[@]}"; do
    if [ -f "${plugin_root}/docs/templates/${template}" ]; then
      template_count=$((template_count + 1))
    fi
  done
  if [ $template_count -eq ${#templates[@]} ]; then
    doctor_pass "모든 템플릿 파일 존재 (${template_count}/${#templates[@]})"
  else
    doctor_warn "일부 템플릿 파일 누락 (${template_count}/${#templates[@]})"
  fi
}

# ============================================================================
# 메인 진단 함수
# ============================================================================

run_doctor() {
  echo "========================================"
  echo "  Harness Engineering Doctor"
  echo "  설치 진단 도구"
  echo "========================================"
  echo ""
  doctor_info "진단 시작: $(date '+%Y-%m-%d %H:%M:%S')"
  doctor_info "프로젝트: ${CLAUDE_PROJECT_DIR:-$(pwd)}"

  check_dependencies
  check_plugin_structure
  check_hook_permissions
  check_runtime_directory
  check_sample_workflow
  check_config_files

  # 결과 요약
  echo ""
  echo "========================================"
  echo "  진단 결과 요약"
  echo "========================================"
  echo -e "${GREEN}통과: ${DOCTOR_PASSED}${NC}"
  echo -e "${YELLOW}경고: ${DOCTOR_WARNINGS}${NC}"
  echo -e "${RED}실패: ${DOCTOR_FAILED}${NC}"
  echo ""

  if [ $DOCTOR_FAILED -eq 0 ]; then
    if [ $DOCTOR_WARNINGS -eq 0 ]; then
      echo -e "${GREEN}✓ 모든 검사 통과! 플러그인이 정상 작동합니다.${NC}"
      return 0
    else
      echo -e "${YELLOW}⚠ 기본 기능은 작동하지만 일부 경고가 있습니다.${NC}"
      return 0
    fi
  else
    echo -e "${RED}✗ 일부 검사 실패. 위의 FAIL 항목을 확인하세요.${NC}"
    return 1
  fi
}

# 직접 실행 시 진단 실행
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  run_doctor
fi
