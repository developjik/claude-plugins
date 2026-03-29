#!/usr/bin/env bash
# on-agent-start.sh — 통합 SubagentStart 훅
# 에이전트 전환 시 PDCA 단계 자동 추적, 의존성 확인, 스킬 체인 검증
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/common.sh
source "${SCRIPT_DIR}/common.sh"
# shellcheck source=hooks/lib/skill-chain.sh
source "${SCRIPT_DIR}/lib/skill-chain.sh"

_harness_load_module "automation-level"
_harness_load_module "feature-context"
_harness_load_module "feature-registry"
_harness_load_module "phase-transition"

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
PAYLOAD=$(cat)
HARNESS_DIR=$(harness_runtime_dir "$PAYLOAD")
LOG_DIR="${HARNESS_DIR}/logs"
STATE_DIR="${HARNESS_DIR}/state"
PROJECT_ROOT=$(harness_project_root "$PAYLOAD")

mkdir -p "$LOG_DIR" "$STATE_DIR"

AGENT_NAME=$(json_query "$PAYLOAD" '.agent_name // .agent // ""')
PHASE=$(phase_for_agent "$AGENT_NAME")
PREVIOUS_PHASE=$(get_runtime_phase "$PROJECT_ROOT")

# 현재 에이전트 기록
echo "$AGENT_NAME" > "$(harness_current_agent_file "$PROJECT_ROOT")"

# 현재 시간 기록 (결과 요약용)
date +%s > "$(harness_phase_start_file "$PROJECT_ROOT")" 2>/dev/null || true

echo "[$TIMESTAMP] AGENT_START agent=$AGENT_NAME phase=$PHASE previous=$PREVIOUS_PHASE" >> "${LOG_DIR}/session.log"

# ============================================================================
# 스킬 체인 검증 (requires 필드 기반)
# ============================================================================
CURRENT_FEATURE=$(get_current_feature "$PROJECT_ROOT")

if [ -n "$CURRENT_FEATURE" ] && [ "$PHASE" != "unknown" ]; then
  # 에이전트에서 스킬 이름 추론
  SKILL_NAME=$(infer_skill_from_agent "$AGENT_NAME")

  # 스킬 체인 검증 (strict_mode=false: 경고만)
  CHAIN_RESULT=$(check_and_validate_chain "$SKILL_NAME" "$CURRENT_FEATURE" "false" 2>/dev/null || echo "")

  if [ -n "$CHAIN_RESULT" ]; then
    # 검증 결과 로깅
    echo "[$TIMESTAMP] SKILL_CHAIN_CHECK skill=$SKILL_NAME feature=$CURRENT_FEATURE" >> "${LOG_DIR}/skill-chain.log"

    # JSON 응답인 경우 파싱
    if echo "$CHAIN_RESULT" | jq -e . >/dev/null 2>&1; then
      DECISION=$(echo "$CHAIN_RESULT" | jq -r '.decision // "allow"')
      WARNING=$(echo "$CHAIN_RESULT" | jq -r '.warning // ""')

      if [ "$DECISION" == "block" ]; then
        echo "[$TIMESTAMP] SKILL_CHAIN_BLOCKED skill=$SKILL_NAME" >> "${LOG_DIR}/skill-chain.log"
        echo "$CHAIN_RESULT"
        exit 0
      elif [ -n "$WARNING" ] && [ "$WARNING" != "null" ]; then
        echo "[WARNING] $WARNING" >&2
      fi
    fi
  fi
fi

# ============================================================================
# 의존성 확인 (engineer 에이전트가 implement 단계 진입 시)
# ============================================================================
if [[ "$AGENT_NAME" == *"engineer"* ]] && [ "$PHASE" = "implement" ]; then
  if [ -n "$CURRENT_FEATURE" ]; then
    if ! check_dependency_conflicts "$PROJECT_ROOT" "$CURRENT_FEATURE"; then
      echo "[$TIMESTAMP] DEPENDENCY_CHECK FAILED for feature=$CURRENT_FEATURE" >> "${LOG_DIR}/dependencies.log"
      echo "[WARNING] Some dependencies for feature '$CURRENT_FEATURE' are not yet completed." >&2
      echo "[WARNING] Please ensure all prerequisite features are marked as 'Completed' in docs/features.md" >&2
    fi
  fi
fi

# ============================================================================
# 기능 레지스트리 존재 확인
# ============================================================================
if ! check_feature_registry "$PROJECT_ROOT"; then
  echo "[$TIMESTAMP] REGISTRY_CHECK FAILED" >> "${LOG_DIR}/registry.log"
  echo "[INFO] Feature registry (docs/features.md) not found. Creating or updating it is recommended." >&2
fi

# ============================================================================
# 자동화 레벨 기반 단계 전환 승인 확인
# ============================================================================
# 현재 자동화 레벨 조회
CURRENT_LEVEL=$(get_automation_level "$PROJECT_ROOT")
echo "$CURRENT_LEVEL" > "$(harness_current_level_file "$PROJECT_ROOT")"

# 단계 전환 감지 및 승인 확인
APPROVAL_NEEDED=$(handle_phase_transition_approval "$PROJECT_ROOT" "$PREVIOUS_PHASE" "$PHASE" "$CURRENT_LEVEL")

if [ "$APPROVAL_NEEDED" != "skip" ]; then
  echo "[$TIMESTAMP] PHASE_TRANSITION from=$PREVIOUS_PHASE to=$PHASE level=$CURRENT_LEVEL approval=$APPROVAL_NEEDED" >> "${LOG_DIR}/session.log"
fi

case "$APPROVAL_NEEDED" in
  true)
    echo "[APPROVAL REQUIRED] Phase transition: $PREVIOUS_PHASE → $PHASE" >&2
    echo "[APPROVAL REQUIRED] Automation level: $CURRENT_LEVEL" >&2
    echo "[APPROVAL REQUIRED] Please confirm to proceed, or edit .harness/config.yaml to change automation level" >&2
    ;;
  if_uncertain)
    echo "[INFO] Phase transition: $PREVIOUS_PHASE → $PHASE (Level: $CURRENT_LEVEL)" >&2
    echo "[INFO] If uncertain about this transition, please review before proceeding" >&2
    ;;
  false)
    echo "[INFO] Auto-proceed: $PREVIOUS_PHASE → $PHASE (Level: $CURRENT_LEVEL)" >&2
    ;;
esac

if is_managed_pdca_phase "$PHASE"; then
  record_phase_transition "$PROJECT_ROOT" "$PHASE" "$AGENT_NAME" "agent_start" >/dev/null 2>&1 || true
fi
