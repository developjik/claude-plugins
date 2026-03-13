#!/usr/bin/env bash
# session-end.sh — 세션 종료 훅
set -euo pipefail

LOG_DIR="${HOME}/.harness-engineering/logs"
mkdir -p "$LOG_DIR"

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
echo "[$TIMESTAMP] SESSION_END" >> "${LOG_DIR}/session.log"
