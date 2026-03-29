#!/usr/bin/env bash
# session-start.sh — 세션 시작 훅
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/common.sh
source "${SCRIPT_DIR}/common.sh"

# 필요한 모듈 로드
_harness_load_module "automation-level"
_harness_load_module "context-rot"
_harness_load_module "cleanup"
_harness_load_module "feature-context"

PAYLOAD=$(cat)
HARNESS_DIR=$(harness_runtime_dir "$PAYLOAD")
LOG_DIR="${HARNESS_DIR}/logs"
STATE_DIR="${HARNESS_DIR}/state"
PROJECT_ROOT=$(harness_project_root "$PAYLOAD")

mkdir -p "$LOG_DIR" "$STATE_DIR"

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
SESSION_LOG="${LOG_DIR}/session.log"

# 세션 시작 기록
echo "[$TIMESTAMP] SESSION_START" >> "$SESSION_LOG"
echo "[$TIMESTAMP] PROJECT_ROOT=$PROJECT_ROOT" >> "$SESSION_LOG"

# Git 상태 감지
if command -v git &>/dev/null && git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
  BRANCH=$(git -C "$PROJECT_ROOT" branch --show-current 2>/dev/null || echo "detached")
  echo "[$TIMESTAMP] GIT_BRANCH=$BRANCH" >> "$SESSION_LOG"

  EXCLUDE_ENTRY=$(ensure_runtime_git_exclude "$PROJECT_ROOT")
  if [ -n "$EXCLUDE_ENTRY" ]; then
    echo "[$TIMESTAMP] GIT_EXCLUDE_ADDED=$EXCLUDE_ENTRY" >> "$SESSION_LOG"
  fi
fi

# PDCA 상태 캐시 초기화
ensure_harness_runtime_subdirs "$PROJECT_ROOT"
if [[ -f "$(harness_engine_dir_from_root "$PROJECT_ROOT")/state.json" ]]; then
  safe_sync_runtime_cache "$PROJECT_ROOT" >/dev/null 2>&1 || true
else
  echo "idle" > "$(harness_phase_file "$PROJECT_ROOT")"
  : > "$(harness_current_feature_file "$PROJECT_ROOT")"
fi
echo "" > "$(harness_current_agent_file "$PROJECT_ROOT")"
: > "$(harness_phase_start_file "$PROJECT_ROOT")"

# ============================================================================
# 자동화 레벨 설정 초기화
# ============================================================================
init_automation_config "$PROJECT_ROOT"

# 현재 자동화 레벨 조회 및 기록
CURRENT_LEVEL=$(get_automation_level "$PROJECT_ROOT")
echo "$CURRENT_LEVEL" > "$(harness_current_level_file "$PROJECT_ROOT")"

# 신뢰 점수 기반 추천 레벨 확인
TRUST_SCORE=$(get_trust_score "$PROJECT_ROOT")
RECOMMENDED_LEVEL=$(get_recommended_level "$PROJECT_ROOT")

echo "[$TIMESTAMP] AUTOMATION_LEVEL=$CURRENT_LEVEL" >> "$SESSION_LOG"
echo "[$TIMESTAMP] TRUST_SCORE=$TRUST_SCORE" >> "$SESSION_LOG"
echo "[$TIMESTAMP] RECOMMENDED_LEVEL=$RECOMMENDED_LEVEL" >> "$SESSION_LOG"

# 추천 레벨과 현재 레벨이 다르면 로그에 안내
if [ "$CURRENT_LEVEL" != "$RECOMMENDED_LEVEL" ]; then
  echo "[$TIMESTAMP] LEVEL_RECOMMENDATION: Current=$CURRENT_LEVEL, Recommended=$RECOMMENDED_LEVEL" >> "$SESSION_LOG"
  echo "[INFO] Based on trust score ($TRUST_SCORE), recommended automation level is $RECOMMENDED_LEVEL" >&2
  echo "[INFO] Current level is $CURRENT_LEVEL. To change, edit .harness/config.yaml" >&2
fi

# ============================================================================
# Context Rot 추적 초기화
# ============================================================================
record_session_start "$PROJECT_ROOT"

# Context Rot 상태 로그
CONTEXT_ROT_SCORE=$(get_context_rot_score "$PROJECT_ROOT")
CONTEXT_ROT_GRADE=$(get_context_rot_grade "$PROJECT_ROOT")

echo "[$TIMESTAMP] CONTEXT_ROT_SCORE=$CONTEXT_ROT_SCORE" >> "$SESSION_LOG"
echo "[$TIMESTAMP] CONTEXT_ROT_GRADE=$CONTEXT_ROT_GRADE" >> "$SESSION_LOG"

# Context Rot 이벤트 로그
log_context_rot_event "$PROJECT_ROOT" "session_start"

# ============================================================================
# Cleanup 핸들러 초기화
# ============================================================================
harness_init_cleanup
