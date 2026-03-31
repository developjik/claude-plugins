#!/usr/bin/env bash
# worktree.sh — Git Worktree 관리 유틸리티
# 격리된 개발 환경을 위한 Worktree 생성/삭제 관리
#
# DEPENDENCIES: (none - standalone utility)

set -euo pipefail

# ============================================================================
# 설정
# ============================================================================
readonly WORKTREE_BASE_DIR=".claude/worktrees"
readonly WORKTREE_BRANCH_PREFIX="feature/"

# ============================================================================
# Worktree 생성
# Usage: worktree_setup <feature-slug>
# Output: Worktree 경로 정보
# ============================================================================
worktree_setup() {
  local feature_slug="${1:-}"

  if [[ -z "$feature_slug" ]]; then
    echo "ERROR: feature-slug is required"
    return 1
  fi

  # 현재 Git 저장소 확인
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "ERROR: Not a git repository"
    return 1
  fi

  local project_root
  project_root=$(git rev-parse --show-toplevel)

  # Worktree 디렉토리
  local worktree_dir="${project_root}/${WORKTREE_BASE_DIR}/${feature_slug}"
  local branch_name="${WORKTREE_BRANCH_PREFIX}${feature_slug}"

  # 이미 존재하는지 확인
  if [[ -d "$worktree_dir" ]]; then
    echo "Worktree already exists at: ${worktree_dir}"
    echo "To work on this feature, navigate to: ${worktree_dir}"
    return 0
  fi

  # 브랜치 존재 확인
  local branch_exists
  branch_exists=$(git branch --list "$branch_name" 2>/dev/null)

  # Worktree 생성
  mkdir -p "$(dirname "$worktree_dir")"

  if [[ -n "$branch_exists" ]]; then
    # 기존 브랜치로 Worktree 생성
    git worktree add "$worktree_dir" "$branch_name" 2>/dev/null
  else
    # 새 브랜치로 Worktree 생성
    git worktree add -b "$branch_name" "$worktree_dir" 2>/dev/null
  fi

  if [[ $? -eq 0 ]]; then
    echo "Worktree created at: ${worktree_dir}"
    echo "Branch: ${branch_name}"
    echo "To work on this feature, navigate to: ${worktree_dir}"
    return 0
  else
    echo "ERROR: Failed to create worktree"
    return 1
  fi
}

# ============================================================================
# Worktree 제거
# Usage: worktree_remove <feature-slug>
# ============================================================================
worktree_remove() {
  local feature_slug="${1:-}"

  if [[ -z "$feature_slug" ]]; then
    echo "ERROR: feature-slug is required"
    return 1
  fi

  local project_root
  project_root=$(git rev-parse --show-toplevel 2>/dev/null || echo "")

  if [[ -z "$project_root" ]]; then
    echo "ERROR: Not a git repository"
    return 1
  fi

  local worktree_dir="${project_root}/${WORKTREE_BASE_DIR}/${feature_slug}"

  if [[ ! -d "$worktree_dir" ]]; then
    echo "Worktree not found: ${worktree_dir}"
    return 0
  fi

  # Worktree 제거
  git worktree remove "$worktree_dir" 2>/dev/null

  if [[ $? -eq 0 ]]; then
    echo "Worktree removed: ${worktree_dir}"
    return 0
  else
    echo "WARNING: Could not remove worktree cleanly, attempting force remove"
    git worktree remove --force "$worktree_dir" 2>/dev/null
    return $?
  fi
}

# ============================================================================
# Worktree 목록
# Usage: worktree_list
# ============================================================================
worktree_list() {
  git worktree list 2>/dev/null || echo "No worktrees found"
}

# ============================================================================
# 메인 진입점
# ============================================================================
main() {
  local action="${1:-help}"
  shift || true

  case "$action" in
    setup|create|add)
      worktree_setup "$@"
      ;;
    remove|delete|rm)
      worktree_remove "$@"
      ;;
    list|ls)
      worktree_list
      ;;
    help|--help|-h)
      echo "Usage: worktree.sh <action> [args]"
      echo ""
      echo "Actions:"
      echo "  setup <feature-slug>  Create a new worktree for the feature"
      echo "  remove <feature-slug> Remove the worktree for the feature"
      echo "  list                  List all worktrees"
      ;;
    *)
      echo "Unknown action: $action"
      echo "Use 'worktree.sh help' for usage"
      return 1
      ;;
  esac
}

# 직접 실행 시 main 호출
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
