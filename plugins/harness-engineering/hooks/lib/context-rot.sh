#!/usr/bin/env bash
# context-rot.sh — Context Rot 감지 및 관리 함수
# common.sh에서 분리된 모듈
#
# DEPENDENCIES: json-utils.sh, logging.sh

# ============================================================================
# Context Rot 설정
# ============================================================================

# 토큰 추정 상수
readonly AVG_TOKENS_PER_TOOL_CALL=500
readonly MAX_CONTEXT_TOKENS=200000
readonly CONTEXT_ROT_CACHE_TTL=5

# 기본 임계값 (외부 설정 가능)
readonly DEFAULT_ROT_THRESHOLD="0.7"

# ============================================================================
# 세션 시작 시간 기록
# Usage: record_session_start <project_root>
# ============================================================================
record_session_start() {
  local project_root="${1:-}"
  local state_dir="${project_root}/.harness/state"

  mkdir -p "$state_dir"

  local now_epoch
  now_epoch=$(date +%s)

  echo "$now_epoch" > "${state_dir}/session-start-time"
  echo "0" > "${state_dir}/tool-call-count"
  echo "0.5" > "${state_dir}/context-rot-score"
  echo "$now_epoch" > "${state_dir}/context-rot-last-calc"
}

# ============================================================================
# 도구 호출 카운터 증가
# Usage: increment_tool_call_count <project_root>
# ============================================================================
increment_tool_call_count() {
  local project_root="${1:-}"
  local state_dir="${project_root}/.harness/state"
  local count_file="${state_dir}/tool-call-count"

  mkdir -p "$state_dir"

  local count=0
  if [[ -f "$count_file" ]]; then
    count=$(cat "$count_file" 2>/dev/null || echo "0")
  fi

  echo $((count + 1)) > "$count_file"
}

# ============================================================================
# Context Rot 점수 계산
# Usage: calculate_context_rot <project_root>
# Returns: 0.0 ~ 1.0
# ============================================================================
calculate_context_rot() {
  local project_root="${1:-}"
  local state_dir="${project_root}/.harness/state"

  # 캐시 확인 (5초 TTL)
  local cache_file="${state_dir}/context-rot-last-calc"
  local score_file="${state_dir}/context-rot-score"
  local now_epoch
  now_epoch=$(date +%s)

  if [[ -f "$cache_file" ]] && [[ -f "$score_file" ]]; then
    local last_calc
    last_calc=$(cat "$cache_file" 2>/dev/null || echo "0")
    local elapsed=$((now_epoch - last_calc))
    if [[ $elapsed -lt $CONTEXT_ROT_CACHE_TTL ]]; then
      cat "$score_file"
      return 0
    fi
  fi

  # 구성 요소 계산
  local tool_calls=0
  local session_start=0

  if [[ -f "${state_dir}/tool-call-count" ]]; then
    tool_calls=$(cat "${state_dir}/tool-call-count" 2>/dev/null || echo "0")
  fi

  if [[ -f "${state_dir}/session-start-time" ]]; then
    session_start=$(cat "${state_dir}/session-start-time" 2>/dev/null || echo "$now_epoch")
  fi

  local session_minutes=$(( (now_epoch - session_start) / 60 ))

  # 비율 계산 (0.0 ~ 1.0)
  local token_ratio task_ratio time_ratio

  token_ratio=$(awk -v calls="$tool_calls" -v avg="$AVG_TOKENS_PER_TOOL_CALL" -v max="$MAX_CONTEXT_TOKENS" 'BEGIN {
    ratio = (calls * avg) / max
    if (ratio > 1.0) ratio = 1.0
    printf "%.4f", ratio
  }')

  task_ratio=$(awk -v calls="$tool_calls" -v max_calls="50" 'BEGIN {
    ratio = calls / max_calls
    if (ratio > 1.0) ratio = 1.0
    printf "%.4f", ratio
  }')

  time_ratio=$(awk -v minutes="$session_minutes" -v max_minutes="60" 'BEGIN {
    ratio = minutes / max_minutes
    if (ratio > 1.0) ratio = 1.0
    printf "%.4f", ratio
  }')

  # 가중 평균 (토큰 40% + 작업 30% + 시간 30%)
  local score
  score=$(awk -v t="$token_ratio" -v k="$task_ratio" -v m="$time_ratio" 'BEGIN {
    score = (t * 0.4) + (k * 0.3) + (m * 0.3)
    printf "%.4f", score
  }')

  # 상태 파일 업데이트
  mkdir -p "$state_dir"
  echo "$score" > "$score_file"
  echo "$now_epoch" > "$cache_file"

  echo "$score"
}

# ============================================================================
# Context Rot 점수 조회 (캐시 활용)
# Usage: get_context_rot_score <project_root>
# Returns: 0.0 ~ 1.0
# ============================================================================
get_context_rot_score() {
  local project_root="${1:-}"
  calculate_context_rot "$project_root"
}

# ============================================================================
# 서브에이전트 사용 권장 여부
# Usage: should_use_subagent <project_root> [threshold]
# Returns: true or false
# ============================================================================
should_use_subagent() {
  local project_root="${1:-}"
  local threshold="${2:-$DEFAULT_ROT_THRESHOLD}"
  local score
  score=$(calculate_context_rot "$project_root")

  local result
  result=$(awk -v score="$score" -v thresh="$threshold" 'BEGIN {
    if (score >= thresh) print "true"
    else print "false"
  }')

  echo "$result"
}

# ============================================================================
# Context Rot 등급 조회
# Usage: get_context_rot_grade <project_root>
# Returns: healthy, caution, rot
# ============================================================================
get_context_rot_grade() {
  local project_root="${1:-}"
  local score
  score=$(calculate_context_rot "$project_root")

  local grade
  grade=$(awk -v score="$score" 'BEGIN {
    if (score < 0.5) print "healthy"
    else if (score < 0.7) print "caution"
    else print "rot"
  }')

  echo "$grade"
}

# ============================================================================
# Context Rot 이벤트 로그
# Usage: log_context_rot_event <project_root> <event_type> [details_json]
# ============================================================================
log_context_rot_event() {
  local project_root="${1:-}"
  local event_type="${2:-}"
  local details="${3:-}"
  local log_dir="${project_root}/.harness/logs"
  local log_file="${log_dir}/context-rot.jsonl"

  mkdir -p "$log_dir"

  local timestamp
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  local score
  score=$(calculate_context_rot "$project_root")

  local grade
  grade=$(get_context_rot_grade "$project_root")

  local tool_calls=0
  if [[ -f "${project_root}/.harness/state/tool-call-count" ]]; then
    tool_calls=$(cat "${project_root}/.harness/state/tool-call-count" 2>/dev/null || echo "0")
  fi

  local log_entry
  if [[ -n "$details" ]]; then
    log_entry=$(printf '{"timestamp":"%s","event":"%s","score":%.4f,"grade":"%s","tool_calls":%d,%s}' \
      "$timestamp" "$event_type" "$score" "$grade" "$tool_calls" "${details}")
  else
    log_entry=$(printf '{"timestamp":"%s","event":"%s","score":%.4f,"grade":"%s","tool_calls":%d}' \
      "$timestamp" "$event_type" "$score" "$grade" "$tool_calls")
  fi

  echo "$log_entry" >> "$log_file"
}

# ============================================================================
# Context Rot 상태 초기화
# Usage: reset_context_rot_state <project_root>
# ============================================================================
reset_context_rot_state() {
  local project_root="${1:-}"
  local state_dir="${project_root}/.harness/state"

  mkdir -p "$state_dir"

  local now_epoch
  now_epoch=$(date +%s)

  echo "$now_epoch" > "${state_dir}/session-start-time"
  echo "0" > "${state_dir}/tool-call-count"
  echo "0.5" > "${state_dir}/context-rot-score"
  echo "$now_epoch" > "${state_dir}/context-rot-last-calc"
}

# ============================================================================
# 세션 경과 시간 조회 (분)
# Usage: get_session_duration_minutes <project_root>
# Returns: 분 단위 정수
# ============================================================================
get_session_duration_minutes() {
  local project_root="${1:-}"
  local state_dir="${project_root}/.harness/state"
  local session_start_file="${state_dir}/session-start-time"

  if [[ ! -f "$session_start_file" ]]; then
    echo "0"
    return 0
  fi

  local session_start
  session_start=$(cat "$session_start_file" 2>/dev/null || echo "0")

  local now_epoch
  now_epoch=$(date +%s)

  local session_minutes=$(( (now_epoch - session_start) / 60 ))

  echo "$session_minutes"
}

# ============================================================================
# 도구 호출 횟수 조회
# Usage: get_tool_call_count <project_root>
# Returns: 정수
# ============================================================================
get_tool_call_count() {
  local project_root="${1:-}"
  local count_file="${project_root}/.harness/state/tool-call-count"

  if [[ ! -f "$count_file" ]]; then
    echo "0"
    return 0
  fi

  cat "$count_file" 2>/dev/null || echo "0"
}

# ============================================================================
# Context Rot 임계값 설정 조회
# Usage: get_rot_threshold <project_root>
# Returns: 0.0 ~ 1.0
# ============================================================================
get_rot_threshold() {
  local project_root="${1:-}"
  local config_file="${project_root}/.harness/config.yaml"

  if [[ ! -f "$config_file" ]]; then
    echo "$DEFAULT_ROT_THRESHOLD"
    return 0
  fi

  # yq가 있으면 사용
  if command -v yq &>/dev/null; then
    local threshold
    threshold=$(yq '.context_rot.threshold // ""' "$config_file" 2>/dev/null)
    if [[ -n "$threshold" && "$threshold" != "null" ]]; then
      echo "$threshold"
      return 0
    fi
  fi

  echo "$DEFAULT_ROT_THRESHOLD"
}
