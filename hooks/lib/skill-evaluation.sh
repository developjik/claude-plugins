#!/usr/bin/env bash
# skill-evaluation.sh — 스킬 평가 프레임워크
# P1-2: 스킬 실행 품질 메트릭 수집 및 분석
#
# DEPENDENCIES: json-utils.sh, logging.sh
#
# 수집 메트릭:
# - success_rate: 성공률
# - execution_time: 실행 시간
# - error_count: 에러 횟수
# - retry_count: 재시도 횟수
# - user_satisfaction: 사용자 만족도

set -euo pipefail

# ============================================================================
# 상수
# ============================================================================

readonly METRICS_DIR=".harness/metrics"
readonly DASHBOARD_FILE=".harness/metrics/dashboard.md"
readonly MAX_METRICS_AGE_DAYS=30
readonly MIN_SAMPLE_SIZE=5

# ============================================================================
# 스킬 실행 기록
# ============================================================================

# 스킬 실행 기록
# Usage: record_skill_execution <project_root> <skill_name> <status> [duration_ms] [error_msg] [metadata_json]
# status: success|failure|partial|timeout
record_skill_execution() {
  local project_root="${1:-}"
  local skill_name="${2:-}"
  local status="${3:-success}"
  local duration_ms="${4:-0}"
  local error_msg="${5:-}"
  local metadata="${6:-}"

  # 메트릭 디렉토리 생성
  local metrics_dir="${project_root}/${METRICS_DIR}"
  mkdir -p "$metrics_dir"

  # 스킬별 메트릭 파일
  local metric_file="${metrics_dir}/${skill_name}.jsonl"

  # 타임스탬프
  local timestamp
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  # 실행 ID 생성
  local execution_id
  execution_id="${skill_name}_$(date +%s)_$$_$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom 2>/dev/null | head -c 4 || echo "rand")"

  # 메타데이터 검증 (유효한 JSON인지 확인)
  local valid_metadata="{}"
  if [[ -n "$metadata" ]]; then
    if echo "$metadata" | jq -e . > /dev/null 2>&1; then
      valid_metadata="$metadata"
    fi
  fi

  # JSON 레코드 생성
  local record
  record=$(jq -c -n \
    --arg id "$execution_id" \
    --arg skill "$skill_name" \
    --arg status "$status" \
    --argjson duration "$duration_ms" \
    --arg error "$error_msg" \
    --arg ts "$timestamp" \
    --argjson metadata "$valid_metadata" \
    '{
      id: $id,
      skill: $skill,
      status: $status,
      duration_ms: $duration,
      error: $error,
      timestamp: $ts,
      metadata: $metadata
    }')

  # 파일에 추가
  echo "$record" >> "$metric_file"

  # 로그 기록
  if declare -f log_event &>/dev/null; then
    log_event "$project_root" "INFO" "skill_execution" "Skill executed" \
      "{\"skill\":\"$skill_name\",\"status\":\"$status\",\"duration_ms\":$duration_ms}"
  fi

  echo "$record"
}

# 배치 실행 기록
# Usage: record_batch_execution <project_root> <skill_name> <results_json>
record_batch_execution() {
  local project_root="${1:-}"
  local skill_name="${2:-}"
  local results_json="${3:-}"

  local total passed failed duration
  total=$(echo "$results_json" | jq -r '.total // 1')
  passed=$(echo "$results_json" | jq -r '.passed // 0')
  failed=$(echo "$results_json" | jq -r '.failed // 0')
  duration=$(echo "$results_json" | jq -r '.duration_ms // 0')

  local status="success"
  if [[ "$failed" -gt 0 ]] && [[ "$passed" -eq 0 ]]; then
    status="failure"
  elif [[ "$failed" -gt 0 ]]; then
    status="partial"
  fi

  local metadata
  metadata=$(jq -c -n \
    --argjson total "$total" \
    --argjson passed "$passed" \
    --argjson failed "$failed" \
    '{"total": $total, "passed": $passed, "failed": $failed}')

  record_skill_execution "$project_root" "$skill_name" "$status" "$duration" "" "$metadata"
}

# ============================================================================
# 스킬 통계 조회
# ============================================================================

# 스킬별 통계 조회
# Usage: get_skill_statistics <project_root> <skill_name> [days]
# Output: JSON with statistics
get_skill_statistics() {
  local project_root="${1:-}"
  local skill_name="${2:-}"
  local days="${3:-30}"

  local metric_file="${project_root}/${METRICS_DIR}/${skill_name}.jsonl"

  if [[ ! -f "$metric_file" ]]; then
    echo '{"skill": "'"$skill_name"'", "total_executions": 0, "success_rate": 0, "avg_duration_ms": 0}'
    return 0
  fi

  # 날짜 필터링
  local cutoff_date
  cutoff_date=$(date -v-${days}d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
    date -d "-${days} days" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
    echo "2000-01-01T00:00:00Z")

  # 통계 계산
  local total success_count failure_count partial_count timeout_count
  local total_duration avg_duration
  local error_messages

  total=$(grep -c . "$metric_file" 2>/dev/null || echo 0)

  # 필터링된 레코드 수집
  local filtered_records
  filtered_records=$(while IFS= read -r line; do
    local ts
    ts=$(echo "$line" | jq -r '.timestamp // "2000-01-01T00:00:00Z"')
    if [[ "$ts" > "$cutoff_date" ]]; then
      echo "$line"
    fi
  done < "$metric_file")

  local filtered_total
  filtered_total=$(echo "$filtered_records" | grep -c . 2>/dev/null || echo 0)

  if [[ "$filtered_total" -eq 0 ]]; then
    echo '{"skill": "'"$skill_name"'", "total_executions": 0, "success_rate": 0, "avg_duration_ms": 0, "period_days": '"$days"'}'
    return 0
  fi

  success_count=$(echo "$filtered_records" | jq -s '[.[] | select(.status == "success")] | length' 2>/dev/null || echo 0)
  failure_count=$(echo "$filtered_records" | jq -s '[.[] | select(.status == "failure")] | length' 2>/dev/null || echo 0)
  partial_count=$(echo "$filtered_records" | jq -s '[.[] | select(.status == "partial")] | length' 2>/dev/null || echo 0)
  timeout_count=$(echo "$filtered_records" | jq -s '[.[] | select(.status == "timeout")] | length' 2>/dev/null || echo 0)

  total_duration=$(echo "$filtered_records" | jq -s '[.[]?.duration_ms // 0] | add // 0' 2>/dev/null || echo 0)
  avg_duration=0
  if [[ "$filtered_total" -gt 0 ]]; then
    avg_duration=$(awk "BEGIN {printf \"%.0f\", $total_duration / $filtered_total}")
  fi

  local success_rate
  success_rate=$(awk "BEGIN {printf \"%.2f\", $success_count / $filtered_total}")

  # 에러 메시지 수집 (상위 5개)
  error_messages=$(echo "$filtered_records" | jq -s -r \
    '[.[] | select(.error != "" and .error != null) | .error] | group_by(.) | map({message: .[0], count: length}) | sort_by(-.count) | .[0:5]' \
    2>/dev/null || echo '[]')

  # 결과 조립
  jq -n \
    --arg skill "$skill_name" \
    --argjson total "$filtered_total" \
    --argjson success "$success_count" \
    --argjson failure "$failure_count" \
    --argjson partial "$partial_count" \
    --argjson timeout "$timeout_count" \
    --arg success_rate "$success_rate" \
    --argjson avg_duration "$avg_duration" \
    --argjson days "$days" \
    --argjson errors "$error_messages" \
    '{
      skill: $skill,
      total_executions: $total,
      success_count: $success,
      failure_count: $failure,
      partial_count: $partial,
      timeout_count: $timeout,
      success_rate: ($success_rate | tonumber),
      avg_duration_ms: $avg_duration,
      period_days: $days,
      top_errors: $errors
    }'
}

# 모든 스킬 통계 조회
# Usage: get_all_skill_statistics <project_root> [days]
get_all_skill_statistics() {
  local project_root="${1:-}"
  local days="${2:-30}"

  local metrics_dir="${project_root}/${METRICS_DIR}"

  if [[ ! -d "$metrics_dir" ]]; then
    echo '{"skills": [], "summary": {"total_executions": 0, "overall_success_rate": 0}}'
    return 0
  fi

  local all_stats='[]'
  local skill_files=()

  # 모든 스킬 파일 찾기
  while IFS= read -r file; do
    skill_files+=("$file")
  done < <(find "$metrics_dir" -name "*.jsonl" -type f 2>/dev/null)

  for file in "${skill_files[@]}"; do
    local skill_name
    skill_name=$(basename "$file" .jsonl)
    local stat
    stat=$(get_skill_statistics "$project_root" "$skill_name" "$days")
    all_stats=$(echo "$all_stats" | jq '. + ['"$stat"']')
  done

  # 요약 통계
  local total_exec overall_success
  total_exec=$(echo "$all_stats" | jq '[.[].total_executions] | add // 0')
  overall_success=$(echo "$all_stats" | jq -r '.[] | select(.total_executions > 0) | .success_rate * .total_executions' 2>/dev/null | \
    awk '{sum+=$1} END {print sum}')

  local overall_rate=0
  if [[ "$total_exec" -gt 0 ]]; then
    overall_rate=$(awk "BEGIN {printf \"%.2f\", $overall_success / $total_exec}")
  fi

  jq -n \
    --argjson skills "$all_stats" \
    --argjson total_exec "$total_exec" \
    --arg overall_rate "$overall_rate" \
    --argjson days "$days" \
    '{
      skills: $skills,
      summary: {
        total_skills: ($skills | length),
        total_executions: $total_exec,
        overall_success_rate: ($overall_rate | tonumber),
        period_days: $days
      }
    }'
}

# ============================================================================
# 대시보드 생성
# ============================================================================

# Markdown 대시보드 생성
# Usage: generate_skill_dashboard <project_root> [days]
generate_skill_dashboard() {
  local project_root="${1:-}"
  local days="${2:-30}"

  local metrics_dir="${project_root}/${METRICS_DIR}"
  mkdir -p "$metrics_dir"

  local stats
  stats=$(get_all_skill_statistics "$project_root" "$days")

  local dashboard_file="${project_root}/${DASHBOARD_FILE}"

  # 대시보드 헤더
  cat > "$dashboard_file" << 'EOF'
# Skill Evaluation Dashboard

EOF

  echo "Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')" >> "$dashboard_file"
  echo "Period: Last ${days} days" >> "$dashboard_file"
  echo "" >> "$dashboard_file"

  # 요약 섹션
  echo "## Summary" >> "$dashboard_file"
  echo "" >> "$dashboard_file"

  local total_skills total_exec overall_rate
  total_skills=$(echo "$stats" | jq -r '.summary.total_skills')
  total_exec=$(echo "$stats" | jq -r '.summary.total_executions')
  overall_rate=$(echo "$stats" | jq -r '.summary.overall_success_rate')

  echo "| Metric | Value |" >> "$dashboard_file"
  echo "|--------|-------|" >> "$dashboard_file"
  echo "| Total Skills | $total_skills |" >> "$dashboard_file"
  echo "| Total Executions | $total_exec |" >> "$dashboard_file"
  echo "| Overall Success Rate | $(awk "BEGIN {printf \"%.1f%%\", $overall_rate * 100}") |" >> "$dashboard_file"
  echo "" >> "$dashboard_file"

  # 스킬별 상세
  echo "## Skill Statistics" >> "$dashboard_file"
  echo "" >> "$dashboard_file"

  echo "| Skill | Executions | Success Rate | Avg Duration | Status |" >> "$dashboard_file"
  echo "|-------|------------|--------------|--------------|--------|" >> "$dashboard_file"

  echo "$stats" | jq -r '.skills[] | select(.total_executions > 0) | [.skill, .total_executions, .success_rate, .avg_duration_ms] | @tsv' | \
    while IFS=$'\t' read -r skill exec rate dur; do
      local status_emoji pct
      pct=$(awk "BEGIN {printf \"%.1f\", $rate * 100}")
      dur_ms=$(awk "BEGIN {printf \"%.0f ms\", $dur}")

      if awk "BEGIN {exit !($rate >= 0.9)}"; then
        status_emoji="✅"
      elif awk "BEGIN {exit !($rate >= 0.7)}"; then
        status_emoji="⚠️"
      else
        status_emoji="❌"
      fi

      echo "| $skill | $exec | ${pct}% | ${dur_ms} | $status_emoji |" >> "$dashboard_file"
    done

  echo "" >> "$dashboard_file"

  # 미사용 스킬
  local unused
  unused=$(echo "$stats" | jq -r '.skills[] | select(.total_executions == 0) | .skill')
  if [[ -n "$unused" ]]; then
    echo "## Unused Skills" >> "$dashboard_file"
    echo "" >> "$dashboard_file"
    echo "$unused" | while read -r skill; do
      echo "- $skill" >> "$dashboard_file"
    done
    echo "" >> "$dashboard_file"
  fi

  # Top 에러
  echo "## Top Errors" >> "$dashboard_file"
  echo "" >> "$dashboard_file"

  echo "$stats" | jq -r '.skills[] | select(.top_errors | length > 0) | .top_errors[]? | "- \(.message) (\(.count) occurrences)"' 2>/dev/null | \
    head -10 >> "$dashboard_file"

  echo "" >> "$dashboard_file"
  echo "---" >> "$dashboard_file"
  echo "*Auto-generated by skill-evaluation.sh*" >> "$dashboard_file"

  echo "$dashboard_file"
}

# ============================================================================
# 메트릭 집계 및 분석
# ============================================================================

# 스킬 점수 계산
# Usage: calculate_skill_score <stats_json>
# Output: 0.0-1.0 score
calculate_skill_score() {
  local stats_json="${1:-}"

  local total success_rate avg_duration
  total=$(echo "$stats_json" | jq -r '.total_executions // 0')
  success_rate=$(echo "$stats_json" | jq -r '.success_rate // 0')
  avg_duration=$(echo "$stats_json" | jq -r '.avg_duration_ms // 0')

  # 샘플 크기가 충분하지 않으면 중립 점수
  if [[ "$total" -lt "$MIN_SAMPLE_SIZE" ]]; then
    echo "0.5"
    return 0
  fi

  # 점수 계산:
  # - 성공률: 70%
  # - 실행 시간 (빠를수록 좋음): 30%

  local time_score=0.5
  if [[ "$avg_duration" -gt 0 ]]; then
    # 1초 이하: 1.0, 10초 이상: 0.0, 그 사이는 선형
    if [[ "$avg_duration" -le 1000 ]]; then
      time_score=1.0
    elif [[ "$avg_duration" -ge 10000 ]]; then
      time_score=0.0
    else
      time_score=$(awk "BEGIN {printf \"%.2f\", 1 - ($avg_duration - 1000) / 9000}")
    fi
  fi

  local final_score
  final_score=$(awk "BEGIN {printf \"%.2f\", ($success_rate * 0.7) + ($time_score * 0.3)}")

  echo "$final_score"
}

# 스킬 랭킹 계산
# Usage: rank_skills <project_root> [days]
rank_skills() {
  local project_root="${1:-}"
  local days="${2:-30}"

  local stats
  stats=$(get_all_skill_statistics "$project_root" "$days")

  local ranked='[]'

  echo "$stats" | jq -r '.skills[] | @json' | while read -r skill_json; do
    local skill score
    skill=$(echo "$skill_json" | jq -r '.skill')
    score=$(calculate_skill_score "$skill_json")

    ranked=$(echo "$ranked" | jq '. + [{"skill": "'"$skill"'", "score": '"$score"'}]')
  done

  # 점수순 정렬
  echo "$ranked" | jq 'sort_by(-.score)'
}

# 이상 탐지 (성능 저하, 에러 급증)
# Usage: detect_anomalies <project_root> [threshold]
detect_anomalies() {
  local project_root="${1:-}"
  local threshold="${2:-0.3}"

  local stats
  stats=$(get_all_skill_statistics "$project_root" "7")

  # jq로 직접 이상 탐지
  echo "$stats" | jq --argjson threshold "$threshold" '
    [.skills[] | select(.total_executions >= 5 and .success_rate < $threshold) | {
      skill: .skill,
      type: "low_success_rate",
      value: .success_rate,
      message: "Success rate below threshold"
    }]
  '
}

# ============================================================================
# 메트릭 관리
# ============================================================================

# 오래된 메트릭 정리
# Usage: cleanup_old_metrics <project_root> [max_age_days]
cleanup_old_metrics() {
  local project_root="${1:-}"
  local max_age_days="${2:-$MAX_METRICS_AGE_DAYS}"

  local metrics_dir="${project_root}/${METRICS_DIR}"

  if [[ ! -d "$metrics_dir" ]]; then
    echo "0"
    return 0
  fi

  local cleaned=0
  local cutoff_date
  cutoff_date=$(date -v-${max_age_days}d +%s 2>/dev/null || \
    date -d "-${max_age_days} days" +%s 2>/dev/null)

  for file in "$metrics_dir"/*.jsonl; do
    if [[ -f "$file" ]]; then
      # 각 라인 검사
      local tmp_file="${file}.tmp"
      local kept=0

      while IFS= read -r line; do
        local ts
        ts=$(echo "$line" | jq -r '.timestamp // "2000-01-01T00:00:00Z"')

        local ts_epoch
        # Fixed: Add TZ=UTC for consistent timezone handling
        ts_epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s 2>/dev/null || echo 0)

        if [[ "$ts_epoch" -ge "$cutoff_date" ]]; then
          echo "$line" >> "$tmp_file"
          kept=$((kept + 1))
        else
          cleaned=$((cleaned + 1))
        fi
      done < "$file"

      if [[ "$kept" -gt 0 ]]; then
        mv "$tmp_file" "$file"
      else
        rm -f "$file" "$tmp_file"
      fi
    fi
  done

  echo "$cleaned"
}

# 메트릭 내보내기
# Usage: export_metrics <project_root> <format>
# format: json|csv
export_metrics() {
  local project_root="${1:-}"
  local format="${2:-json}"

  local stats
  stats=$(get_all_skill_statistics "$project_root" "30")

  case "$format" in
    csv)
      echo "skill,total_executions,success_rate,failure_count,avg_duration_ms"
      echo "$stats" | jq -r '.skills[] | [.skill, .total_executions, .success_rate, .failure_count, .avg_duration_ms] | @csv'
      ;;
    json|*)
      echo "$stats"
      ;;
  esac
}

# ============================================================================
# 리포트 생성
# ============================================================================

# 주간 리포트 생성
# Usage: generate_weekly_report <project_root>
generate_weekly_report() {
  local project_root="${1:-}"

  local report_file="${project_root}/${METRICS_DIR}/weekly_report_$(date +%Y%m%d).md"

  local stats_7d stats_30d
  stats_7d=$(get_all_skill_statistics "$project_root" "7")
  stats_30d=$(get_all_skill_statistics "$project_root" "30")

  cat > "$report_file" << EOF
# Weekly Skill Evaluation Report

**Generated:** $(date -u '+%Y-%m-%d %H:%M:%S UTC')

## Summary (Last 7 Days)

| Metric | Value |
|--------|-------|
| Total Executions | $(echo "$stats_7d" | jq -r '.summary.total_executions') |
| Success Rate | $(echo "$stats_7d" | jq -r '.summary.overall_success_rate | . * 100 | floor')% |

## Top Performers

$(echo "$stats_7d" | jq -r '.skills | sort_by(-.success_rate) | .[0:3] | .[] | "- \(.skill): \(.success_rate * 100 | floor)% success rate"')

## Needs Attention

$(echo "$stats_7d" | jq -r '.skills | sort_by(.success_rate) | .[0:3] | .[] | "- \(.skill): \(.success_rate * 100 | floor)% success rate"')

## Recommendations

$(generate_recommendations "$stats_7d")

---
*Auto-generated by skill-evaluation.sh*
EOF

  echo "$report_file"
}

# 권장사항 생성
generate_recommendations() {
  local stats="${1:-}"

  local recs=""

  # 낮은 성공률 스킬
  local low_success
  low_success=$(echo "$stats" | jq -r '.skills[] | select(.success_rate < 0.7 and .total_executions >= 5) | .skill')

  if [[ -n "$low_success" ]]; then
    recs+="1. **Review failing skills:**\n"
    echo "$low_success" | while read -r skill; do
      recs+="   - $skill\n"
    done
  fi

  # 미사용 스킬
  local unused
  unused=$(echo "$stats" | jq -r '.skills[] | select(.total_executions == 0) | .skill')

  if [[ -n "$unused" ]]; then
    recs+="2. **Consider removing unused skills:**\n"
    echo "$unused" | head -3 | while read -r skill; do
      recs+="   - $skill\n"
    done
  fi

  if [[ -z "$recs" ]]; then
    recs="- All skills performing well ✅"
  fi

  echo -e "$recs"
}
