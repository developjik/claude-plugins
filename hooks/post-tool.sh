#!/usr/bin/env bash
# post-tool.sh — 통합 PostToolUse 훅
# 파일 변경 추적, Bash 실행 로깅
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

TOOL_NAME=$(json_query "$PAYLOAD" '.tool_name // .tool // ""')

case "$TOOL_NAME" in
  Write|Edit|write|edit)
    # 파일 변경 추적
    FILE_PATH=$(json_query "$PAYLOAD" '.tool_input.file_path // .tool_input.path // .input.file_path // .input.path // ""')
    if [ -n "$FILE_PATH" ] && [ -f "$FILE_PATH" ]; then
      HASH=""
      if command -v md5sum &>/dev/null; then
        HASH=$(md5sum "$FILE_PATH" | cut -d' ' -f1)
      elif command -v md5 &>/dev/null; then
        HASH=$(md5 -q "$FILE_PATH")
      fi
      echo "[$TIMESTAMP] CHANGED $FILE_PATH $HASH" >> "${STATE_DIR}/changes.txt"
    fi
    ;;
  Bash|bash)
    # 실행 로깅
    echo "[$TIMESTAMP] BASH_EXECUTED" >> "${LOG_DIR}/session.log"
    ;;
esac
