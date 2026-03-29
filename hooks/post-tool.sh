#!/usr/bin/env bash
# post-tool.sh — 통합 PostToolUse 훅
# 파일 변경 추적, Bash 실행 로깅, Context Rot 추적
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/common.sh
source "${SCRIPT_DIR}/common.sh"

_harness_load_module "context-rot"
_harness_load_module "feature-context"
_harness_load_module "state-machine"

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
PAYLOAD=$(cat)
HARNESS_DIR=$(harness_runtime_dir "$PAYLOAD")
LOG_DIR="${HARNESS_DIR}/logs"
STATE_DIR="${HARNESS_DIR}/state"
PROJECT_ROOT=$(harness_project_root "$PAYLOAD")

mkdir -p "$LOG_DIR" "$STATE_DIR"

TOOL_NAME=$(json_query "$PAYLOAD" '.tool_name // .tool // ""')

# ============================================================================
# Context Rot 추적 - 도구 호출 카운터 증가
# ============================================================================
increment_tool_call_count "$PROJECT_ROOT"

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

    if [ -n "$FILE_PATH" ]; then
      FEATURE_PATH="$FILE_PATH"
      if [[ "$FEATURE_PATH" != /* ]]; then
        FEATURE_PATH="${PROJECT_ROOT}/${FEATURE_PATH}"
      fi

      INFERRED_FEATURE=$(infer_feature_from_path "$FEATURE_PATH" 2>/dev/null || true)
      if [ -n "$INFERRED_FEATURE" ]; then
        set_current_feature "$PROJECT_ROOT" "$INFERRED_FEATURE" >/dev/null 2>&1 || true
      fi
    fi

    sync_runtime_cache "$PROJECT_ROOT" >/dev/null 2>&1 || true
    ;;
  Bash|bash)
    # 실행 로깅
    echo "[$TIMESTAMP] BASH_EXECUTED" >> "${LOG_DIR}/session.log"
    ;;
esac

# ============================================================================
# Context Rot 점수 확인 및 이벤트 로그
# ============================================================================
CONTEXT_ROT_SCORE=$(get_context_rot_score "$PROJECT_ROOT")
CONTEXT_ROT_GRADE=$(get_context_rot_grade "$PROJECT_ROOT")

# Context Rot 감지 시 이벤트 로그
if [[ "$CONTEXT_ROT_GRADE" == "rot" ]]; then
  log_context_rot_event "$PROJECT_ROOT" "context_rot_detected" \
    "\"grade\":\"$CONTEXT_ROT_GRADE\",\"tool_calls\":$(get_tool_call_count "$PROJECT_ROOT")"

  # 세션 로그에 경고 기록
  echo "[$TIMESTAMP] CONTEXT_ROT_DETECTED score=$CONTEXT_ROT_SCORE grade=$CONTEXT_ROT_GRADE" >> "${LOG_DIR}/session.log"
fi

# 주의 단계일 때도 로그
if [[ "$CONTEXT_ROT_GRADE" == "caution" ]]; then
  echo "[$TIMESTAMP] CONTEXT_ROT_CAUTION score=$CONTEXT_ROT_SCORE" >> "${LOG_DIR}/session.log"
fi
