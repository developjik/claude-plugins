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
    # 편집할 파일 목록 (환경 변수에서 가져오기)
    # Claude Code는 편집할 파일을 환경 변수로 전달합니다
    local files_to_edit="${EDITED_FILES:-}"
    
    if [ -z "$files_to_edit" ]; then
        return 0
    fi
    
    # 각 파일에 대해 백업 생성
    while IFS= read -r file; do
        if [ -n "$file" ]; then
            backup_file "$file"
        fi
    done <<< "$files_to_edit"
    
    log_message "Pre-edit backup completed"
    return 0
}

# 실행
main
