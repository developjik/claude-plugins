#!/usr/bin/env bash
# on-agent-stop.sh — 통합 SubagentStop 훅
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/common.sh
source "${SCRIPT_DIR}/common.sh"

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
PAYLOAD=$(cat)
HARNESS_DIR=$(harness_runtime_dir "$PAYLOAD")
LOG_DIR="${HARNESS_DIR}/logs"
STATE_DIR="${HARNESS_DIR}/state"

mkdir -p "$LOG_DIR" "$STATE_DIR"

AGENT_NAME=$(json_query "$PAYLOAD" '.agent_name // .agent // ""')

echo "[$TIMESTAMP] AGENT_STOP agent=$AGENT_NAME" >> "${LOG_DIR}/session.log"
echo "" > "${STATE_DIR}/current-agent.txt" 2>/dev/null || true
