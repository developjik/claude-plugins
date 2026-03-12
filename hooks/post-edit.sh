#!/bin/bash

# Post-Edit Hook: 파일 편집 후 린트 검사 및 변경 사항 추적
# 이 스크립트는 파일 편집 후 자동으로 린트 검사를 수행하고 변경 사항을 추적합니다.

set -e

# 디렉토리 설정
STATE_DIR="${HOME}/.harness-engineering/state"
LOG_DIR="${HOME}/.harness-engineering/logs"
mkdir -p "$STATE_DIR" "$LOG_DIR"

LOG_FILE="$LOG_DIR/post-edit-$(date +%Y%m%d_%H%M%S).log"
CHANGES_FILE="$STATE_DIR/changes.txt"

# 로깅 함수
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# 파일 변경 추적
track_changes() {
    local file="$1"
    
    if [ ! -f "$file" ]; then
        return 0
    fi
    
    # 파일 해시 계산
    local file_hash=$(md5sum "$file" | awk '{print $1}')
    
    # 변경 사항 기록
    echo "$file|$file_hash|$(date +%Y-%m-%d\ %H:%M:%S)" >> "$CHANGES_FILE"
    log_message "File tracked: $file (hash: $file_hash)"
}

# 린트 검사 (JavaScript/TypeScript)
check_javascript_lint() {
    local file="$1"
    
    if [[ ! "$file" =~ \.(js|ts|jsx|tsx)$ ]]; then
        return 0
    fi
    
    log_message "Checking JavaScript/TypeScript: $file"
    
    # ESLint 설치 여부 확인
    if ! command -v eslint &> /dev/null; then
        log_message "ESLint not installed, skipping JavaScript lint"
        return 0
    fi
    
    # ESLint 실행
    if eslint "$file" >> "$LOG_FILE" 2>&1; then
        log_message "JavaScript lint passed: $file"
        return 0
    else
        log_message "JavaScript lint failed: $file"
        return 1
    fi
}

# 린트 검사 (Python)
check_python_lint() {
    local file="$1"
    
    if [[ ! "$file" =~ \.py$ ]]; then
        return 0
    fi
    
    log_message "Checking Python: $file"
    
    # Pylint 설치 여부 확인
    if ! command -v pylint &> /dev/null; then
        log_message "Pylint not installed, skipping Python lint"
        return 0
    fi
    
    # Pylint 실행
    if pylint "$file" >> "$LOG_FILE" 2>&1; then
        log_message "Python lint passed: $file"
        return 0
    else
        log_message "Python lint warnings/errors: $file"
        return 1
    fi
}

# 마크다운 검사
check_markdown() {
    local file="$1"
    
    if [[ ! "$file" =~ \.md$ ]]; then
        return 0
    fi
    
    log_message "Checking Markdown: $file"
    
    # Markdownlint 설치 여부 확인
    if ! command -v markdownlint &> /dev/null; then
        log_message "Markdownlint not installed, skipping Markdown check"
        return 0
    fi
    
    # Markdownlint 실행
    if markdownlint "$file" >> "$LOG_FILE" 2>&1; then
        log_message "Markdown check passed: $file"
        return 0
    else
        log_message "Markdown check warnings: $file"
        return 1
    fi
}

# 메인 로직
main() {
    # 입력 데이터 읽기 (JSON 형식)
    local input=$(cat)
    
    # 수정된 파일 정보 추출
    local tool_name=$(echo "$input" | jq -r '.tool_name' 2>/dev/null || echo "unknown")
    local file_path=$(echo "$input" | jq -r '.tool_input.path' 2>/dev/null || echo "")
    
    if [ -z "$file_path" ]; then
        return 0
    fi
    
    log_message "Post-edit hook started for: $file_path"
    
    # 파일 존재 확인
    if [ ! -f "$file_path" ]; then
        log_message "File not found: $file_path"
        return 0
    fi
    
    # 파일 크기 기록
    local file_size=$(wc -c < "$file_path")
    log_message "File size: $file_size bytes"
    
    # 변경 사항 추적
    track_changes "$file_path"
    
    # 린트 검사
    local lint_failed=0
    check_javascript_lint "$file_path" || lint_failed=1
    check_python_lint "$file_path" || lint_failed=1
    check_markdown "$file_path" || lint_failed=1
    
    log_message "Post-edit hook completed"
    
    # 린트 실패 시 경고
    if [ $lint_failed -eq 1 ]; then
        echo "⚠️  린트 검사에서 경고가 발생했습니다. 로그를 확인하세요: $LOG_FILE"
    fi
    
    return 0
}

# 실행
main
