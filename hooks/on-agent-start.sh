#!/usr/bin/env bash
# on-agent-start.sh — 통합 SubagentStart 훅
# 에이전트 전환 시 PDCA 단계 자동 추적
set -euo pipefail

HARNESS_DIR="${HOME}/.harness-engineering"
LOG_DIR="${HARNESS_DIR}/logs"
STATE_DIR="${HARNESS_DIR}/state"
mkdir -p "$LOG_DIR" "$STATE_DIR"

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
PAYLOAD=$(cat)

AGENT_NAME=""
if command -v jq &>/dev/null; then
  AGENT_NAME=$(echo "$PAYLOAD" | jq -r '.agent_name // .agent // ""' 2>/dev/null || echo "")
fi

# 현재 에이전트 기록
echo "$AGENT_NAME" > "${STATE_DIR}/current-agent.txt"

# 에이전트 → PDCA 단계 매핑
case "$AGENT_NAME" in
  strategist)  PHASE="plan" ;;
  architect)   PHASE="design" ;;
  engineer)    PHASE="do" ;;
  guardian)    PHASE="check" ;;
  librarian)   PHASE="wrapup" ;;
  debugger)    PHASE="debug" ;;
  *)           PHASE="unknown" ;;
esac

echo "$PHASE" > "${STATE_DIR}/pdca-phase.txt"
echo "[$TIMESTAMP] AGENT_START agent=$AGENT_NAME phase=$PHASE" >> "${LOG_DIR}/session.log"
