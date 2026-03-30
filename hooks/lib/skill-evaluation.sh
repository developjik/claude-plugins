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

if [[ -z "${SKILL_EVALUATION_LIB_DIR:-}" ]]; then
  SKILL_EVALUATION_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
fi

if ! declare -f record_skill_execution > /dev/null 2>&1; then
  # shellcheck source=hooks/lib/skill-metrics.sh
  source "${SKILL_EVALUATION_LIB_DIR}/skill-metrics.sh"
fi

if ! declare -f calculate_skill_score > /dev/null 2>&1; then
  # shellcheck source=hooks/lib/skill-scoring.sh
  source "${SKILL_EVALUATION_LIB_DIR}/skill-scoring.sh"
fi

if ! declare -f generate_skill_dashboard > /dev/null 2>&1; then
  # shellcheck source=hooks/lib/skill-report.sh
  source "${SKILL_EVALUATION_LIB_DIR}/skill-report.sh"
fi
