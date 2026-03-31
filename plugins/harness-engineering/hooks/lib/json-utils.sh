#!/usr/bin/env bash
# json-utils.sh — JSON 파싱 유틸리티 함수
# common.sh에서 분리된 모듈
#
# DEPENDENCIES: (none - base module)

# ============================================================================
# jq 설치 확인 (fail-safe)
# ============================================================================

# jq 설치 여부 확인 및 경고
# Returns: 0 (설치됨), 1 (미설치)
require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    printf '[ERROR] jq is required but not installed.\n' >&2
    printf '[ERROR] Install with: brew install jq (macOS) or apt install jq (Ubuntu)\n' >&2
    return 1
  fi
  return 0
}

# ============================================================================
# JSON 파싱 헬퍼 함수
# ============================================================================

json_query() {
  local payload="${1:-}"
  local query="${2:-}"

  if [ -z "$payload" ] || [ -z "$query" ]; then
    printf '\n'
    return 0
  fi

  # jq 필수 - 없으면 에러 반환
  if ! command -v jq >/dev/null 2>&1; then
    printf '[ERROR] jq not installed. Cannot parse JSON.\n' >&2
    return 1
  fi

  printf '%s' "$payload" | jq -r "$query" 2>/dev/null || printf '\n'
}

# ============================================================================
# 안전한 JSON 파싱 (입력 검증 포함)
# ============================================================================

safe_json_query() {
  local payload="${1:-}"
  local query="${2:-}"

  # 입력 검증
  if [ -z "$payload" ] || [ -z "$query" ]; then
    printf '\n'
    return 1
  fi

  # 기본 JSON 구조 검증
  if ! echo "$payload" | grep -q '^{.*}$' >/dev/null 2>&1; then
    printf '[ERROR] Invalid JSON payload\n' >&2
    return 1
  fi

  # 쿼리 인젝션 패턴 검사
  if echo "$query" | grep -qE '(rm|curl|wget|eval|exec)' >/dev/null 2>&1; then
    printf '[ERROR] Potentially unsafe query pattern detected\n' >&2
    return 1
  fi

  # jq 필수 - 없으면 에러 반환
  if ! command -v jq >/dev/null 2>&1; then
    printf '[ERROR] jq not installed. Cannot parse JSON.\n' >&2
    return 1
  fi

  printf '%s' "$payload" | jq -r "$query" 2>/dev/null || printf '\n'
}

# ============================================================================
# JSON 파일 읽기 (파일 존재 확인 포함)
# ============================================================================

read_json_file() {
  local file_path="${1:-}"
  local query="${2:-}"

  if [ ! -f "$file_path" ]; then
    printf '[ERROR] File not found: %s\n' "$file_path" >&2
    return 1
  fi

  # jq 필수 - 없으면 에러 반환
  if ! command -v jq >/dev/null 2>&1; then
    printf '[ERROR] jq not installed. Cannot read JSON file.\n' >&2
    return 1
  fi

  jq -r "$query" "$file_path" 2>/dev/null || printf '\n'
}
