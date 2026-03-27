#!/usr/bin/env bash
# common.sh — Harness 훅 공통 헬퍼 (리팩토링된 버전)
# 분리된 모듈들을 source하는 진입점 역할

# ============================================================================
# 모듈 로드
# ============================================================================

# 스크립트 디렉토리 확인
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

# 분리된 모듈 로드
if [[ -d "$LIB_DIR" ]]; then
  source "${LIB_DIR}/json-utils.sh"
  source "${LIB_DIR}/context-rot.sh"
  source "${LIB_DIR}/automation-level.sh"
  source "${LIB_DIR}/feature-registry.sh"
  source "${LIB_DIR}/logging.sh"
  source "${LIB_DIR}/cleanup.sh"
  source "${LIB_DIR}/feature-sync.sh"
fi

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

HARNESS_COMMON_VERSION="2.1.0"

harness_version() {
  echo "$HARNESS_COMMON_VERSION"
}

# ============================================================================
# 호환성 래퍼 함수 (lib/feature-registry.sh로 위임)
# ============================================================================

# detect_file_conflicts → check_dependency_conflicts로 이름 변경됨
# 기존 호출자를 위해 별칭 유지
detect_file_conflicts() {
  check_dependency_conflicts "$@"
}
