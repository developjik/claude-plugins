#!/bin/bash

# Pre-Edit Hook: 파일 편집 전 백업 생성
# 이 스크립트는 파일 편집 전에 자동으로 백업을 생성합니다.

set -e

# 백업 디렉토리 설정
BACKUP_DIR="${HOME}/.harness-engineering/backups"
mkdir -p "$BACKUP_DIR"

# 로그 파일 설정
LOG_DIR="${HOME}/.harness-engineering/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/pre-edit-$(date +%Y%m%d_%H%M%S).log"

# 로깅 함수
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

extract_files_from_payload() {
    local payload="$1"

    if [ -z "$payload" ] || ! command -v jq &> /dev/null; then
        return 1
    fi

    printf '%s' "$payload" | jq -r '
        [
            .tool_input.path?,
            .tool_input.file_path?,
            .tool_input.filePath?,
            (.tool_input.paths[]?),
            (.tool_input.files[]?)
        ]
        | map(select(type == "string" and length > 0))
        | .[]
    ' 2>/dev/null
}

# 파일 백업 함수
backup_file() {
    local file="$1"
    
    if [ ! -f "$file" ]; then
        log_message "File not found: $file"
        return 0
    fi
    
    # 백업 파일명 생성 (타임스탬프 포함)
    local backup_name=$(basename "$file")
    local backup_path="$BACKUP_DIR/${backup_name}.$(date +%Y%m%d_%H%M%S).bak"
    
    # 파일 백업
    cp "$file" "$backup_path"
    log_message "Backup created: $backup_path"
    
    # 백업 메타데이터 저장
    local metadata_file="$BACKUP_DIR/.metadata"
    echo "$file -> $backup_path" >> "$metadata_file"
    
    return 0
}

# 메인 로직
main() {
    local payload files_to_edit
    payload="$(cat)"
    files_to_edit=""

    # stdin JSON 페이로드를 기본 계약으로 사용하고, 이전 환경 변수 방식도 지원합니다.
    files_to_edit="$(extract_files_from_payload "$payload" || true)"

    if [ -z "$files_to_edit" ]; then
        files_to_edit="${EDITED_FILES:-}"
    fi
    
    if [ -z "$files_to_edit" ]; then
        log_message "No editable files found in payload or environment"
        return 0
    fi
    
    # 각 파일에 대해 백업 생성
    printf '%s\n' "$files_to_edit" | awk 'NF && !seen[$0]++' | while IFS= read -r file; do
        if [ -n "$file" ]; then
            backup_file "$file"
        fi
    done
    
    log_message "Pre-edit backup completed"
    return 0
}

# 실행
main
