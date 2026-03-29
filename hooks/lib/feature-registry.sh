#!/usr/bin/env bash
# feature-registry.sh — 기능 레지스트리 및 의존성 관리 함수
# common.sh에서 분리된 모듈
#
# DEPENDENCIES: json-utils.sh, logging.sh

# 기능 레지스트리 파일 경로 조회
# docs/features.md 우선, 없으면 docs/analysis/features.md 사용
feature_registry_file() {
  local project_root="${1:-}"

  if [[ -f "${project_root}/docs/features.md" ]]; then
    printf '%s/docs/features.md\n' "$project_root"
    return 0
  fi

  if [[ -f "${project_root}/docs/analysis/features.md" ]]; then
    printf '%s/docs/analysis/features.md\n' "$project_root"
    return 0
  fi

  printf '%s/docs/features.md\n' "$project_root"
}

# ============================================================================
# 기능 레지스트리 관련 함수
# ============================================================================

# 기능 레지스트리 파일 존재 확인
# Usage: check_feature_registry <project_root>
check_feature_registry() {
  local project_root="${1:-}"
  local features_file
  features_file=$(feature_registry_file "$project_root")

  if [ ! -f "$features_file" ]; then
    printf '[WARNING] Feature registry not found: %s\n' "$features_file" >&2
    return 1
  fi
  return 0
}

# 기능 상태 조회
# Usage: get_feature_status <project_root> <feature_slug>
# Returns: 상태 문자열
get_feature_status() {
  local project_root="${1:-}"
  local feature_slug="${2:-}"
  local features_file
  features_file=$(feature_registry_file "$project_root")

  if [ ! -f "$features_file" ]; then
    printf ''
    return 1
  fi

  # 간단한 grep 기반 상태 조회
  grep "^| \`${feature_slug}\`" "$features_file" | awk -F'|' '{print $4}' | xargs
}

# 의존성 충돌 확인
# Usage: check_dependency_conflicts <project_root> <current_feature>
check_dependency_conflicts() {
  local project_root="${1:-}"
  local current_feature="${2:-}"
  local features_file
  features_file=$(feature_registry_file "$project_root")

  if [ ! -f "$features_file" ]; then
    return 0
  fi

  # 현재 기능이 의존하는 다른 기능들의 상태 확인
  local dependencies=$(grep "^| \`${current_feature}\`" "$features_file" | awk -F'|' '{print $6}' | xargs)

  if [ -z "$dependencies" ] || [ "$dependencies" = "-" ]; then
    return 0
  fi

  printf '[INFO] Dependencies for %s: %s\n' "$current_feature" "$dependencies" >&2
  return 0
}

# 파일 충돌 감지
# Usage: detect_file_conflicts <project_root> <modified_file> <current_feature>
detect_file_conflicts() {
  local project_root="${1:-}"
  local modified_file="${2:-}"
  local current_feature="${3:-}"
  local features_file
  features_file=$(feature_registry_file "$project_root")

  if [ ! -f "$features_file" ]; then
    return 0
  fi

  local conflicting_features=""

  # 파일 경로가 다른 기능의 영향 범위에 포함되는지 확인
  while IFS='|' read -r slug title status team deps impact _; do
    # 헤더 행 및 구분선 스킵
    if [[ "$slug" =~ ^[[:space:]]*\| ]] || [[ "$slug" =~ ^[[:space:]]*\`feature ]]; then
      continue
    fi

    # 현재 기능 제외
    if [[ "$slug" =~ "$current_feature" ]]; then
      continue
    fi

    # In Progress 상태 확인
    if [[ "$status" =~ "Implementing" ]] || [[ "$status" =~ "Checking" ]]; then
      if [[ "$impact" =~ "$modified_file" ]]; then
        conflicting_features="${conflicting_features}${slug},"
      fi
    fi
  done < "$features_file"

  if [ -n "$conflicting_features" ]; then
    printf '[WARNING] Potential file conflicts detected with: %s\n' "${conflicting_features%,}" >&2
    return 1
  fi

  return 0
}

# ============================================================================
# 기능 레지스트리 업데이트 (자동화)
# ============================================================================

# 기능 상태 업데이트
# Usage: update_feature_status <project_root> <feature_slug> <new_status>
update_feature_status() {
  local project_root="${1:-}"
  local feature_slug="${2:-}"
  local new_status="${3:-}"
  local features_file
  features_file=$(feature_registry_file "$project_root")

  if [ ! -f "$features_file" ]; then
    printf '[WARNING] Feature registry not found, cannot update status\n' >&2
    return 1
  fi

  # 상태 업데이트 (sed 사용)
  # macOS와 Linux 호환을 위해 백업 파일 사용 후 삭제
  local backup_file="${features_file}.bak"
  cp "$features_file" "$backup_file"

  # 상태 열이 4번째라고 가정 (| slug | title | status | ...)
  sed "s/^| \`${feature_slug}\` | \(.*\) | \(.*\) | \(.*\) |/| \`${feature_slug}\` | \1 | ${new_status} |/" "$backup_file" > "$features_file"

  rm -f "$backup_file"

  printf '[INFO] Updated feature %s status to: %s\n' "$feature_slug" "$new_status" >&2
  return 0
}

# 새 기능 등록
# Usage: register_feature <project_root> <feature_slug> <title> <dependencies>
register_feature() {
  local project_root="${1:-}"
  local feature_slug="${2:-}"
  local title="${3:-}"
  local dependencies="${4:--}"
  local features_file
  features_file=$(feature_registry_file "$project_root")

  if [ ! -f "$features_file" ]; then
    printf '[WARNING] Feature registry not found, cannot register feature\n' >&2
    return 1
  fi

  # 이미 등록된 기능인지 확인
  if grep -q "^| \`${feature_slug}\`" "$features_file"; then
    printf '[INFO] Feature %s already registered\n' "$feature_slug" >&2
    return 0
  fi

  # 새 행 추가 (테이블 구조에 맞게)
  local new_row="| \`${feature_slug}\` | ${title} | Planning | - | ${dependencies} | - |"

  # 마지막 데이터 행 다음에 추가
  # 간단한 구현: 파일 끝에 추가
  echo "$new_row" >> "$features_file"

  printf '[INFO] Registered new feature: %s\n' "$feature_slug" >&2
  return 0
}
