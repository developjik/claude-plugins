#!/usr/bin/env bash
# automation-level.sh — 자동화 레벨 (L0-L4) 관련 함수
# common.sh에서 분리된 모듈
#
# DEPENDENCIES: json-utils.sh, logging.sh

# ============================================================================
# 자동화 레벨 설정
# ============================================================================

# 기본 자동화 레벨
if [[ -z "${DEFAULT_AUTOMATION_LEVEL:-}" ]]; then
  readonly DEFAULT_AUTOMATION_LEVEL="L2"
fi

if [[ -z "${DEFAULT_TRUST_SCORE:-}" ]]; then
  readonly DEFAULT_TRUST_SCORE="0.5"
fi

# ============================================================================
# 자동화 레벨 조회
# Usage: get_automation_level <project_root>
# Returns: L0, L1, L2, L3, L4 (기본값: L2)
# ============================================================================
get_automation_level() {
  local project_root="${1:-}"
  local config_file="${project_root}/.harness/config.yaml"

  if [[ ! -f "$config_file" ]]; then
    echo "$DEFAULT_AUTOMATION_LEVEL"
    return 0
  fi

  # yq가 있으면 사용, 없으면 grep으로 대체
  if command -v yq &>/dev/null; then
    local level
    level=$(yq '.automation.level // ""' "$config_file" 2>/dev/null)
    if [[ -n "$level" && "$level" != "null" ]]; then
      echo "$level"
      return 0
    fi
  fi

  # yq 없이 grep으로 간단히 파싱
  local level_line
  level_line=$(grep -E "^\s*level:\s*" "$config_file" 2>/dev/null | head -1)
  if [[ -n "$level_line" ]]; then
    local level
    level=$(echo "$level_line" | sed 's/.*level:\s*//' | tr -d ' "'\''')
    if [[ "$level" =~ ^L[0-4]$ ]]; then
      echo "$level"
      return 0
    fi
  fi

  echo "$DEFAULT_AUTOMATION_LEVEL"
}

# ============================================================================
# 신뢰 점수 조회
# Usage: get_trust_score <project_root>
# Returns: 0.0 ~ 1.0 (기본값: 0.5)
# ============================================================================
get_trust_score() {
  local project_root="${1:-}"
  local trust_file="${project_root}/.harness/trust.json"

  if [[ ! -f "$trust_file" ]]; then
    echo "$DEFAULT_TRUST_SCORE"
    return 0
  fi

  if command -v jq &>/dev/null; then
    local score
    score=$(jq -r '.composite // 0.5' "$trust_file" 2>/dev/null)
    if [[ -n "$score" && "$score" != "null" ]]; then
      echo "$score"
      return 0
    fi
  fi

  echo "$DEFAULT_TRUST_SCORE"
}

# ============================================================================
# 단계 전환 승인 필요 여부 확인
# Usage: should_approve_transition <level> <transition>
# transition: clarify_to_plan, plan_to_design, design_to_do, do_to_check, check_to_wrapup
# implement/check 명칭도 내부적으로 동일 전환으로 처리
# Returns: true, false, if_uncertain
# ============================================================================
should_approve_transition() {
  local level="${1:-$DEFAULT_AUTOMATION_LEVEL}"
  local transition="${2:-}"

  case "$level" in
    L0)
      echo "true"
      ;;
    L1)
      case "$transition" in
        check_to_wrapup) echo "false" ;;
        *) echo "true" ;;
      esac
      ;;
    L2)
      case "$transition" in
        clarify_to_plan|plan_to_design) echo "if_uncertain" ;;
        *) echo "false" ;;
      esac
      ;;
    L3|L4)
      echo "false"
      ;;
    *)
      echo "false"
      ;;
  esac
}

# ============================================================================
# 현재 PDCA 단계에서 다음 단계로의 전환 이름 조회
# Usage: get_transition_name <from_phase> <to_phase>
# ============================================================================
get_transition_name() {
  local from_phase="${1:-}"
  local to_phase="${2:-}"

  case "${from_phase}_${to_phase}" in
    clarify_plan) echo "clarify_to_plan" ;;
    plan_design) echo "plan_to_design" ;;
    design_do|design_implement) echo "design_to_do" ;;
    do_check|implement_check) echo "do_to_check" ;;
    check_wrapup) echo "check_to_wrapup" ;;
    *) echo "" ;;
  esac
}

# ============================================================================
# 자동화 설정 파일 초기화
# Usage: init_automation_config <project_root>
# ============================================================================
init_automation_config() {
  local project_root="${1:-}"
  local harness_dir="${project_root}/.harness"
  local config_file="${harness_dir}/config.yaml"
  local trust_file="${harness_dir}/trust.json"

  mkdir -p "$harness_dir"

  # config.yaml 생성 (없을 경우만)
  if [[ ! -f "$config_file" ]]; then
    cat > "$config_file" << 'EOF'
# Harness Engineering 자동화 설정
# https://github.com/developjik/harness-engineering

automation:
  level: L2  # L0(Manual), L1(Guided), L2(Semi-Auto), L3(Auto), L4(Full-Auto)
  default_level: L2

trust:
  enabled: true
  auto_escalation: false
  auto_downgrade: true
  escalation_threshold: 0.8
  downgrade_threshold: 0.3

context_rot:
  threshold: 0.7
  weights:
    tokens: 0.4
    tasks: 0.3
    time: 0.3
EOF
    echo "[INFO] Created default config: $config_file" >&2
  fi

  # trust.json 생성 (없을 경우만)
  if [[ ! -f "$trust_file" ]]; then
    cat > "$trust_file" << EOF
{
  "version": "1.0",
  "updated_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "scores": {
    "track_record": 0.5,
    "quality_metrics": 0.5,
    "velocity": 0.5,
    "user_ratings": 0.5,
    "decision_accuracy": 0.5,
    "safety": 1.0
  },
  "composite": 0.55,
  "history": []
}
EOF
    echo "[INFO] Created default trust file: $trust_file" >&2
  fi
}

# ============================================================================
# 결정 로그 기록
# Usage: log_decision <project_root> <event_type> <details_json>
# ============================================================================
log_decision() {
  local project_root="${1:-}"
  local event_type="${2:-}"
  local details="${3:-}"
  local log_dir="${project_root}/.harness/logs"
  local log_file="${log_dir}/decisions.jsonl"

  mkdir -p "$log_dir"

  local timestamp
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  local log_entry
  if [[ -n "$details" ]]; then
    if [[ "$details" == \{* ]]; then
      log_entry=$(jq -cn \
        --arg ts "$timestamp" \
        --arg event "$event_type" \
        --argjson details "$details" \
        '$details + {timestamp: $ts, event: $event}')
    else
      log_entry=$(printf '{"timestamp":"%s","event":"%s",%s}' "$timestamp" "$event_type" "$details")
    fi
  else
    log_entry=$(printf '{"timestamp":"%s","event":"%s"}' "$timestamp" "$event_type")
  fi

  echo "$log_entry" >> "$log_file"
}

# ============================================================================
# 승인 대기 상태 설정
# Usage: set_pending_approval <project_root> <transition> <reason>
# ============================================================================
set_pending_approval() {
  local project_root="${1:-}"
  local transition="${2:-}"
  local reason="${3:-}"
  local state_dir="${project_root}/.harness/state"

  mkdir -p "$state_dir"

  echo "pending" > "${state_dir}/approval-status.txt"
  echo "$transition" > "${state_dir}/approval-transition.txt"
  echo "$reason" > "${state_dir}/approval-reason.txt"
  echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" > "${state_dir}/approval-requested-at.txt"

  # 결정 로그 기록
  log_decision "$project_root" "approval_requested" \
    "\"transition\":\"$transition\",\"reason\":\"$reason\""
}

# ============================================================================
# 승인 상태 초기화
# Usage: clear_pending_approval <project_root>
# ============================================================================
clear_pending_approval() {
  local project_root="${1:-}"
  local state_dir="${project_root}/.harness/state"

  rm -f "${state_dir}/approval-status.txt"
  rm -f "${state_dir}/approval-transition.txt"
  rm -f "${state_dir}/approval-reason.txt"
  rm -f "${state_dir}/approval-requested-at.txt"
}

# ============================================================================
# 승인 대기 여부 확인
# Usage: is_pending_approval <project_root>
# Returns: true or false
# ============================================================================
is_pending_approval() {
  local project_root="${1:-}"
  local state_dir="${project_root}/.harness/state"
  local status_file="${state_dir}/approval-status.txt"

  if [[ -f "$status_file" ]] && [[ "$(cat "$status_file")" == "pending" ]]; then
    echo "true"
  else
    echo "false"
  fi
}

# ============================================================================
# 신뢰 점수 기반 추천 레벨 조회
# Usage: get_recommended_level <project_root>
# Returns: L0, L1, L2, L3, L4
# ============================================================================
get_recommended_level() {
  local project_root="${1:-}"
  local trust_score
  trust_score=$(get_trust_score "$project_root")

  # awk for floating point comparison
  local recommended
  recommended=$(awk -v score="$trust_score" 'BEGIN {
    if (score < 0.3) print "L0"
    else if (score < 0.5) print "L1"
    else if (score < 0.7) print "L2"
    else if (score < 0.85) print "L3"
    else print "L4"
  }')

  echo "$recommended"
}
