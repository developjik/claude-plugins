#!/usr/bin/env bash
# on-agent-stop.sh — 통합 SubagentStop 훅
# 에이전트 종료 시 로깅 및 결과 요약
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/common.sh
source "${SCRIPT_DIR}/common.sh"
# shellcheck source=hooks/lib/result-summary.sh
source "${SCRIPT_DIR}/lib/result-summary.sh"

_harness_load_module "feature-context"
_harness_load_module "feature-sync"

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
PAYLOAD=$(cat)
PROJECT_ROOT=$(harness_project_root "$PAYLOAD")
HARNESS_DIR=$(harness_runtime_dir "$PAYLOAD")
LOG_DIR="${HARNESS_DIR}/logs"
STATE_DIR="${HARNESS_DIR}/state"

mkdir -p "$LOG_DIR" "$STATE_DIR"

AGENT_NAME=$(json_query "$PAYLOAD" '.agent_name // .agent // ""')

echo "[$TIMESTAMP] AGENT_STOP agent=$AGENT_NAME" >> "${LOG_DIR}/session.log"
echo "" > "$(harness_current_agent_file "$PROJECT_ROOT")" 2>/dev/null || true

# ============================================================================
# 결과 요약 (PDCA 스킬 완료 시)
# ============================================================================

# 현재 기능과 단계 가져오기
CURRENT_FEATURE=$(get_current_feature "$PROJECT_ROOT")
PHASE_START_TIME=$(cat "$(harness_phase_start_file "$PROJECT_ROOT")" 2>/dev/null || echo "")

if [ -n "$CURRENT_FEATURE" ] && [ -n "$AGENT_NAME" ]; then
  # 에이전트를 단계에 매핑
  case "$AGENT_NAME" in
    strategist|harness-engineering:strategist)
      PHASE="plan"
      ;;
    architect|harness-engineering:architect)
      PHASE="design"
      ;;
    engineer|harness-engineering:engineer)
      PHASE="implement"
      ;;
    guardian|harness-engineering:guardian)
      PHASE="check"
      ;;
    librarian|harness-engineering:librarian)
      PHASE="wrapup"
      ;;
    *)
      PHASE=""
      ;;
  esac

  # 결과 요약 생성
  if [ -n "$PHASE" ]; then
    # 시작 시간이 없으면 현재 시간 사용 (즉시 완료)
    if [ -z "$PHASE_START_TIME" ]; then
      PHASE_START_TIME=$(date +%s)
    fi

    # 결과 요약 출력
    generate_result_summary "$PHASE" "$CURRENT_FEATURE" "$PHASE_START_TIME"

    # 기능 레지스트리 자동 동기화
    sync_on_phase_complete "$PROJECT_ROOT" "$CURRENT_FEATURE" "$PHASE" 2>/dev/null || true
  fi
fi

# 세션 통계 (wrapup 완료 후)
if [ -n "$CURRENT_FEATURE" ] && { [ "$AGENT_NAME" == "librarian" ] || [ "$AGENT_NAME" == "harness-engineering:librarian" ]; }; then
  show_session_summary
fi
