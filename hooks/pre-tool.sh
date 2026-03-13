#!/usr/bin/env bash
# pre-tool.sh — 통합 PreToolUse 훅
# stdin으로 JSON 페이로드를 받아 도구 유형에 따라 분기
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/common.sh
source "${SCRIPT_DIR}/common.sh"

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
PAYLOAD=$(cat)
HARNESS_DIR=$(harness_runtime_dir "$PAYLOAD")
LOG_DIR="${HARNESS_DIR}/logs"
BACKUP_DIR="${HARNESS_DIR}/backups"

mkdir -p "$LOG_DIR" "$BACKUP_DIR"

# 도구 이름 추출 (jq 사용 가능 시)
TOOL_NAME=$(json_query "$PAYLOAD" '.tool_name // .tool // ""')

case "$TOOL_NAME" in
  Bash|bash)
    # 위험한 명령어 차단
    COMMAND=$(json_query "$PAYLOAD" '.tool_input.command // .input.command // ""')
    DANGEROUS_PATTERNS="rm -rf /|rm -rf ~|sudo rm|mkfs|dd if=|:(){|chmod -R 777 /"
    if echo "$COMMAND" | grep -qE "$DANGEROUS_PATTERNS"; then
      echo "[$TIMESTAMP] BLOCKED: $COMMAND" >> "${LOG_DIR}/security.log"
      echo '{"decision":"block","reason":"위험한 명령어가 감지되었습니다."}' 
      exit 0
    fi
    ;;
  Write|Edit|write|edit)
    # 편집 전 백업
    FILE_PATH=$(json_query "$PAYLOAD" '.tool_input.file_path // .tool_input.path // .input.file_path // .input.path // ""')
    if [ -n "$FILE_PATH" ] && [ -f "$FILE_PATH" ]; then
      BACKUP_NAME=$(echo "$FILE_PATH" | tr '/' '_')
      cp "$FILE_PATH" "${BACKUP_DIR}/${BACKUP_NAME}.$(date +%s).bak" 2>/dev/null || true
    fi
    ;;
esac
