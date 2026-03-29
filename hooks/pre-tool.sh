#!/usr/bin/env bash
# pre-tool.sh — 통합 PreToolUse 훅
# stdin으로 JSON 페이로드를 받아 도구 유형에 따라 분기
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/common.sh
source "${SCRIPT_DIR}/common.sh"
# shellcheck source=hooks/lib/validation.sh
source "${SCRIPT_DIR}/lib/validation.sh"
# shellcheck source=hooks/lib/error-messages.sh
source "${SCRIPT_DIR}/lib/error-messages.sh"

_harness_load_module "feature-context"
_harness_load_module "feature-registry"

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
PAYLOAD=$(cat)
HARNESS_DIR=$(harness_runtime_dir "$PAYLOAD")
LOG_DIR="${HARNESS_DIR}/logs"
BACKUP_DIR="${HARNESS_DIR}/backups"
STATE_DIR="${HARNESS_DIR}/state"
PROJECT_ROOT=$(harness_project_root "$PAYLOAD")

# 검증 로그 파일 설정
export VALIDATION_LOG="${LOG_DIR}/validation.log"

mkdir -p "$LOG_DIR" "$BACKUP_DIR" "$STATE_DIR"

# 도구 이름 추출 (jq 사용 가능 시)
TOOL_NAME=$(json_query "$PAYLOAD" '.tool_name // .tool // ""')

case "$TOOL_NAME" in
  Bash|bash)
    # 위험한 명령어 차단 (강화된 패턴)
    COMMAND=$(json_query "$PAYLOAD" '.tool_input.command // .input.command // ""')

    # 위험 패턴 정의 (확장)
    # 블랙리스트: 절대 차단
    # Fixed: Changed regex patterns to literal strings for safer matching
    DANGEROUS_BLACKLIST=(
      "rm -rf /"
      "rm -rf /*"
      "rm -rf ~"
      "rm -rf $HOME"
      "sudo rm -rf"
      "mkfs"
      "dd if=/dev/zero"
      "dd if=/dev/urandom"
      ":(){ :|:& };:"
      "chmod -R 777 /"
      "chmod -R 777 ~"
      "> /dev/sd"
      "> /dev/hd"
      "| bash"
      "|  bash"
      "|bash"
      "| sh"
      "|  sh"
      "|sh"
      "|/bin/bash"
      "|/bin/sh"
      "curl "
      "wget "
      "eval "
      "exec "
      "rm -rf *"
      "rm -rf ./*"
      "rm -rf ../"
      "rm -rf /home"
      "rm -rf /Users"
      "rm -rf /etc"
      "rm -rf /var"
      "rm -rf /usr"
      "rm -rf /bin"
      "rm -rf /sbin"
      "rm -rf /opt"
      "shutdown"
      "reboot"
      "halt"
      "poweroff"
      "init 0"
      "init 6"
    )

    # 의심 패턴: 로그 기록 후 경고
    SUSPICIOUS_PATTERNS=(
      "rm -rf"
      "sudo "
      "chmod 777"
      "chown -R"
      "kill -9"
      "pkill -9"
      "killall"
      "iptables"
      "ufw"
      "firewall-cmd"
      "systemctl"
      "service "
      "env "
      "export "
      "unset "
      "source /etc"
      "cat /etc/passwd"
      "cat /etc/shadow"
      "cat ~/.ssh"
      "openssl"
      "gpg "
      "ssh-keygen"
    )

    # 화이트리스트: 안전한 명령어 (차단 패턴에 포함되어도 허용)
    # 강화된 매칭: 명령어가 정확히 화이트리스트 패턴으로 시작해야 함
    SAFE_WHITELIST=(
      "rm -rf .harness/"
      "rm -rf node_modules/"
      "rm -rf __pycache__/"
      "rm -rf .cache/"
      "rm -rf dist/"
      "rm -rf build/"
      "rm -rf coverage/"
      "rm -rf .pytest_cache/"
      "rm -rf .tox/"
      "rm -rf target/"
      "rm -rf .gradle/"
    )

    # 화이트리스트 확인 (강화된 매칭 사용)
    IS_SAFE=false
    if match_whitelist_strict "$COMMAND" "${SAFE_WHITELIST[@]}"; then
      IS_SAFE=true
    fi

    # 추가: 와일드카드 패턴 허용 (*.log, *.tmp 등) - 하지만 안전한 컨텍스트에서만
    if [[ "$IS_SAFE" == false ]]; then
      if [[ "$COMMAND" =~ ^rm[[:space:]]+-rf[[:space:]]+\*\.([a-zA-Z0-9]+)$ ]]; then
        # 단순한 와일드카드 패턴만 허용 (현재 디렉토리)
        IS_SAFE=true
      fi
    fi

    if [[ "$IS_SAFE" == false ]]; then
      # 블랙리스트 확인
      for dangerous_pattern in "${DANGEROUS_BLACKLIST[@]}"; do
        # Fixed: Use grep -qF for literal matching to prevent regex bypass
        if echo "$COMMAND" | grep -qF "$dangerous_pattern"; then
          echo "[$TIMESTAMP] BLOCKED (blacklist): $COMMAND" >> "${LOG_DIR}/security.log"
          log_event "$(harness_project_root "$PAYLOAD")" "WARN" "command_blocked" \
            "Blocked dangerous command" "\"command\":\"$(mask_sensitive_data "$COMMAND")\",\"pattern\":\"$dangerous_pattern\""
          # 사용자 친화적 에러 메시지 출력
          error_dangerous_command "$COMMAND" "$dangerous_pattern"
          exit 0
        fi
      done

      # 의심 패턴 확인 (경고만)
      for suspicious_pattern in "${SUSPICIOUS_PATTERNS[@]}"; do
        # Fixed: Use grep -qF for literal matching
        if echo "$COMMAND" | grep -qF "$suspicious_pattern"; then
          echo "[$TIMESTAMP] SUSPICIOUS: $COMMAND" >> "${LOG_DIR}/security.log"
          log_event "$(harness_project_root "$PAYLOAD")" "WARN" "suspicious_command" \
            "Suspicious command detected" "\"command\":\"$(mask_sensitive_data "$COMMAND")\",\"pattern\":\"$suspicious_pattern\""
          # 차단하지 않고 로그만 기록
          break
        fi
      done
    fi
    ;;
  Write|Edit|write|edit)
    # 파일 경로 추출
    FILE_PATH=$(json_query "$PAYLOAD" '.tool_input.file_path // .tool_input.path // .input.file_path // .input.path // ""')

    # 파일 경로 검증 (강화된 보안)
    if [ -n "$FILE_PATH" ]; then
      # 경로 순회 검사
      if [[ "$FILE_PATH" == *".."* ]]; then
        echo "[$TIMESTAMP] BLOCKED (path_traversal): $FILE_PATH" >> "${LOG_DIR}/security.log"
        log_event "$PROJECT_ROOT" "WARN" "path_blocked" \
          "Blocked path traversal" "\"path\":\"$(mask_sensitive_data "$FILE_PATH")\""
        error_path_traversal "$FILE_PATH"
        exit 0
      fi

      # 시스템 경로 검사
      normalized_path=$(echo "$FILE_PATH" | tr -s '/')
      system_paths=("/etc" "/root" "/var" "/usr" "/bin" "/sbin" "/opt" "/sys" "/proc")
      for sys_path in "${system_paths[@]}"; do
        if [[ "$normalized_path" == "$sys_path"/* ]]; then
          echo "[$TIMESTAMP] BLOCKED (system_path): $FILE_PATH" >> "${LOG_DIR}/security.log"
          log_event "$PROJECT_ROOT" "WARN" "path_blocked" \
            "Blocked system path access" "\"path\":\"$(mask_sensitive_data "$FILE_PATH")\""
          error_system_path_access "$FILE_PATH" "$sys_path"
          exit 0
        fi
      done

      # 민감 파일 경고
      if is_sensitive_file "$FILE_PATH"; then
        echo "[$TIMESTAMP] SENSITIVE_FILE: $FILE_PATH" >> "${LOG_DIR}/security.log"
        # 차단하지 않고 경고만 기록
      fi
    fi

    # 편집 전 백업
    if [ -n "$FILE_PATH" ] && [ -f "$FILE_PATH" ]; then
      BACKUP_NAME=$(echo "$FILE_PATH" | tr '/' '_')
      cp "$FILE_PATH" "${BACKUP_DIR}/${BACKUP_NAME}.$(date +%s).bak" 2>/dev/null || true
    fi

    # docs/specs/<slug>/... 편집은 현재 feature context를 갱신
    if [ -n "$FILE_PATH" ]; then
      FEATURE_PATH="$FILE_PATH"
      if [[ "$FEATURE_PATH" != /* ]]; then
        FEATURE_PATH="${PROJECT_ROOT}/${FEATURE_PATH}"
      fi

      INFERRED_FEATURE=$(infer_feature_from_path "$FEATURE_PATH" 2>/dev/null || true)
      if [ -n "$INFERRED_FEATURE" ]; then
        set_current_feature "$PROJECT_ROOT" "$INFERRED_FEATURE" >/dev/null 2>&1 || true
      fi
    fi

    # 파일 충돌 감지 (기능 레지스트리 기반)
    CURRENT_FEATURE=$(get_current_feature "$PROJECT_ROOT")
    if [ -n "$CURRENT_FEATURE" ] && [ -n "$FILE_PATH" ]; then
      if ! detect_file_conflicts "$PROJECT_ROOT" "$FILE_PATH" "$CURRENT_FEATURE"; then
        echo "[$TIMESTAMP] CONFLICT_WARNING: File $FILE_PATH may conflict with other in-progress features" >> "${LOG_DIR}/conflicts.log"
      fi
    fi
    ;;
esac
