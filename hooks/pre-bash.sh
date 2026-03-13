#!/bin/bash

# Pre-Bash Hook: 위험한 명령어 차단
# 이 스크립트는 Bash 명령어 실행 전에 위험한 작업을 감지하고 차단합니다.

set -e

# 로그 파일 설정
LOG_DIR="${HOME}/.harness-engineering/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/pre-bash-$(date +%Y%m%d_%H%M%S).log"

extract_command_from_payload() {
    local payload="$1"

    if [ -z "$payload" ] || ! command -v jq &> /dev/null; then
        return 1
    fi

    printf '%s' "$payload" | jq -r '.tool_input.command // .tool_input.cmd // .tool_input.commandLine // empty' 2>/dev/null
}

# 명령어 로깅
log_command() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# 위험한 패턴 검사
check_dangerous_patterns() {
    local command="$1"
    
    # 위험한 패턴 목록
    local dangerous_patterns=(
        "rm -rf /"
        "rm -rf ~"
        "dd if=/dev/zero"
        ":(){ :|:& };:"  # Fork bomb
        "mkfs"
        "shred"
    )
    
    for pattern in "${dangerous_patterns[@]}"; do
        if [[ "$command" == *"$pattern"* ]]; then
            log_command "BLOCKED: $command"
            echo "⚠️  위험한 명령어가 감지되었습니다: $pattern"
            echo "이 명령어는 보안상 이유로 실행할 수 없습니다."
            return 1
        fi
    done
    
    return 0
}

# 권한 검사
check_permissions() {
    local command="$1"
    
    # sudo 사용 검사
    if [[ "$command" == *"sudo"* ]]; then
        log_command "WARNING: sudo detected in command: $command"
        echo "⚠️  sudo 명령어가 포함되어 있습니다."
        echo "필요한 경우 관리자에게 문의하세요."
        return 1
    fi
    
    return 0
}

# 메인 로직
main() {
    local payload command
    payload="$(cat)"
    command=""

    # stdin JSON 페이로드를 기본 계약으로 사용하고, 이전 환경 변수 방식도 지원합니다.
    command="$(extract_command_from_payload "$payload" || true)"

    if [ -z "$command" ]; then
        command="${BASH_COMMAND:-}"
    fi
    
    if [ -z "$command" ]; then
        log_command "No bash command found in payload or environment"
        return 0
    fi
    
    log_command "EXECUTING: $command"
    
    # 위험한 패턴 검사
    if ! check_dangerous_patterns "$command"; then
        return 1
    fi
    
    # 권한 검사
    if ! check_permissions "$command"; then
        return 1
    fi
    
    # 모든 검사 통과
    return 0
}

# 실행
main
