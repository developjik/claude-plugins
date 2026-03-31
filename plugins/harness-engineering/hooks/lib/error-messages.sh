#!/usr/bin/env bash
# error-messages.sh — 사용자 친화적 에러 메시지 유틸리티
# 에러 코드, 대안, 문서 링크를 포함한 JSON 응답 생성
#
# DEPENDENCIES: logging.sh (for escape_json_string)

# ============================================================================
# 의존성 로드
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# logging.sh에서 escape_json_string 함수 로드
if [[ -f "${SCRIPT_DIR}/logging.sh" ]]; then
  # shellcheck source=hooks/lib/logging.sh
  source "${SCRIPT_DIR}/logging.sh"
fi

# ============================================================================
# 에러 코드 정의 (bash 3.2 호환)
# ============================================================================

# 에러 코드 조회 함수 (연관 배열 대신 case 문 사용)
get_error_code_name() {
  local code="${1:-}"
  case "$code" in
    # 명령어 관련 (E1xx)
    E101) echo "DANGEROUS_COMMAND" ;;
    E102) echo "COMMAND_SUBSTITUTION" ;;
    E103) echo "SYSTEM_DESTRUCTIVE" ;;
    E104) echo "PRIVILEGE_ESCALATION" ;;
    E105) echo "REMOTE_EXECUTION" ;;
    # 파일 경로 관련 (E2xx)
    E201) echo "PATH_TRAVERSAL" ;;
    E202) echo "SYSTEM_PATH_ACCESS" ;;
    E203) echo "SYMLINK_ESCAPE" ;;
    E204) echo "INVALID_CHARACTERS" ;;
    E205) echo "OUTSIDE_PROJECT" ;;
    # 권한 관련 (E3xx)
    E301) echo "PERMISSION_DENIED" ;;
    E302) echo "FILE_NOT_WRITABLE" ;;
    # 기타 (E4xx)
    E401) echo "SENSITIVE_FILE" ;;
    E402) echo "FILE_CONFLICT" ;;
    *) echo "UNKNOWN" ;;
  esac
}

# 에러 코드 이름으로 코드 조회
get_error_code_by_name() {
  local name="${1:-}"
  case "$name" in
    DANGEROUS_COMMAND) echo "E101" ;;
    COMMAND_SUBSTITUTION) echo "E102" ;;
    SYSTEM_DESTRUCTIVE) echo "E103" ;;
    PRIVILEGE_ESCALATION) echo "E104" ;;
    REMOTE_EXECUTION) echo "E105" ;;
    PATH_TRAVERSAL) echo "E201" ;;
    SYSTEM_PATH_ACCESS) echo "E202" ;;
    SYMLINK_ESCAPE) echo "E203" ;;
    INVALID_CHARACTERS) echo "E204" ;;
    OUTSIDE_PROJECT) echo "E205" ;;
    PERMISSION_DENIED) echo "E301" ;;
    FILE_NOT_WRITABLE) echo "E302" ;;
    SENSITIVE_FILE) echo "E401" ;;
    FILE_CONFLICT) echo "E402" ;;
    *) echo "E999" ;;
  esac
}

# ============================================================================
# 에러 메시지 생성 함수
# ============================================================================

# 사용자 친화적 에러 JSON 생성
# Usage: create_error_json <error_code> <reason> <suggestion> [doc_link]
create_error_json() {
  local error_code="${1:-E999}"
  local reason="${2:-알 수 없는 오류가 발생했습니다}"
  local suggestion="${3:-}"
  local doc_link="${4:-}"

  # JSON 이스케이프 처리
  local escaped_reason
  local escaped_suggestion
  local escaped_doc_link

  # escape_json_string 함수가 있으면 사용, 없으면 기본 이스케이프
  if declare -f escape_json_string >/dev/null 2>&1; then
    escaped_reason=$(escape_json_string "$reason")
    escaped_suggestion=$(escape_json_string "$suggestion")
    escaped_doc_link=$(escape_json_string "$doc_link")
  else
    # 폴백: 기본 이스케이프
    escaped_reason="${reason//\"/\\\"}"
    escaped_reason="${escaped_reason//\\/\\\\}"
    escaped_suggestion="${suggestion//\"/\\\"}"
    escaped_suggestion="${escaped_suggestion//\\/\\\\}"
    escaped_doc_link="${doc_link//\"/\\\"}"
    escaped_doc_link="${escaped_doc_link//\\/\\\\}"
  fi

  local json='{'
  json+='"decision":"block",'
  json+='"error_code":"'"$error_code"'",'
  json+='"reason":"'"$escaped_reason"'"'

  if [ -n "$escaped_suggestion" ]; then
    json+=',"suggestion":"'"$escaped_suggestion"'"'
  fi

  if [ -n "$escaped_doc_link" ]; then
    json+=',"doc_link":"'"$escaped_doc_link"'"'
  fi

  json+='}'

  echo "$json"
}

# ============================================================================
# 명령어 관련 에러 메시지
# ============================================================================

error_dangerous_command() {
  local command="${1:-}"
  local pattern="${2:-}"

  create_error_json \
    "E101" \
    "위험한 명령어가 감지되었습니다" \
    "안전한 대안을 사용하세요. 파일 삭제가 필요하면 'rm -rf ./target-directory' 형식을 사용하세요." \
    "https://docs.harness.dev/security/safe-commands"
}

error_command_substitution() {
  local command="${1:-}"

  create_error_json \
    "E102" \
    "명령어 치환(백틱 또는 \$())이 감지되었습니다: 보안상 차단됩니다" \
    "변수가 필요한 경우 별도로 실행 후 결과를 전달하세요." \
    "https://docs.harness.dev/security/command-injection"
}

error_system_destructive() {
  local command="${1:-}"

  create_error_json \
    "E103" \
    "시스템 파괴 가능성이 있는 명령어입니다" \
    "시스템 파일이나 디렉토리는 수정할 수 없습니다." \
    "https://docs.harness.dev/security/system-protection"
}

error_privilege_escalation() {
  local command="${1:-}"

  create_error_json \
    "E104" \
    "권한 상승(sudo)이 감지되었습니다" \
    "sudo가 필요한 작업은 터미널에서 직접 실행하세요." \
    "https://docs.harness.dev/security/privilege-escalation"
}

error_remote_execution() {
  local command="${1:-}"

  create_error_json \
    "E105" \
    "원격 코드 실행(curl | bash 등)이 감지되었습니다" \
    "스크립트를 먼저 다운로드하고 검토한 후 실행하세요." \
    "https://docs.harness.dev/security/remote-execution"
}

# ============================================================================
# 파일 경로 관련 에러 메시지
# ============================================================================

error_path_traversal() {
  local path="${1:-}"

  create_error_json \
    "E201" \
    "경로 순회(../)가 감지되었습니다: 프로젝트 외부 접근이 차단됩니다" \
    "프로젝트 내부의 상대 경로를 사용하세요. 예: './src/file.txt'" \
    "https://docs.harness.dev/security/path-traversal"
}

error_system_path_access() {
  local path="${1:-}"
  local system_path="${2:-}"

  create_error_json \
    "E202" \
    "시스템 경로 접근이 차단되었습니다: ${system_path}" \
    "프로젝트 디렉토리 내의 파일만 수정할 수 있습니다." \
    "https://docs.harness.dev/security/system-paths"
}

error_symlink_escape() {
  local path="${1:-}"
  local target="${2:-}"

  create_error_json \
    "E203" \
    "심볼릭 링크가 프로젝트 외부를 가리킵니다" \
    "프로젝트 내부의 파일만 참조하는 심볼릭 링크를 사용하세요." \
    "https://docs.harness.dev/security/symlink-safety"
}

error_invalid_characters() {
  local path="${1:-}"

  create_error_json \
    "E204" \
    "파일 경로에 유효하지 않은 문자가 포함되어 있습니다" \
    "경로에 제어 문자나 null byte를 사용할 수 없습니다." \
    "https://docs.harness.dev/security/invalid-characters"
}

error_outside_project() {
  local path="${1:-}"
  local project_root="${2:-}"

  create_error_json \
    "E205" \
    "프로젝트 외부 경로는 접근할 수 없습니다" \
    "프로젝트 루트(${project_root}) 내부의 파일만 수정할 수 있습니다." \
    "https://docs.harness.dev/security/project-boundary"
}

# ============================================================================
# 권한 관련 에러 메시지
# ============================================================================

error_permission_denied() {
  local path="${1:-}"

  create_error_json \
    "E301" \
    "파일에 대한 권한이 없습니다" \
    "파일 권한을 확인하거나 소유자에게 문의하세요." \
    "https://docs.harness.dev/security/permissions"
}

error_file_not_writable() {
  local path="${1:-}"

  create_error_json \
    "E302" \
    "파일에 쓸 수 없습니다" \
    "파일이 읽기 전용이거나 디스크가 꽉 찼을 수 있습니다." \
    "https://docs.harness.dev/security/file-permissions"
}

# ============================================================================
# 기타 경고 메시지
# ============================================================================

warning_sensitive_file() {
  local path="${1:-}"

  # 경고는 차단하지 않고 로그만 기록
  echo '{"decision":"allow","warning":"민감 파일에 접근합니다: '"$path"'","warning_code":"W401"}'
}

warning_file_conflict() {
  local path="${1:-}"
  local conflicting_feature="${2:-}"

  echo '{"decision":"allow","warning":"파일이 다른 기능('"$conflicting_feature"')과 충돌할 수 있습니다","warning_code":"W402"}'
}

# ============================================================================
# 성공 메시지 (필요시 사용)
# ============================================================================

success_backup_created() {
  local path="${1:-}"
  local backup_path="${2:-}"

  # 백업 성공은 조용히 처리 (로그만)
  : # no-op
}
