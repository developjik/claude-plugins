#!/usr/bin/env bash
# session-start.sh — 세션 시작 훅
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/common.sh
source "${SCRIPT_DIR}/common.sh"

PAYLOAD=$(cat)
HARNESS_DIR=$(harness_runtime_dir "$PAYLOAD")
LOG_DIR="${HARNESS_DIR}/logs"
STATE_DIR="${HARNESS_DIR}/state"
PROJECT_ROOT=$(harness_project_root "$PAYLOAD")

mkdir -p "$LOG_DIR" "$STATE_DIR"

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
SESSION_LOG="${LOG_DIR}/session.log"

# 세션 시작 기록
echo "[$TIMESTAMP] SESSION_START" >> "$SESSION_LOG"
echo "[$TIMESTAMP] PROJECT_ROOT=$PROJECT_ROOT" >> "$SESSION_LOG"

# Git 상태 감지
if command -v git &>/dev/null && git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
  BRANCH=$(git -C "$PROJECT_ROOT" branch --show-current 2>/dev/null || echo "detached")
  echo "[$TIMESTAMP] GIT_BRANCH=$BRANCH" >> "$SESSION_LOG"

  EXCLUDE_ENTRY=$(ensure_runtime_git_exclude "$PROJECT_ROOT")
  if [ -n "$EXCLUDE_ENTRY" ]; then
    echo "[$TIMESTAMP] GIT_EXCLUDE_ADDED=$EXCLUDE_ENTRY" >> "$SESSION_LOG"
  fi
fi

# PDCA 상태 초기화
echo "idle" > "${STATE_DIR}/pdca-phase.txt"
echo "" > "${STATE_DIR}/current-agent.txt"
