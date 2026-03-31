#!/usr/bin/env bash
# validation.sh — 입력 검증 유틸리티 함수
# 보안 강화: 경로 순회, 인젝션, 권한 검증
#
# DEPENDENCIES: logging.sh

# ============================================================================
# 파일 경로 검증
# ============================================================================

# 파일 경로가 안전한지 검증
# Returns: 0 (안전), 1 (위험)
validate_file_path() {
  local path="${1:-}"
  local project_root="${2:-}"
  local allow_create="${3:-false}"  # 존재하지 않는 파일도 허용할지

  # 빈 경로는 통과
  if [ -z "$path" ]; then
    return 0
  fi

  # 1. 경로 순회 패턴 검사 (Path Traversal)
  if [[ "$path" == *".."* ]]; then
    log_validation_error "path_traversal" "$path" "Path traversal detected"
    return 1
  fi

  # 2. 절대 경로로 시스템 디렉토리 접근 시도 검사
  # 주의: 프로젝트 루트가 시스템 경로 하위에 있을 수 있음 (예: /home/user/project)
  local system_paths=("/etc" "/root" "/var" "/usr" "/bin" "/sbin" "/opt" "/sys" "/proc")
  local normalized_path
  normalized_path=$(normalize_path "$path")

  # 프로젝트 루트 정규화
  local normalized_root=""
  if [ -n "$project_root" ]; then
    normalized_root=$(normalize_path "$project_root")
  fi

  for sys_path in "${system_paths[@]}"; do
    if [[ "$normalized_path" == "$sys_path"/* ]] || [[ "$normalized_path" == "$sys_path" ]]; then
      # 프로젝트 루트가 제공된 경우, 경로가 프로젝트 내부인지 확인
      if [ -n "$normalized_root" ] && [[ "$normalized_path" == "$normalized_root"* ]]; then
        # 프로젝트 내부의 시스템 경로는 허용 (예: /home/user/project)
        continue
      fi
      log_validation_error "system_path_access" "$path" "Attempt to access system directory: $sys_path"
      return 1
    fi
  done

  # /home, /Users는 별도 처리 (사용자 프로젝트가 여기 있을 수 있음)
  local user_paths=("/home" "/Users")
  for user_path in "${user_paths[@]}"; do
    if [[ "$normalized_path" == "$user_path"/* ]]; then
      # 프로젝트 루트가 제공된 경우
      if [ -n "$normalized_root" ]; then
        # 프로젝트 내부면 허용
        if [[ "$normalized_path" == "$normalized_root"* ]]; then
          continue
        fi
        # 프로젝트 외부의 다른 사용자 디렉토리는 차단
        # 예: 프로젝트가 /home/user1/project인데 /home/user2/.ssh 접근 시도
        local project_user_path="${user_path}/"
        if [[ "$normalized_root" == "$project_user_path"* ]]; then
          local root_user="${normalized_root#$project_user_path}"
          root_user="${root_user%%/*}"
          if [[ "$normalized_path" == "$project_user_path${root_user}"* ]]; then
            # 같은 사용자 디렉토리 내부면 허용
            continue
          else
            log_validation_error "other_user_access" "$path" "Attempt to access other user's directory"
            return 1
          fi
        fi
      fi
    fi
  done

  # 3. 심볼릭 링크 검사 (파일이 존재하는 경우만)
  if [ -e "$path" ] && [ -L "$path" ]; then
    local resolved_link
    resolved_link=$(readlink -f "$path" 2>/dev/null || greadlink -f "$path" 2>/dev/null || echo "")
    if [ -n "$resolved_link" ] && [ -n "$project_root" ]; then
      local normalized_root
      normalized_root=$(normalize_path "$project_root")
      if [[ "$resolved_link" != "$normalized_root"* ]]; then
        log_validation_error "symlink_escape" "$path" "Symlink points outside project: $resolved_link"
        return 1
      fi
    fi
  fi

  # 4. 특수 문자/제어 문자 검사
  if [[ "$path" =~ [[:cntrl:]] ]] || [[ "$path" == *$'\n'* ]] || [[ "$path" == *$'\0'* ]]; then
    log_validation_error "invalid_characters" "$path" "Control characters in path"
    return 1
  fi

  # 5. null byte 검사
  if [[ "$path" == *$'\x00'* ]]; then
    log_validation_error "null_byte" "$path" "Null byte in path"
    return 1
  fi

  # 6. 프로젝트 루트 내부인지 확인 (프로젝트 루트가 제공된 경우)
  if [ -n "$project_root" ] && [ "$allow_create" != "true" ]; then
    local normalized_root
    normalized_root=$(normalize_path "$project_root")

    # 파일이 존재하면 실제 경로 확인
    if [ -e "$path" ]; then
      local real_path
      real_path=$(cd "$(dirname "$path")" 2>/dev/null && pwd)/$(basename "$path") 2>/dev/null || echo ""
      if [ -n "$real_path" ] && [[ "$real_path" != "$normalized_root"* ]]; then
        log_validation_error "outside_project" "$path" "Path outside project root"
        return 1
      fi
    fi
  fi

  return 0
}

# ============================================================================
# 명령어 검증
# ============================================================================

# 명령어 인젝션 패턴 검사
# Returns: 0 (안전), 1 (위험)
validate_command() {
  local command="${1:-}"

  # 빈 명령어는 통과
  if [ -z "$command" ]; then
    return 0
  fi

  # 1. 명령어 치환 패턴 검사 (항상 위험)
  # 백틱과 $()는 항상 차단
  if [[ "$command" == *'`'* ]] || [[ "$command" == *'$('* ]]; then
    log_validation_error "command_substitution" "$command" "Command substitution detected"
    return 1
  fi

  # 1-2. 간접 변수 확장 차단 (${!var})
  if [[ "$command" =~ \$\{! ]]; then
    log_validation_error "indirect_expansion" "$command" "Indirect variable expansion detected"
    return 1
  fi

  # 1-3. 산술 확장 차단 ($(( )))
  if [[ "$command" =~ \$\(\( ]]; then
    log_validation_error "arithmetic_expansion" "$command" "Arithmetic expansion detected"
    return 1
  fi

  # 1-4. 프로세스 대체 차단 (<() >())
  if [[ "$command" == *'<('* ]] || [[ "$command" == *'>('* ]]; then
    log_validation_error "process_substitution" "$command" "Process substitution detected"
    return 1
  fi

  # 2. 명령어 체이닝 패턴 검사 (&&, ||, ;)
  # 허용된 파이프(|)를 제외하고 체이닝 차단
  # 주의: | 단독은 허용하되 ||는 차단
  if [[ "$command" == *'&&'* ]]; then
    log_validation_error "command_chaining" "$command" "Command chaining with && detected"
    return 1
  fi

  if [[ "$command" == *'||'* ]]; then
    log_validation_error "command_chaining" "$command" "Command chaining with || detected"
    return 1
  fi

  # 세미콜론 명령어 구분자 차단
  # 주의: 문자열 내 세미콜론은 허용할 수 있으나, 보안상 엄격하게 차단
  if [[ "$command" == *';'* ]]; then
    # Fixed: Check if semicolon is NOT at the end (which would be safe)
    # If the last character is not a semicolon, there's a semicolon in the middle
    local trimmed
    trimmed=$(echo "$command" | sed 's/[[:space:]]*$//')
    # Block if trimmed command contains semicolon AND doesn't end with semicolon
    # This catches "ls; whoami" but allows commands ending with just ";"
    if [[ "${trimmed: -1}" != ';' ]]; then
      # 중간에 세미콜론이 있으면 차단
      log_validation_error "command_separator" "$command" "Command separator ; detected"
      return 1
    fi
  fi

  # 3. 위험한 변수 확장 패턴 (${...})
  # ${var} 형식 중 위험한 것들 차단
  if [[ "$command" =~ \$\{[^}]*[[:space:]][^}]*\} ]]; then
    log_validation_error "variable_expansion" "$command" "Complex variable expansion detected"
    return 1
  fi

  # 4. 제어 문자 검사
  if [[ "$command" =~ [[:cntrl:]] ]]; then
    log_validation_error "control_chars" "$command" "Control characters in command"
    return 1
  fi

  # 5. null byte 검사
  if [[ "$command" == *$'\x00'* ]]; then
    log_validation_error "null_byte" "$command" "Null byte in command"
    return 1
  fi

  return 0
}

# ============================================================================
# 화이트리스트 매칭 (강화된 버전)
# ============================================================================

# 명령어가 화이트리스트 패턴과 정확히 매칭되는지 확인
# 전체 명령어가 화이트리스트 패턴으로 시작해야 함
match_whitelist_strict() {
  local command="${1:-}"
  shift
  local patterns=("$@")

  # 명령어 앞뒤 공백 제거
  local trimmed_command
  trimmed_command=$(echo "$command" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  for pattern in "${patterns[@]}"; do
    # 패턴도 공백 제거
    local trimmed_pattern
    trimmed_pattern=$(echo "$pattern" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # 정확히 일치하거나, 명령어가 패턴으로 시작하고 그 뒤에 안전한 문자만 있는 경우
    if [[ "$trimmed_command" == "$trimmed_pattern" ]]; then
      return 0
    fi

    # 패턴으로 시작하는 경우, 뒤에 오는 내용이 안전한지 확인
    if [[ "$trimmed_command" == "$trimmed_pattern"* ]]; then
      local suffix="${trimmed_command#${trimmed_pattern}}"
      # 접미사가 안전한지 확인
      # - 공백만 있거나
      # - 상대 경로만 허용 (/ 문자 없이, .. 없이)
      # 추가 인자가 없거나, 단일 상대 경로만 있는 경우 허용
      if [[ -z "$suffix" ]]; then
        return 0
      fi
      # 공백으로 시작하는 경우, 상대 경로만 허용
      if [[ "$suffix" =~ ^[[:space:]]+[a-zA-Z0-9_.-]+$ ]]; then
        return 0
      fi
      # 슬래시 없는 상대 경로 허용 (예: node_modules/project-a)
      # 하지만 절대 경로(/로 시작)는 차단
      if [[ "$suffix" =~ ^[[:space:]]*[a-zA-Z0-9_.-]+(/[a-zA-Z0-9_.-]+)*$ ]]; then
        # 경로 순회가 없어야 함
        if [[ "$suffix" != *".."* ]]; then
          return 0
        fi
      fi
    fi
  done

  return 1
}

# ============================================================================
# 유틸리티 함수
# ============================================================================

# 경로 정규화 (상대 경로 제거, 중복 슬래시 제거)
normalize_path() {
  local path="${1:-}"

  if [ -z "$path" ]; then
    echo ""
    return 0
  fi

  # 중복 슬래시 제거
  path=$(echo "$path" | tr -s '/')

  # ./ 제거
  path=$(echo "$path" | sed 's#/\./#/#g; s#^\./##; s#/\.$##')

  # realpath 사용 가능하면 사용
  if command -v realpath >/dev/null 2>&1 && [ -e "$path" ]; then
    realpath "$path" 2>/dev/null || echo "$path"
  elif command -v grealpath >/dev/null 2>&1 && [ -e "$path" ]; then
    grealpath "$path" 2>/dev/null || echo "$path"
  else
    echo "$path"
  fi
}

# 검증 에러 로깅
log_validation_error() {
  local error_type="${1:-}"
  local value="${2:-}"
  local message="${3:-}"
  local log_file="${VALIDATION_LOG:-/dev/stderr}"

  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')

  # 민감 정보 마스킹
  local masked_value
  masked_value=$(echo "$value" | sed 's/\(password\|token\|key\|secret\)=\S*/\1=***/gi' 2>/dev/null || echo "$value")

  echo "[$timestamp] [VALIDATION_ERROR] [$error_type] $message: $masked_value" >> "$log_file" 2>/dev/null || true
}

# ============================================================================
# 민감 파일 검증
# ============================================================================

# 파일이 민감한 정보를 포함할 수 있는지 확인
is_sensitive_file() {
  local path="${1:-}"

  local sensitive_patterns=(
    ".env"
    ".env."
    "credentials"
    "secrets"
    "private"
    "id_rsa"
    "id_ed25519"
    ".pem"
    ".key"
    "password"
    "token"
    "api_key"
    "access_key"
    ".netrc"
    "_netrc"
    ".pgpass"
    ".my.cnf"
  )

  local filename
  filename=$(basename "$path" 2>/dev/null || echo "")

  for pattern in "${sensitive_patterns[@]}"; do
    if [[ "$filename" == *"$pattern"* ]] || [[ "$filename" == "$pattern"* ]]; then
      return 0
    fi
  done

  return 1
}
