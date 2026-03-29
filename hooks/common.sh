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
# 지연 초기화 시스템 (bash 3.2 호환)
# ============================================================================

# 모듈 로드 상태 추적 (연관 배열 대신 문자열 사용)
# bash 3.2는 declare -A를 지원하지 않으므로 콜론으로 구분된 문자열 사용
_HARNESS_LOADED_MODULES=""

# 모듈이 로드되었는지 확인
_harness_is_module_loaded() {
  local module_name="${1:-}"
  case ":${_HARNESS_LOADED_MODULES}:" in
    *":${module_name}:"*) return 0 ;;
    *) return 1 ;;
  esac
}

# 모듈을 로드됨으로 표시
_harness_mark_module_loaded() {
  local module_name="${1:-}"
  if [ -z "$_HARNESS_LOADED_MODULES" ]; then
    _HARNESS_LOADED_MODULES="${module_name}"
  else
    _HARNESS_LOADED_MODULES="${_HARNESS_LOADED_MODULES}:${module_name}"
  fi
}

# 모듈 로드 함수
_harness_load_module() {
  local module_name="${1:-}"
  local module_file="${LIB_DIR}/${module_name}.sh"

  # 이미 로드되었으면 종료
  if _harness_is_module_loaded "$module_name"; then
    return 0
  fi

  # 파일 존재 확인
  if [[ ! -f "$module_file" ]]; then
    echo "[WARN] Module not found: ${module_name}" >&2
    return 1
  fi

  # 모듈 source
  # shellcheck source=hooks/lib/*.sh
  source "$module_file"
  _harness_mark_module_loaded "$module_name"
}

# ============================================================================
# 핵심 모듈 로드 (항상 필요)
# ============================================================================

# json-utils: JSON 파싱 유틸리티 (필수)
_harness_load_module "json-utils"

# logging: 로깱 유틸리티 (필수)
_harness_load_module "logging"

# runtime-paths: .harness 경로 표준화 (필수)
_harness_load_module "runtime-paths"

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
  if declare -f harness_runtime_dir_from_root >/dev/null 2>&1; then
    harness_runtime_dir_from_root "$root"
  else
    printf '%s/.harness\n' "$root"
  fi
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
