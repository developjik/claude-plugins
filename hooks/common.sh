#!/usr/bin/env bash
# common.sh — Harness 훅 공통 헬퍼 (리팩토링된 버전)
# 분리된 모듈들을 source하는 진입점 역할
#
# 리팩토링: 지연 초기화 패턴 도입
# - 핵심 모듈(json-utils, logging)만 항상 로드
# - 나머지 모듈은 실제 사용 시점에 로드
# - 초기 로딩 시간 단축
#

# ============================================================================
# 스크립트 디렉토리 및 상수
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

# ============================================================================
# 지연 초기화 시스템
# ============================================================================

# 모듈 로드 상태 추적
declare -A _HARNESS_MODULE_LOADED=(
  [json-utils]=false
  [logging]=false
  [validation]=false
  [state-machine]=false
  [subagent-spawner]=false
  [crash-recovery]=false
  [browser-testing]=false
  [feature-registry]=false
  [context-rot]=false
  [automation-level]=false
  [test-runner]=false
  [verification-classes]=false
  [review-engine]=false
  [skill-evaluation]=false
  [wave-executor]=false
  [hash-anchored-edit]=false
  [cleanup]=false
  [skill-chain]=false
  [worktree]=false
  [feature-sync]=false
  [lsp-tools]=false
  [browser-controller]=false
  [task-format]=false
)

# 모듈 로드 함수
_harness_load_module() {
  local module_name="${1:-}"
  local module_file="${LIB_DIR}/${module_name}.sh"

  # 이미 로드되었으면 종료
  if [[ "${_HARNESS_MODULE_LOADED[$module_name]}" == "true" ]]; then
    return 0
  fi

  # 파일 존재 확인
  if [[ ! -f "$module_file" ]]; then
    echo "[WARN] Module not found: ${module_name}" >&2
    return 1
  fi

  # 모듈 source
  source "$module_file"
  _HARNESS_MODULE_LOADED[$module_name]=true
}

# ============================================================================
# 핵심 모듈 로드 (항상 필요)
# ============================================================================

# json-utils: JSON 파싱 유틸리티 (필수)
_harness_load_module "json-utils"

# logging: 로깱 유틸리티 (필수)
_harness_load_module "logging"

# ============================================================================
# 지연 로드될 모듈들 (사용 시점에 자동 로드)
# 실제 사용되는 함수에서 필요한 모듈을 호출
# 예: validate_file_path() → validation.sh 로드
# ============================================================================

# 선택적 로드 헬퍼 (함수 내부에서 호출)
_harness_ensure_module() {
  local module_name="${1:-}"
  _harness_load_module "$module_name"
}

# ============================================================================
# 프로젝트 경로 관련 함수
# ============================================================================

harness_project_root() {
  local payload="${1:-}"
  local root=""

  if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
    root="${CLAUDE_PROJECT_DIR}"
  else
    root=$(json_query "$payload" '.cwd // .session.cwd // ""')
  fi

  if [ -z "$root" ] && command -v git >/dev/null 2>&1 && git rev-parse --show-toplevel >/dev/null 2>&1; then
    root=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
  fi

  if [ -z "$root" ]; then
    root=$(pwd -P)
  elif [ -d "$root" ]; then
    root=$(cd "$root" && pwd -P)
  fi

  printf '%s\n' "$root"
}

harness_runtime_dir() {
  local root
  root=$(harness_project_root "${1:-}")
  printf '%s/.harness\n' "$root"
}

ensure_runtime_git_exclude() {
  local project_root="${1:-}"
  local git_root=""
  local exclude_path=""
  local pattern=""

  if [ -z "$project_root" ] || ! command -v git >/dev/null 2>&1; then
    return 0
  fi

  if ! git -C "$project_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return 0
  fi

  git_root=$(git -C "$project_root" rev-parse --show-toplevel 2>/dev/null || echo "")
  exclude_path=$(git -C "$project_root" rev-parse --git-path info/exclude 2>/dev/null || echo "")

  if [ -z "$git_root" ] || [ -z "$exclude_path" ]; then
    return 0
  fi

  case "$exclude_path" in
    /*) ;;
    *) exclude_path="${project_root}/${exclude_path}" ;;
  esac

  case "$project_root" in
    "$git_root")
      pattern=".harness/"
      ;;
    "$git_root"/*)
      pattern="${project_root#"$git_root"/}/.harness/"
      ;;
    *)
      return 0
      ;;
  esac

  mkdir -p "$(dirname "$exclude_path")"
  touch "$exclude_path"

  if ! grep -Fqx "$pattern" "$exclude_path"; then
    printf '%s\n' "$pattern" >> "$exclude_path"
    printf '%s\n' "$pattern"
  fi
}

# ============================================================================
# 버전 정보
# ============================================================================

HARNESS_COMMON_VERSION="2.2.0"

harness_version() {
  echo "$HARNESS_COMMON_VERSION"
}

# ============================================================================
# 호환성 래퍼 함수
# ============================================================================

# detect_file_conflicts → check_dependency_conflicts로 이름 변경됨
# 기존 호출자를 위해 별칭 유지
detect_file_conflicts() {
  check_dependency_conflicts "$@"
}
