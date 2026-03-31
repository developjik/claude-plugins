#!/usr/bin/env bash
# feature-sync.sh — 기능 레지스트리 자동 동기화
# PDCA 단계 변경 시 feature registry 자동 업데이트
#
# DEPENDENCIES: feature-registry.sh, logging.sh

FEATURE_SYNC_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=feature-context.sh
source "${FEATURE_SYNC_LIB_DIR}/feature-context.sh"
# shellcheck source=feature-registry.sh
source "${FEATURE_SYNC_LIB_DIR}/feature-registry.sh"
# shellcheck source=phase-transition.sh
source "${FEATURE_SYNC_LIB_DIR}/phase-transition.sh"

# ============================================================================
# PDCA 단계 → 상태 매핑
# ============================================================================

# PDCA 단계를 feature registry 상태로 변환
# Usage: pdca_phase_to_status <phase>
pdca_phase_to_status() {
  local phase="${1:-}"

  case "$phase" in
    clarify|clarifying)
      echo "Clarifying"
      ;;
    plan|planning)
      echo "Planning"
      ;;
    design|designing)
      echo "Designing"
      ;;
    implement|implementing|do|doing)
      echo "Implementing"
      ;;
    check|checking)
      echo "Checking"
      ;;
    wrapup|wrapup|completed)
      echo "Completed"
      ;;
    *)
      echo "Planning"
      ;;
  esac
}

# ============================================================================
# 기능 레지스트리 동기화
# ============================================================================

# 기능 레지스트리 동기화
# Usage: sync_feature_registry <project_root> <feature_slug> <phase>
sync_feature_registry() {
  local project_root="${1:-}"
  local feature_slug="${2:-}"
  local phase="${3:-}"
  local features_file
  features_file=$(feature_registry_file "$project_root")

  if [ ! -f "$features_file" ]; then
    return 0
  fi

  if [ -z "$feature_slug" ] || [ -z "$phase" ]; then
    return 0
  fi

  local new_status
  new_status=$(pdca_phase_to_status "$phase")

  # 현재 상태 확인
  local current_status
  current_status=$(grep "^| \`${feature_slug}\`" "$features_file" | awk -F'|' '{print $4}' | xargs 2>/dev/null || echo "")

  if [ -z "$current_status" ]; then
    # 기능이 레지스트리에 없으면 등록
    printf '[INFO] Registering new feature: %s\n' "$feature_slug" >&2
    register_feature_from_sync "$project_root" "$feature_slug" "$new_status"
    return 0
  fi

  # 상태가 변경된 경우에만 업데이트
  if [ "$current_status" != "$new_status" ]; then
    update_feature_status_from_sync "$project_root" "$feature_slug" "$new_status" "$current_status"
  fi

  return 0
}

# 기능 상태 업데이트 (동기화용)
update_feature_status_from_sync() {
  local project_root="${1:-}"
  local feature_slug="${2:-}"
  local new_status="${3:-}"
  local old_status="${4:-}"
  local features_file
  features_file=$(feature_registry_file "$project_root")

  if [ ! -f "$features_file" ]; then
    return 1
  fi

  # 타임스탬프
  local timestamp
  timestamp=$(date '+%Y-%m-%d')

  # 백업 생성
  local backup_file="${features_file}.bak"
  cp "$features_file" "$backup_file"

  # 상태 업데이트 (4번째 열 = 상태, 7번째 열 = 마지막 업데이트)
  # 패턴: | `feature-slug` | title | OLD_STATUS | team | deps | impact | LAST_UPDATE |
  # 변경: | `feature-slug` | title | NEW_STATUS | team | deps | impact | TIMESTAMP |

  awk -v slug="$feature_slug" -v new_status="$new_status" -v timestamp="$timestamp" '
  BEGIN { FS="|"; OFS="|" }
  {
    # 공백 제거한 첫 번째 필드 확인
    trimmed = $2
    gsub(/^[ \t]+|[ \t]+$/, "", trimmed)

    if (trimmed == "`" slug "`") {
      # 상태(4번째 열)와 마지막 업데이트(7번째 열) 변경
      gsub(/^[ \t]+|[ \t]+$/, "", $4)
      $4 = " " new_status " "

      # 7번째 열이 있으면 업데이트
      if (NF >= 7) {
        gsub(/^[ \t]+|[ \t]+$/, "", $7)
        $7 = " " timestamp " "
      }
    }
    print
  }
  ' "$backup_file" > "$features_file"

  rm -f "$backup_file"

  printf '[INFO] Feature status updated: %s (%s → %s)\n' "$feature_slug" "$old_status" "$new_status" >&2

  # 변경 로그 기록
  local harness_dir="${project_root}/.harness"
  local sync_log="${harness_dir}/logs/feature-sync.log"
  mkdir -p "$(dirname "$sync_log")"
  printf '[%s] %s: %s → %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$feature_slug" "$old_status" "$new_status" >> "$sync_log"

  return 0
}

# 새 기능 등록 (동기화용)
register_feature_from_sync() {
  local project_root="${1:-}"
  local feature_slug="${2:-}"
  local status="${3:-Planning}"
  local features_file
  features_file=$(feature_registry_file "$project_root")

  if [ ! -f "$features_file" ]; then
    return 1
  fi

  # 이미 등록되어 있는지 확인
  if grep -q "^| \`${feature_slug}\`" "$features_file"; then
    return 0
  fi

  # 타이틀 생성 (slug를 사람이 읽기 쉬운 형태로)
  local title
  title=$(echo "$feature_slug" | tr '-' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2))}1')

  # 타임스탬프
  local timestamp
  timestamp=$(date '+%Y-%m-%d')

  # 새 행 추가 (테이블 끝에 추가)
  local new_row="| \`${feature_slug}\` | ${title} | ${status} | - | - | - | ${timestamp} |"

  # 마지막 데이터 행 찾기 (구분선 이후, 빈 행 전)
  local temp_file="${features_file}.tmp"
  local in_table=false
  local last_data_line=""

  while IFS= read -r line; do
    if [[ "$line" =~ ^\|[[:space:]]*\` ]]; then
      in_table=true
      last_data_line="$line"
    fi
    echo "$line" >> "$temp_file"
  done < "$features_file"

  # 새 행을 마지막 데이터 행 다음에 추가
  if [ -n "$last_data_line" ]; then
    # 임시 파일에서 마지막 데이터 행 위치 찾아서 삽입
    awk -v new_row="$new_row" -v last_data="$last_data_line" '
    {
      print
      if ($0 == last_data) {
        print new_row
      }
    }
    ' "$features_file" > "${features_file}.new"
    mv "${features_file}.new" "$features_file"
    rm -f "$temp_file"
  else
    # 테이블이 없으면 파일 끝에 추가
    echo "$new_row" >> "$features_file"
    rm -f "$temp_file"
  fi

  printf '[INFO] New feature registered: %s (%s)\n' "$feature_slug" "$status" >&2

  return 0
}

# ============================================================================
# 배치 동기화
# ============================================================================

# 모든 활성 기능 동기화
# Usage: sync_all_active_features <project_root>
sync_all_active_features() {
  local project_root="${1:-}"
  local features_file
  features_file=$(feature_registry_file "$project_root")

  if [ ! -f "$features_file" ]; then
    return 0
  fi

  # 현재 진행 중인 기능들 조회
  local current_feature
  current_feature=$(get_current_feature "$project_root")

  if [ -n "$current_feature" ]; then
    local current_phase
    current_phase=$(get_runtime_phase "$project_root")
    sync_feature_registry "$project_root" "$current_feature" "$current_phase"
  fi

  return 0
}

# ============================================================================
# 충돌 감지
# ============================================================================

# 파일 수정 시 충돌 감지
# Usage: detect_feature_conflicts <project_root> <modified_file> <current_feature>
detect_feature_conflicts() {
  local project_root="${1:-}"
  local modified_file="${2:-}"
  local current_feature="${3:-}"
  local features_file
  features_file=$(feature_registry_file "$project_root")

  if [ ! -f "$features_file" ] || [ -z "$current_feature" ]; then
    return 0
  fi

  # 다른 활성 기능들이 같은 파일을 수정하는지 확인
  local conflicting_features=""

  while IFS='|' read -r slug title status team deps impact _; do
    # 공백 제거
    slug=$(echo "$slug" | xargs 2>/dev/null || echo "")
    status=$(echo "$status" | xargs 2>/dev/null || echo "")
    impact=$(echo "$impact" | xargs 2>/dev/null || echo "")

    # 헤더/구분선 스킵
    [[ "$slug" =~ ^\` ]] || continue
    [[ "$slug" =~ "$current_feature" ]] && continue

    # 활성 상태 확인 (Implementing, Checking)
    if [[ "$status" == *"Implementing"* ]] || [[ "$status" == *"Checking"* ]]; then
      if [[ "$impact" == *"$modified_file"* ]]; then
        conflicting_features="${conflicting_features}${slug}, "
      fi
    fi
  done < "$features_file"

  if [ -n "$conflicting_features" ]; then
    printf '[WARNING] File conflict detected: %s is also being modified by: %s\n' \
      "$modified_file" "${conflicting_features%, }" >&2
    return 1
  fi

  return 0
}

# ============================================================================
# 통합 함수
# ============================================================================

# on-agent-stop에서 호출할 통합 동기화 함수
# Usage: sync_on_phase_complete <project_root> <feature_slug> <completed_phase>
sync_on_phase_complete() {
  local project_root="${1:-}"
  local feature_slug="${2:-}"
  local completed_phase="${3:-}"

  # 기능 레지스트리 동기화
  sync_feature_registry "$project_root" "$feature_slug" "$completed_phase"

  # 로그 기록
  local harness_dir="${project_root}/.harness"
  local sync_log="${harness_dir}/logs/feature-sync.log"
  mkdir -p "$(dirname "$sync_log")"

  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  local status
  status=$(pdca_phase_to_status "$completed_phase")

  printf '[%s] Phase complete: %s → %s (%s)\n' "$timestamp" "$feature_slug" "$completed_phase" "$status" >> "$sync_log"

  return 0
}
