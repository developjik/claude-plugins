#!/usr/bin/env bash
# session-start.sh — 세션 시작 훅
set -euo pipefail

HARNESS_DIR="${HOME}/.harness-engineering"
LOG_DIR="${HARNESS_DIR}/logs"
STATE_DIR="${HARNESS_DIR}/state"

mkdir -p "$LOG_DIR" "$STATE_DIR"

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
SESSION_LOG="${LOG_DIR}/session.log"

# 세션 시작 기록
echo "[$TIMESTAMP] SESSION_START" >> "$SESSION_LOG"

# Git 상태 감지
if command -v git &>/dev/null && git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
  BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")
  echo "[$TIMESTAMP] GIT_BRANCH=$BRANCH" >> "$SESSION_LOG"
fi

# PDCA 상태 초기화
echo "idle" > "${STATE_DIR}/pdca-phase.txt"
echo "" > "${STATE_DIR}/current-agent.txt"
