#!/usr/bin/env bash
# pre-tool.sh — 통합 PreToolUse 훅
# stdin으로 JSON 페이로드를 받아 도구 유형에 따라 분기
set -euo pipefail

HARNESS_DIR="${HOME}/.harness-engineering"
LOG_DIR="${HARNESS_DIR}/logs"
BACKUP_DIR="${HARNESS_DIR}/backups"
mkdir -p "$LOG_DIR" "$BACKUP_DIR"

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
PAYLOAD=$(cat)

# 도구 이름 추출 (jq 사용 가능 시)
TOOL_NAME=""
if command -v jq &>/dev/null; then
  TOOL_NAME=$(echo "$PAYLOAD" | jq -r '.tool_name // .tool // ""' 2>/dev/null || echo "")
fi

case "$TOOL_NAME" in
  Bash|bash)
    # 위험한 명령어 차단
    COMMAND=$(echo "$PAYLOAD" | jq -r '.input.command // ""' 2>/dev/null || echo "")
    DANGEROUS_PATTERNS="rm -rf /|rm -rf ~|sudo rm|mkfs|dd if=|:(){|chmod -R 777 /"
    if echo "$COMMAND" | grep -qE "$DANGEROUS_PATTERNS"; then
      echo "[$TIMESTAMP] BLOCKED: $COMMAND" >> "${LOG_DIR}/security.log"
      echo '{"decision":"block","reason":"위험한 명령어가 감지되었습니다."}' 
      exit 0
    fi
    ;;
  Write|Edit|write|edit)
    # 편집 전 백업
    FILE_PATH=$(echo "$PAYLOAD" | jq -r '.input.file_path // .input.path // ""' 2>/dev/null || echo "")
    if [ -n "$FILE_PATH" ] && [ -f "$FILE_PATH" ]; then
      BACKUP_NAME=$(echo "$FILE_PATH" | tr '/' '_')
      cp "$FILE_PATH" "${BACKUP_DIR}/${BACKUP_NAME}.$(date +%s).bak" 2>/dev/null || true
    fi
    ;;
esac
