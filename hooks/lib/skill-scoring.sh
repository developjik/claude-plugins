#!/usr/bin/env bash
# skill-scoring.sh — skill-evaluation score, ranking, anomaly helpers

set -euo pipefail

if [[ -z "${SKILL_EVALUATION_LIB_DIR:-}" ]]; then
  SKILL_EVALUATION_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
fi

if ! declare -f get_all_skill_statistics > /dev/null 2>&1; then
  # shellcheck source=hooks/lib/skill-metrics.sh
  source "${SKILL_EVALUATION_LIB_DIR}/skill-metrics.sh"
fi

skill_eval_min_sample_size() {
  echo "${MIN_SAMPLE_SIZE:-5}"
}

# 스킬 점수 계산
# Usage: calculate_skill_score <stats_json>
# Output: 0.0-1.0 score
calculate_skill_score() {
  local stats_json="${1:-}"
  local min_sample_size total success_rate avg_duration time_score final_score

  min_sample_size=$(skill_eval_min_sample_size)
  total=$(echo "$stats_json" | jq -r '.total_executions // 0')
  success_rate=$(echo "$stats_json" | jq -r '.success_rate // 0')
  avg_duration=$(echo "$stats_json" | jq -r '.avg_duration_ms // 0')

  if [[ "$total" -lt "$min_sample_size" ]]; then
    echo "0.5"
    return 0
  fi

  time_score=0.5
  if [[ "$avg_duration" -gt 0 ]]; then
    if [[ "$avg_duration" -le 1000 ]]; then
      time_score=1.0
    elif [[ "$avg_duration" -ge 10000 ]]; then
      time_score=0.0
    else
      time_score=$(awk -v dur="$avg_duration" 'BEGIN {printf "%.2f", 1 - (dur - 1000) / 9000}')
    fi
  fi

  final_score=$(awk -v sr="$success_rate" -v ts="$time_score" 'BEGIN {printf "%.2f", (sr * 0.7) + (ts * 0.3)}')
  echo "$final_score"
}

# 스킬 랭킹 계산
# Usage: rank_skills <project_root> [days]
rank_skills() {
  local project_root="${1:-}"
  local days="${2:-30}"
  local stats ranked

  stats=$(get_all_skill_statistics "$project_root" "$days")
  ranked='[]'

  while IFS= read -r skill_json; do
    local skill score
    skill=$(echo "$skill_json" | jq -r '.skill')
    score=$(calculate_skill_score "$skill_json")
    ranked=$(echo "$ranked" | jq -c --arg skill "$skill" --argjson score "$score" '. + [{skill: $skill, score: $score}]')
  done < <(echo "$stats" | jq -c '.skills[]')

  echo "$ranked" | jq 'sort_by(-.score)'
}

# 이상 탐지 (성능 저하, 에러 급증)
# Usage: detect_anomalies <project_root> [threshold]
detect_anomalies() {
  local project_root="${1:-}"
  local threshold="${2:-0.3}"
  local stats

  stats=$(get_all_skill_statistics "$project_root" "7")

  echo "$stats" | jq --argjson threshold "$threshold" '
    [.skills[] | select(.total_executions >= 5 and .success_rate < $threshold) | {
      skill: .skill,
      type: "low_success_rate",
      value: .success_rate,
      message: "Success rate below threshold"
    }]
  '
}
