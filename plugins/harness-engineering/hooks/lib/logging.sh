#!/usr/bin/env bash
# logging.sh — 구조화된 로깅 시스템
# common.sh에서 분리된 모듈
#
# DEPENDENCIES: (none - base module)

# ============================================================================
# 로깅 설정
# ============================================================================

if [[ -z "${LOGGING_MODULE_INITIALIZED:-}" ]]; then
  readonly LOGGING_MODULE_INITIALIZED=1

  # 에러 코드 체계
  readonly E_SUCCESS=0
  readonly E_GENERAL=1
  readonly E_CONFIG=2
  readonly E_DEPENDENCY=3
  readonly E_EXECUTION=4
  readonly E_VALIDATION=5

  # 로그 레벨
  readonly LOG_LEVEL_DEBUG=0
  readonly LOG_LEVEL_INFO=1
  readonly LOG_LEVEL_WARN=2
  readonly LOG_LEVEL_ERROR=3

  # 현재 로그 레벨 (기본값: INFO)
  readonly CURRENT_LOG_LEVEL="${LOG_LEVEL_INFO}"

  # 민감 정보 패턴 (마스킹 대상)
  readonly SENSITIVE_PATTERNS=(
    "password"
    "token"
    "api_key"
    "secret"
    "credential"
    "auth"
    "--key"
    "--pass"
  )
fi

# ============================================================================
# 트레이스 ID 생성
# Usage: generate_trace_id
# Returns: 고유 트레이스 ID
# ============================================================================
generate_trace_id() {
  local timestamp
  timestamp=$(date +%s)
  local random=$RANDOM
  printf "trace_%s_%s" "$timestamp" "$random"
}

# ============================================================================
# 세션 트레이스 ID 조회/생성
# Usage: get_session_trace_id <project_root>
# Returns: 세션 트레이스 ID
# ============================================================================
get_session_trace_id() {
  local project_root="${1:-}"
  local state_dir="${project_root}/.harness/state"
  local trace_file="${state_dir}/trace-id"

  mkdir -p "$state_dir"

  if [[ -f "$trace_file" ]]; then
    cat "$trace_file"
    return 0
  fi

  local trace_id
  trace_id=$(generate_trace_id)
  echo "$trace_id" > "$trace_file"
  echo "$trace_id"
}

# ============================================================================
# JSON 이스케이프 처리
# Usage: escape_json_string <text>
# Returns: JSON 안전한 문자열
# ============================================================================
escape_json_string() {
  local text="${1:-}"

  # 백슬래시 먼저 이스케이프 (다른 이스케이프 전에)
  text="${text//\\/\\\\}"
  # 큰따옴표 이스케이프
  text="${text//\"/\\\"}"
  # 개행 문자 이스케이프
  text="${text//$'\n'/\\n}"
  text="${text//$'\r'/\\r}"
  # 탭 이스케이프
  text="${text//$'\t'/\\t}"
  # 역슬래시+제어문자 조합
  text=$(printf '%s' "$text" | sed 's/\x1b/\\u001b/g')

  printf '%s' "$text"
}

# ============================================================================
# 민감 정보 마스킹
# Usage: mask_sensitive_data <text>
# Returns: 마스킹된 텍스트
# ============================================================================
mask_sensitive_data() {
  local text="${1:-}"

  # 각 민감 패턴에 대해 마스킹 적용
  for pattern in "${SENSITIVE_PATTERNS[@]}"; do
    # password=xxx, --key=xxx 등의 패턴을 [REDACTED]로 치환
    # sed 특수 문자 이스케이프 (완전한 이스케이프)
    local escaped_pattern
    # sed BRE 특수 문자: . * [ ] ^ $ \( \) \{ \} \+ \? \|
    # sed 구분자: /
    # 문자 클래스 내 특수 문자: - (범위)
    escaped_pattern=$(printf '%s' "$pattern" | sed 's/[.[\*^$()+?{|\\]/\\&/g; s/-/\\-/g; s/\//\\\//g')
    text=$(printf '%s' "$text" | sed -E "s/(${escaped_pattern}[[:space:]]*=[[:space:]]*)[^[:space:]]+/\1[REDACTED]/gi" 2>/dev/null || printf '%s' "$text")
    text=$(printf '%s' "$text" | sed -E "s/(--${escaped_pattern}[[:space:]]*)[^[:space:]]+/\1[REDACTED]/gi" 2>/dev/null || printf '%s' "$text")
  done

  printf '%s' "$text"
}

# ============================================================================
# 구조화된 로그 이벤트 (JSONL)
# Usage: log_event <project_root> <level> <event_type> <message> [extra_json]
# ============================================================================
log_event() {
  local project_root="${1:-}"
  local level="${2:-INFO}"
  local event_type="${3:-}"
  local message="${4:-}"
  local extra="${5:-}"

  local log_dir="${project_root}/.harness/logs"
  local log_file="${log_dir}/events.jsonl"

  mkdir -p "$log_dir"

  # 트레이스 ID 조회
  local trace_id
  trace_id=$(get_session_trace_id "$project_root")

  # 타임스탬프
  local timestamp
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  # 메시지 마스킹 후 JSON 이스케이프
  local masked_message
  masked_message=$(mask_sensitive_data "$message")
  masked_message=$(escape_json_string "$masked_message")

  # 이벤트 타입과 extra도 이스케이프
  local escaped_event
  escaped_event=$(escape_json_string "$event_type")
  local escaped_extra=""
  if [[ -n "$extra" ]]; then
    escaped_extra=$(escape_json_string "$extra")
  fi

  # JSON 엔트리 생성
  local log_entry
  if [[ -n "$escaped_extra" ]]; then
    log_entry=$(printf '{"timestamp":"%s","trace_id":"%s","level":"%s","event":"%s","message":"%s",%s}' \
      "$timestamp" "$trace_id" "$level" "$escaped_event" "$masked_message" "${escaped_extra}")
  else
    log_entry=$(printf '{"timestamp":"%s","trace_id":"%s","level":"%s","event":"%s","message":"%s"}' \
      "$timestamp" "$trace_id" "$level" "$escaped_event" "$masked_message")
  fi

  echo "$log_entry" >> "$log_file"
}

# ============================================================================
# 편의 함수들
# ============================================================================

log_debug() {
  log_event "${1:-}" "DEBUG" "${2:-}" "${3:-}" "${4:-}"
}

log_info() {
  log_event "${1:-}" "INFO" "${2:-}" "${3:-}" "${4:-}"
}

log_warn() {
  log_event "${1:-}" "WARN" "${2:-}" "${3:-}" "${4:-}"
}

log_error() {
  log_event "${1:-}" "ERROR" "${2:-}" "${3:-}" "${4:-}"
}

# ============================================================================
# 로그 로테이션
# Usage: rotate_logs <project_root> [max_age_days]
# ============================================================================
rotate_logs() {
  local project_root="${1:-}"
  local max_age="${2:-30}"
  local log_dir="${project_root}/.harness/logs"

  if [[ ! -d "$log_dir" ]]; then
    return 0
  fi

  # 오래된 로그 파일 삭제
  find "$log_dir" -name "*.jsonl" -type f -mtime +$max_age -delete 2>/dev/null
  find "$log_dir" -name "*.log" -type f -mtime +$max_age -delete 2>/dev/null

  log_info "$project_root" "log_rotation" "Logs older than ${max_age} days removed"
}

# ============================================================================
# 에러 코드 반환
# Usage: get_error_message <error_code>
# Returns: 에러 메시지
# ============================================================================
get_error_message() {
  local error_code="${1:-0}"

  case "$error_code" in
    $E_SUCCESS) echo "Success" ;;
    $E_GENERAL) echo "General error" ;;
    $E_CONFIG) echo "Configuration error" ;;
    $E_DEPENDENCY) echo "Dependency error" ;;
    $E_EXECUTION) echo "Execution error" ;;
    $E_VALIDATION) echo "Validation error" ;;
    *) echo "Unknown error" ;;
  esac
}
