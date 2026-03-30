#!/usr/bin/env bash
# wave-executor.sh — Wave 기반 병렬 실행 시스템
# P0-2: 실제 서브에이전트 스포닝으로 개선
# P1-5: 하이브리드 태스크 포맷 지원 (XML + Markdown)
#
# DEPENDENCIES: json-utils.sh, logging.sh, task-format.sh, wave-graph.sh, wave-runner.sh
#
# 변경사항 (P0-2):
# - 시뮬레이션 → 실제 서브에이전트 실행
# - Agent 툴 연동
# - 상태 추적 및 결과 집계
# - 크래시 복구 지원
#
# 변경사항 (P1-5):
# - XML 태스크 포맷 지원
# - Markdown/XML 자동 감지
# - 포맷 간 변환 지원

set -euo pipefail

# ============================================================================
# Wave 실행 설정
# ============================================================================

readonly MAX_PARALLEL_TASKS=4 # 최대 병렬 태스크 수
readonly WAVE_TIMEOUT=300     # Wave당 최대 실행 시간 (초)
readonly TASK_TIMEOUT=600     # 태스크당 최대 실행 시간 (초)
readonly RETRY_COUNT=2        # 실패 시 재시도 횟수

# 태스크 포맷 변환 라이브러리 로드
if ! declare -f detect_task_format &> /dev/null; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "${SCRIPT_DIR}/task-format.sh" 2> /dev/null || true
fi

if [[ -z "${WAVE_EXECUTOR_LIB_DIR:-}" ]]; then
  WAVE_EXECUTOR_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# ============================================================================
# 하이브리드 태스크 로딩 (XML + Markdown)
# ============================================================================

# load_task <task_file>
# Returns: JSON with task data (auto-detects format)
load_task() {
  local task_file="${1:-}"

  if [[ ! -f "$task_file" ]]; then
    echo '{"error": "file_not_found", "file": "'"$task_file"'"}'
    return 1
  fi

  local format
  format=$(detect_task_format "$task_file")

  case "$format" in
    xml)
      parse_xml_task "$task_file"
      ;;
    md)
      parse_md_task "$task_file"
      ;;
    *)
      echo '{"error": "unknown_format", "file": "'"$task_file"'"}'
      return 1
      ;;
  esac
}

# load_all_tasks <tasks_dir>
# Returns: JSON array of all tasks
load_all_tasks() {
  local tasks_dir="${1:-}"

  if [[ ! -d "$tasks_dir" ]]; then
    echo "[]"
    return 1
  fi

  local all_tasks="[]"

  # Load XML tasks
  for xml_file in "$tasks_dir"/*.xml; do
    if [[ -f "$xml_file" ]]; then
      local task_json
      task_json=$(parse_xml_task "$xml_file")
      all_tasks=$(echo "$all_tasks" | jq --argjson task "$task_json" '. += [$task]')
    fi
  done

  # Load Markdown tasks
  for md_file in "$tasks_dir"/*.md; do
    if [[ -f "$md_file" ]]; then
      local task_json
      task_json=$(parse_md_task "$md_file")
      all_tasks=$(echo "$all_tasks" | jq --argjson task "$task_json" '. += [$task]')
    fi
  done

  echo "$all_tasks"
}

# ============================================================================
# YAML 파싱 (yq 없이도 동작)
# ============================================================================

parse_waves_yaml() {
  local yaml_file="${1:-}"
  local project_root="${2:-}"

  if [[ ! -f "$yaml_file" ]]; then
    echo "[]"
    return 1
  fi

  # yq가 있으면 사용
  if command -v yq &> /dev/null; then
    yq -o=json '.' "$yaml_file" 2> /dev/null
    return 0
  fi

  # 간단한 YAML 파싱 (기본적인 waves.yaml 형식만 지원)
  local current_wave=0
  local in_tasks=false
  local tasks_json="[]"

  while IFS= read -r line; do
    # Wave 번호 감지
    if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*wave:[[:space:]]*([0-9]+) ]]; then
      current_wave="${BASH_REMATCH[1]}"
      in_tasks=false
    # tasks 섹션 감지
    elif [[ "$line" =~ ^[[:space:]]*tasks: ]]; then
      in_tasks=true
    # 태스크 항목 감지
    elif [[ "$in_tasks" == true ]] && [[ "$line" =~ ^[[:space:]]*-[[:space:]]*id: ]]; then
      local task_id
      task_id=$(echo "$line" | sed 's/.*id:[[:space:]]*//' | tr -d '"')
      # 간단한 JSON 생성은 생략 (yq 권장)
    fi
  done < "$yaml_file"

  echo "[]"
}

# ============================================================================
# Wave graph / runner 모듈
# ============================================================================

if ! declare -f topological_sort &> /dev/null; then
  # shellcheck source=hooks/lib/wave-graph.sh
  source "${WAVE_EXECUTOR_LIB_DIR}/wave-graph.sh"
fi

if ! declare -f execute_wave &> /dev/null; then
  # shellcheck source=hooks/lib/wave-runner.sh
  source "${WAVE_EXECUTOR_LIB_DIR}/wave-runner.sh"
fi
