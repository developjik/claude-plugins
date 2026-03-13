#!/usr/bin/env bash
# on-agent-stop.sh — 통합 SubagentStop 훅
set -euo pipefail

LOG_DIR="${HOME}/.harness-engineering/logs"
STATE_DIR="${HOME}/.harness-engineering/state"
mkdir -p "$LOG_DIR"

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
PAYLOAD=$(cat)

AGENT_NAME=""
if command -v jq &>/dev/null; then
  AGENT_NAME=$(echo "$PAYLOAD" | jq -r '.agent_name // .agent // ""' 2>/dev/null || echo "")
fi

echo "[$TIMESTAMP] AGENT_STOP agent=$AGENT_NAME" >> "${LOG_DIR}/session.log"
echo "" > "${STATE_DIR}/current-agent.txt" 2>/dev/null || true
