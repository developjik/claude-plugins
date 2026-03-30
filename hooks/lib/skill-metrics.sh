#!/usr/bin/env bash
# skill-metrics.sh — skill-evaluation metrics storage and aggregation helpers

set -euo pipefail

skill_metrics_dir() {
  local project_root="${1:-}"
  local metrics_dir_name="${METRICS_DIR:-.harness/metrics}"
  echo "${project_root}/${metrics_dir_name}"
}

skill_dashboard_file_path() {
  local project_root="${1:-}"
  local dashboard_file_name="${DASHBOARD_FILE:-.harness/metrics/dashboard.md}"
  echo "${project_root}/${dashboard_file_name}"
}

skill_metric_file_path() {
  local project_root="${1:-}"
  local skill_name="${2:-}"
  echo "$(skill_metrics_dir "$project_root")/${skill_name}.jsonl"
}

skill_eval_cutoff_iso() {
  local days="${1:-30}"
  date -v-"${days}"d +%Y-%m-%dT%H:%M:%SZ 2> /dev/null \
    || date -d "-${days} days" +%Y-%m-%dT%H:%M:%SZ 2> /dev/null \
    || echo "2000-01-01T00:00:00Z"
}

skill_eval_iso_to_epoch() {
  local iso_ts="${1:-}"
  local normalized="${iso_ts%Z}"

  if [[ "$OSTYPE" == "darwin"* ]]; then
    TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$normalized" +%s 2> /dev/null || echo 0
  else
    date -d "$iso_ts" +%s 2> /dev/null || date -d "$normalized" +%s 2> /dev/null || echo 0
  fi
}

skill_eval_filter_records_since() {
  local metric_file="${1:-}"
  local cutoff_date="${2:-2000-01-01T00:00:00Z}"

  while IFS= read -r line; do
    local ts
    ts=$(echo "$line" | jq -r '.timestamp // "2000-01-01T00:00:00Z"' 2> /dev/null || echo "2000-01-01T00:00:00Z")
    if [[ "$ts" > "$cutoff_date" ]]; then
      echo "$line"
    fi
  done < "$metric_file"
}

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
  local metrics_dir metric_file timestamp execution_id valid_metadata record

  metrics_dir=$(skill_metrics_dir "$project_root")
  metric_file=$(skill_metric_file_path "$project_root" "$skill_name")
  mkdir -p "$metrics_dir"

  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  execution_id="${skill_name}_$(date +%s)_$$_$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom 2> /dev/null | head -c 4 || echo "rand")"

  valid_metadata="{}"
  if [[ -n "$metadata" ]] && echo "$metadata" | jq -e . > /dev/null 2>&1; then
    valid_metadata="$metadata"
  fi

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

  echo "$record" >> "$metric_file"

  if declare -f log_event > /dev/null 2>&1; then
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
  local total passed failed duration status metadata

  total=$(echo "$results_json" | jq -r '.total // 1')
  passed=$(echo "$results_json" | jq -r '.passed // 0')
  failed=$(echo "$results_json" | jq -r '.failed // 0')
  duration=$(echo "$results_json" | jq -r '.duration_ms // 0')

  status="success"
  if [[ "$failed" -gt 0 ]] && [[ "$passed" -eq 0 ]]; then
    status="failure"
  elif [[ "$failed" -gt 0 ]]; then
    status="partial"
  fi

  metadata=$(jq -c -n \
    --argjson total "$total" \
    --argjson passed "$passed" \
    --argjson failed "$failed" \
    '{"total": $total, "passed": $passed, "failed": $failed}')

  record_skill_execution "$project_root" "$skill_name" "$status" "$duration" "" "$metadata"
}

# 스킬별 통계 조회
# Usage: get_skill_statistics <project_root> <skill_name> [days]
# Output: JSON with statistics
get_skill_statistics() {
  local project_root="${1:-}"
  local skill_name="${2:-}"
  local days="${3:-30}"
  local metric_file cutoff_date filtered_records filtered_total success_count failure_count
  local partial_count timeout_count total_duration avg_duration success_rate error_messages

  metric_file=$(skill_metric_file_path "$project_root" "$skill_name")

  if [[ ! -f "$metric_file" ]]; then
    jq -n \
      --arg skill "$skill_name" \
      '{skill: $skill, total_executions: 0, success_rate: 0, avg_duration_ms: 0}'
    return 0
  fi

  cutoff_date=$(skill_eval_cutoff_iso "$days")
  filtered_records=$(skill_eval_filter_records_since "$metric_file" "$cutoff_date")
  filtered_total=$(printf '%s\n' "$filtered_records" | awk 'NF { count++ } END { print count + 0 }')

  if [[ "$filtered_total" -eq 0 ]]; then
    jq -n \
      --arg skill "$skill_name" \
      --argjson days "$days" \
      '{skill: $skill, total_executions: 0, success_rate: 0, avg_duration_ms: 0, period_days: $days}'
    return 0
  fi

  success_count=$(echo "$filtered_records" | jq -s '[.[] | select(.status == "success")] | length' 2> /dev/null || echo 0)
  failure_count=$(echo "$filtered_records" | jq -s '[.[] | select(.status == "failure")] | length' 2> /dev/null || echo 0)
  partial_count=$(echo "$filtered_records" | jq -s '[.[] | select(.status == "partial")] | length' 2> /dev/null || echo 0)
  timeout_count=$(echo "$filtered_records" | jq -s '[.[] | select(.status == "timeout")] | length' 2> /dev/null || echo 0)
  total_duration=$(echo "$filtered_records" | jq -s '[.[]?.duration_ms // 0] | add // 0' 2> /dev/null || echo 0)

  avg_duration=0
  if [[ "$filtered_total" -gt 0 ]]; then
    avg_duration=$(awk "BEGIN {printf \"%.0f\", $total_duration / $filtered_total}")
  fi

  success_rate=$(awk "BEGIN {printf \"%.2f\", $success_count / $filtered_total}")
  error_messages=$(echo "$filtered_records" | jq -c -s \
    '[.[] | select(.error != "" and .error != null) | .error] | group_by(.) | map({message: .[0], count: length}) | sort_by(-.count) | .[0:5]' \
    2> /dev/null || echo '[]')

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
  local metrics_dir all_stats total_exec overall_success overall_rate

  metrics_dir=$(skill_metrics_dir "$project_root")
  if [[ ! -d "$metrics_dir" ]]; then
    echo '{"skills": [], "summary": {"total_executions": 0, "overall_success_rate": 0}}'
    return 0
  fi

  all_stats='[]'
  while IFS= read -r file; do
    local skill_name stat
    skill_name=$(basename "$file" .jsonl)
    stat=$(get_skill_statistics "$project_root" "$skill_name" "$days")
    all_stats=$(echo "$all_stats" | jq -c --argjson stat "$stat" '. + [$stat]')
  done < <(find "$metrics_dir" -name '*.jsonl' -type f 2> /dev/null | sort)

  total_exec=$(echo "$all_stats" | jq '[.[].total_executions] | add // 0')
  overall_success=$(echo "$all_stats" | jq -r '.[] | select(.total_executions > 0) | .success_rate * .total_executions' 2> /dev/null | awk '{sum+=$1} END {print sum+0}')

  overall_rate=0
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

# 오래된 메트릭 정리
# Usage: cleanup_old_metrics <project_root> [max_age_days]
cleanup_old_metrics() {
  local project_root="${1:-}"
  local max_age_days="${2:-${MAX_METRICS_AGE_DAYS:-30}}"
  local metrics_dir cutoff_date cleaned

  metrics_dir=$(skill_metrics_dir "$project_root")
  if [[ ! -d "$metrics_dir" ]]; then
    echo "0"
    return 0
  fi

  cleaned=0
  cutoff_date=$(date -v-"${max_age_days}"d +%s 2> /dev/null || date -d "-${max_age_days} days" +%s 2> /dev/null || echo 0)

  for file in "$metrics_dir"/*.jsonl; do
    [[ -f "$file" ]] || continue

    local tmp_file kept
    tmp_file="${file}.tmp"
    kept=0
    : > "$tmp_file"

    while IFS= read -r line; do
      local ts ts_epoch
      ts=$(echo "$line" | jq -r '.timestamp // "2000-01-01T00:00:00Z"' 2> /dev/null || echo "2000-01-01T00:00:00Z")
      ts_epoch=$(skill_eval_iso_to_epoch "$ts")

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
    json | *)
      echo "$stats"
      ;;
  esac
}
