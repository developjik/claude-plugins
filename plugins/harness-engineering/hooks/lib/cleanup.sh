#!/usr/bin/env bash
# cleanup.sh — trap 핸들러 및 리소스 정리 유틸리티
# 스크립트 중단 시 임시 파일, lock 파일, 백업 파일 정리
#
# DEPENDENCIES: logging.sh

# ============================================================================
# 전역 변수
# ============================================================================

# 정리가 필요한 리소스 추적
_HARNESS_TEMP_FILES=()
_HARNESS_LOCK_FILES=()
_HARNESS_CLEANUP_REGISTERED=false

# ============================================================================
# 리소스 등록 함수
# ============================================================================

# 임시 파일 등록
# Usage: register_temp_file <file_path>
register_temp_file() {
  local file_path="${1:-}"

  if [ -z "$file_path" ]; then
    return 0
  fi

  _HARNESS_TEMP_FILES+=("$file_path")

  # trap 핸들러가 아직 등록되지 않았으면 등록
  if [ "$_HARNESS_CLEANUP_REGISTERED" = false ]; then
    _harness_register_cleanup_handler
  fi
}

# Lock 파일 등록
# Usage: register_lock_file <file_path>
register_lock_file() {
  local file_path="${1:-}"

  if [ -z "$file_path" ]; then
    return 0
  fi

  _HARNESS_LOCK_FILES+=("$file_path")

  if [ "$_HARNESS_CLEANUP_REGISTERED" = false ]; then
    _harness_register_cleanup_handler
  fi
}

# ============================================================================
# Trap 핸들러 등록
# ============================================================================

_harness_register_cleanup_handler() {
  trap '_harness_cleanup_on_exit' EXIT
  trap '_harness_cleanup_on_signal INT' INT
  trap '_harness_cleanup_on_signal TERM' TERM
  trap '_harness_cleanup_on_signal HUP' HUP
  trap '_harness_cleanup_on_signal QUIT' QUIT
  _HARNESS_CLEANUP_REGISTERED=true
}

# ============================================================================
# 정리 함수
# ============================================================================

# EXIT 시 정리
_harness_cleanup_on_exit() {
  local exit_code=$?

  # 임시 파일 정리
  for temp_file in "${_HARNESS_TEMP_FILES[@]}"; do
    if [ -f "$temp_file" ]; then
      rm -f "$temp_file" 2>/dev/null || true
    fi
  done

  # Lock 파일 해제
  for lock_file in "${_HARNESS_LOCK_FILES[@]}"; do
    if [ -f "$lock_file" ]; then
      # Lock 파일이 내 프로세스의 것인지 확인
      local lock_pid
      lock_pid=$(cat "$lock_file" 2>/dev/null || echo "")
      if [ "$lock_pid" = "$$" ]; then
        rm -f "$lock_file" 2>/dev/null || true
      fi
    fi
  done

  exit $exit_code
}

# 시그널 수신 시 정리
_harness_cleanup_on_signal() {
  local signal="${1:-UNKNOWN}"

  echo "[CLEANUP] Received SIG${signal}, cleaning up..." >&2

  # 임시 파일 정리
  for temp_file in "${_HARNESS_TEMP_FILES[@]}"; do
    if [ -f "$temp_file" ]; then
      rm -f "$temp_file" 2>/dev/null || true
    fi
  done

  # Lock 파일 해제
  for lock_file in "${_HARNESS_LOCK_FILES[@]}"; do
    if [ -f "$lock_file" ]; then
      local lock_pid
      lock_pid=$(cat "$lock_file" 2>/dev/null || echo "")
      if [ "$lock_pid" = "$$" ]; then
        rm -f "$lock_file" 2>/dev/null || true
      fi
    fi
  done

  # 시그널 핸들러 제거 후 재발생
  trap - INT TERM HUP QUIT
  kill -s "$signal" $$ 2>/dev/null || exit 1
}

# ============================================================================
# 유틸리티 함수
# ============================================================================

# 안전한 임시 파일 생성
# Usage: temp_file=$(create_temp_file [prefix] [directory])
#   그 후 register_temp_file "$temp_file" 를 직접 호출하여 등록
#   서브셸 문제 해결: 파일 생성과 등록을 분리
create_temp_file() {
  local prefix="${1:-harness}"
  local directory="${2:-${TMPDIR:-/tmp}}"
  local temp_file

  # 파일만 생성하고 경로 반환
  temp_file=$(mktemp "${directory}/${prefix}.XXXXXX" 2>/dev/null || echo "")

  if [ -n "$temp_file" ] && [ -f "$temp_file" ]; then
    echo "$temp_file"
    return 0
  else
    echo ""
    return 1
  fi
}

# 안전한 Lock 획득
# Usage: acquire_lock <lock_name> [timeout_seconds]
acquire_lock() {
  local lock_name="${1:-}"
  local timeout="${2:-30}"
  local project_root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
  local lock_dir="${project_root}/.harness/locks"
  local lock_file="${lock_dir}/${lock_name}.lock"

  if [ -z "$lock_name" ]; then
    return 1
  fi

  mkdir -p "$lock_dir"

  local waited=0
  while [ $waited -lt $timeout ]; do
    # Lock 획득 시도 (atomic)
    if (set -o noclobber; echo "$$" > "$lock_file") 2>/dev/null; then
      register_lock_file "$lock_file"
      return 0
    fi

    # 기존 Lock의 PID 확인
    local lock_pid
    lock_pid=$(cat "$lock_file" 2>/dev/null || echo "")

    # 프로세스가 살아있는지 확인
    if [ -n "$lock_pid" ] && ! kill -0 "$lock_pid" 2>/dev/null; then
      # 죽은 프로세스의 Lock 제거
      rm -f "$lock_file" 2>/dev/null || true
      continue
    fi

    sleep 1
    waited=$((waited + 1))
  done

  echo "[WARNING] Lock acquisition timeout: $lock_name" >&2
  return 1
}

# Lock 해제
# Usage: release_lock <lock_name>
release_lock() {
  local lock_name="${1:-}"
  local project_root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
  local lock_file="${project_root}/.harness/locks/${lock_name}.lock"

  if [ -z "$lock_name" ]; then
    return 1
  fi

  if [ -f "$lock_file" ]; then
    local lock_pid
    lock_pid=$(cat "$lock_file" 2>/dev/null || echo "")
    if [ "$lock_pid" = "$$" ]; then
      rm -f "$lock_file" 2>/dev/null || true
    fi
  fi

  # 등록된 Lock 목록에서 제거
  local new_locks=()
  for registered_lock in "${_HARNESS_LOCK_FILES[@]}"; do
    if [ "$registered_lock" != "$lock_file" ]; then
      new_locks+=("$registered_lock")
    fi
  done
  _HARNESS_LOCK_FILES=("${new_locks[@]+"${new_locks[@]}"}")

  return 0
}

# ============================================================================
# 백업 정리
# ============================================================================

# 오래된 백업 파일 정리
# Usage: cleanup_old_backups [max_age_days] [backup_dir]
cleanup_old_backups() {
  local max_age="${1:-7}"
  local backup_dir="${2:-}"
  local project_root="${CLAUDE_PROJECT_DIR:-$(pwd)}"

  if [ -z "$backup_dir" ]; then
    backup_dir="${project_root}/.harness/backups"
  fi

  if [ ! -d "$backup_dir" ]; then
    return 0
  fi

  # max_age일 이상 된 백업 파일 삭제
  find "$backup_dir" -name "*.bak" -type f -mtime +${max_age} -delete 2>/dev/null || true

  return 0
}

# ============================================================================
# 초기화
# ============================================================================

# 세션 시작 시 자동 정리 등록
harness_init_cleanup() {
  local project_root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
  local harness_dir="${project_root}/.harness"

  # 오래된 백업 정리
  cleanup_old_backups 7 "${harness_dir}/backups"

  # 오래된 로그 정리 (30일 이상)
  if [ -d "${harness_dir}/logs" ]; then
    find "${harness_dir}/logs" -name "*.log" -type f -mtime +30 -delete 2>/dev/null || true
    find "${harness_dir}/logs" -name "*.jsonl" -type f -mtime +30 -delete 2>/dev/null || true
  fi
}
