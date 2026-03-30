#!/usr/bin/env bash
# review-engine.sh — 2단계 리뷰 시스템
# P1-1: superpowers의 "two-stage review" 패턴 벤치마킹
#
# DEPENDENCIES: json-utils.sh, logging.sh, subagent-spawner.sh, state-machine.sh
#
# Stage 1: 스펙 준수 검증 (Spec Compliance)
# Stage 2: 코드 품질 리뷰 (Code Quality Review - Fresh Subagent)

set -euo pipefail

# ============================================================================
# 상수
# ============================================================================

readonly REVIEW_DIR=".harness/review"
readonly REVIEW_PASS_THRESHOLD=0.90
readonly QUALITY_PASS_THRESHOLD=0.85

if [[ -z "${REVIEW_ENGINE_LIB_DIR:-}" ]]; then
  REVIEW_ENGINE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

review_runtime_python_bin() {
  echo "${HARNESS_REVIEW_PYTHON_BIN:-python3}"
}

review_normalizer_script_path() {
  echo "${HARNESS_REVIEW_NORMALIZER_SCRIPT:-${REVIEW_ENGINE_LIB_DIR}/../../scripts/runtime/review_normalize.py}"
}

review_score_script_path() {
  echo "${HARNESS_REVIEW_SCORE_SCRIPT:-${REVIEW_ENGINE_LIB_DIR}/../../scripts/runtime/review_score.py}"
}

can_use_review_normalizer() {
  local python_bin script_path
  python_bin=$(review_runtime_python_bin)
  script_path=$(review_normalizer_script_path)

  command -v "$python_bin" > /dev/null 2>&1 && [[ -f "$script_path" ]]
}

can_use_review_score_helper() {
  local python_bin script_path
  python_bin=$(review_runtime_python_bin)
  script_path=$(review_score_script_path)

  command -v "$python_bin" > /dev/null 2>&1 && [[ -f "$script_path" ]]
}

# ============================================================================
# 내부 모듈 로드
# ============================================================================
if ! declare -f extract_expected_files > /dev/null 2>&1; then
  # shellcheck source=hooks/lib/review-evidence.sh
  source "${REVIEW_ENGINE_LIB_DIR}/review-evidence.sh"
fi

# 스펙 준수 종합 검증
# Usage: verify_spec_compliance <project_root> <feature_slug>
# Output: JSON with compliance report
verify_spec_compliance() {
  local project_root="${1:-}"
  local feature_slug="${2:-}"

  local design_file="${project_root}/docs/specs/${feature_slug}/design.md"
  local plan_file="${project_root}/docs/specs/${feature_slug}/plan.md"

  # 결과 디렉토리 생성
  local results_dir="${project_root}/${REVIEW_DIR}"
  mkdir -p "$results_dir"

  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)

  # 1. 파일 존재 확인
  local expected_files
  expected_files=$(extract_expected_files "$design_file")

  local file_check
  file_check=$(check_file_existence "$project_root" "$expected_files")

  # 파일 점수 계산
  local file_total file_found file_score
  file_total=$(echo "$file_check" | jq -r '.total // 0')
  file_found=$(echo "$file_check" | jq -r '.found // 0')

  if [[ "$file_total" -gt 0 ]]; then
    file_score=$(awk "BEGIN {printf \"%.2f\", $file_found / $file_total}")
  else
    file_score="1.00"
  fi

  # 2. API 시그니처 확인
  local expected_apis
  expected_apis=$(extract_api_signatures "$design_file")

  local api_check
  api_check=$(check_api_signatures "$project_root" "$expected_apis")

  # API 점수 계산
  local api_total api_found api_score
  api_total=$(echo "$api_check" | jq -r '.total // 0')
  api_found=$(echo "$api_check" | jq -r '.found // 0')

  if [[ "$api_total" -gt 0 ]]; then
    api_score=$(awk "BEGIN {printf \"%.2f\", $api_found / $api_total}")
  else
    api_score="1.00"
  fi

  # 3. 기능 요구사항 확인
  local fr_check
  fr_check=$(check_functional_requirements "$project_root" "$plan_file")

  local fr_score
  fr_score=$(echo "$fr_check" | jq -r '.score // 1')

  # 4. 종합 점수 계산 (적용 가능한 체크만 반영)
  # 파일: 30%, API: 20%, FR: 50%
  local overall_score
  local weighted_sum="0.00"
  local total_weight="0.00"

  if [[ "$file_total" -gt 0 ]]; then
    weighted_sum=$(awk -v current="$weighted_sum" -v score="$file_score" 'BEGIN {printf "%.2f", current + (score * 0.30)}')
    total_weight=$(awk -v current="$total_weight" 'BEGIN {printf "%.2f", current + 0.30}')
  fi

  if [[ "$api_total" -gt 0 ]]; then
    weighted_sum=$(awk -v current="$weighted_sum" -v score="$api_score" 'BEGIN {printf "%.2f", current + (score * 0.20)}')
    total_weight=$(awk -v current="$total_weight" 'BEGIN {printf "%.2f", current + 0.20}')
  fi

  local fr_total
  fr_total=$(echo "$fr_check" | jq -r '.total // 0')
  if [[ "$fr_total" -gt 0 ]]; then
    weighted_sum=$(awk -v current="$weighted_sum" -v score="$fr_score" 'BEGIN {printf "%.2f", current + (score * 0.50)}')
    total_weight=$(awk -v current="$total_weight" 'BEGIN {printf "%.2f", current + 0.50}')
  fi

  if awk -v weight="$total_weight" 'BEGIN {exit !(weight > 0)}'; then
    overall_score=$(awk -v sum="$weighted_sum" -v weight="$total_weight" 'BEGIN {printf "%.2f", sum / weight}')
  else
    overall_score="1.00"
  fi

  # 판정
  local passed="false"
  if awk "BEGIN {exit !($overall_score >= $REVIEW_PASS_THRESHOLD)}"; then
    passed="true"
  fi

  # 결과 조립 (--arg 대신 --arg를 사용하고 jq 내에서 변환)
  local result
  result=$(jq -n \
    --arg ts "$timestamp" \
    --arg fs "$feature_slug" \
    --arg passed "$passed" \
    --arg overall "$overall_score" \
    --arg file_score "$file_score" \
    --arg api_score "$api_score" \
    --arg fr_score "$fr_score" \
    --argjson file_check "$file_check" \
    --argjson api_check "$api_check" \
    --argjson fr_check "$fr_check" \
    '{
      timestamp: $ts,
      feature_slug: $fs,
      stage: "spec_compliance",
      passed: ($passed == "true"),
      overall_score: ($overall | tonumber),
      scores: {
        file_existence: ($file_score | tonumber),
        api_signatures: ($api_score | tonumber),
        functional_requirements: ($fr_score | tonumber)
      },
      checks: {
        file_existence: $file_check,
        api_signatures: $api_check,
        functional_requirements: $fr_check
      }
    }')

  # 결과 저장
  echo "$result" > "${results_dir}/spec_compliance_${timestamp}.json"

  echo "$result"
}

# ============================================================================
# Stage 2: 코드 품질 리뷰 (Fresh Subagent)
# ============================================================================

# 서브에이전트로 코드 품질 리뷰 태스크 생성
# Usage: create_review_task <project_root> <feature_slug>
create_review_task() {
  local project_root="${1:-}"
  local feature_slug="${2:-}"

  cat << TASK_EOF
# Code Quality Review Task

Feature Slug: ${feature_slug}
Plan File: docs/specs/${feature_slug}/plan.md
Design File: docs/specs/${feature_slug}/design.md

Review the implementation for quality and best practices.

## Review Checklist

### 1. SOLID Principles
- Single Responsibility: Each class/function has one purpose?
- Open/Closed: Easy to extend without modification?
- Liskov Substitution: Subtypes substitutable for base types?
- Interface Segregation: Interfaces specific and cohesive?
- Dependency Inversion: Depend on abstractions, not concretions?

### 2. Code Quality
- DRY: No duplicated code?
- Function length: Under 20 lines?
- Cyclomatic complexity: Under 10?
- Naming: Clear and descriptive?

### 3. Error Handling
- All edge cases covered?
- Errors properly propagated?

### 4. Security
- Input validation present?
- No hardcoded secrets?

### 5. Testing
- Unit tests for core logic?
- Edge cases tested?

## Output Format

Return a JSON object with scores (0.0-1.0) and issues list.
TASK_EOF
}

# 리뷰 태스크에서 feature slug 추출
extract_review_feature_slug_from_task() {
  local project_root="${1:-}"
  local subagent_id="${2:-}"
  local subagents_dir="${SUBAGENT_DIR:-.harness/subagents}"
  local task_file="${project_root}/${subagents_dir}/${subagent_id}/task.md"

  if [[ -f "$task_file" ]]; then
    sed -n 's/^Feature Slug:[[:space:]]*//p' "$task_file" | head -1
  fi
}

# 리뷰 결과 텍스트에서 JSON payload 추출
extract_review_json_payload() {
  local result_content="${1:-}"

  if [[ -z "$result_content" ]]; then
    return 1
  fi

  if echo "$result_content" | jq -e '.' > /dev/null 2>&1; then
    echo "$result_content"
    return 0
  fi

  local fenced_json=""
  fenced_json=$(printf '%s\n' "$result_content" | sed -n '/```json/,/```/p' | sed '1d;$d')
  if [[ -z "$fenced_json" ]]; then
    fenced_json=$(printf '%s\n' "$result_content" | sed -n '/```/,/```/p' | sed '1d;$d')
  fi

  if [[ -n "$fenced_json" ]] && echo "$fenced_json" | jq -e '.' > /dev/null 2>&1; then
    echo "$fenced_json"
    return 0
  fi

  return 1
}

# 코드 품질 리뷰 결과 정규화 (Bash fallback)
normalize_code_quality_review_result_bash() {
  local parsed_review_json="${1:-}"
  local feature_slug="${2:-}"
  local subagent_id="${3:-}"
  local timestamp="${4:-}"

  if [[ -z "$parsed_review_json" ]]; then
    parsed_review_json='{}'
  fi

  jq -n \
    --argjson review "$parsed_review_json" \
    --arg ts "$timestamp" \
    --arg fs "$feature_slug" \
    --arg sid "$subagent_id" \
    '
    def clamp01:
      if . == null then null
      elif . < 0 then 0
      elif . > 1 then 1
      else . end;
    def numeric_or_null:
      if . == null then null
      elif type == "number" then .
      elif type == "string" then (tonumber? // null)
      else null end;
    def normalize_issue:
      if . == null then empty
      elif type == "string" then
        {severity: "medium", category: "general", title: ., details: null, file: null}
      elif type == "object" then
        {
          severity: ((.severity // .level // .priority // "medium") | ascii_downcase),
          category: (.category // .type // "general"),
          title: (.title // .message // .summary // "Issue"),
          details: (.details // .description // .reason // null),
          file: (.file // .path // null)
        }
      else
        {severity: "medium", category: "general", title: (tostring), details: null, file: null}
      end;
    def penalty:
      if . == "critical" then 0.30
      elif . == "high" then 0.20
      elif . == "medium" then 0.10
      elif . == "low" then 0.05
      else 0.08 end;
    ($review.issues // $review.findings // $review.problems // []) as $raw_issues |
    ([ $raw_issues[]? | normalize_issue ]) as $issues |
    (
      ($review.scores // $review.category_scores // $review.categories // {})
      | to_entries
      | map({key: .key, value: (.value | numeric_or_null)})
      | map(select(.value != null))
    ) as $score_entries |
    ($score_entries | map(.value)) as $score_values |
    (
      $review.overall_score
      // $review.score
      // $review.scores.overall
      // (if (($review.summary // null) | type) == "object" then $review.summary.overall_score else null end)
      | numeric_or_null
    ) as $direct_score |
    (
      if $direct_score != null then
        ($direct_score | clamp01)
      elif ($score_values | length) > 0 then
        ((($score_values | add) / ($score_values | length)) | clamp01)
      elif ($issues | length) > 0 then
        (reduce $issues[] as $issue (1; . - ($issue.severity | penalty)) | if . < 0 then 0 else . end)
      else
        null
      end
    ) as $overall_score |
    {
      timestamp: $ts,
      feature_slug: $fs,
      stage: "code_quality",
      subagent_id: $sid,
      status: "completed",
      overall_score: $overall_score,
      summary: ($review.summary // $review.overview // $review.verdict // null),
      scores: ($score_entries | from_entries),
      issues: $issues,
      failure_reason: null,
      source: "subagent_review_output"
    }'
}

normalize_code_quality_review_result_python() {
  local parsed_review_json="${1:-}"
  local feature_slug="${2:-}"
  local subagent_id="${3:-}"
  local timestamp="${4:-}"
  local python_bin script_path

  if [[ -z "$parsed_review_json" ]]; then
    parsed_review_json='{}'
  fi

  if ! can_use_review_normalizer; then
    return 1
  fi

  python_bin=$(review_runtime_python_bin)
  script_path=$(review_normalizer_script_path)

  jq -n \
    --argjson review "$parsed_review_json" \
    --arg ts "$timestamp" \
    --arg fs "$feature_slug" \
    --arg sid "$subagent_id" \
    '{
      review: $review,
      timestamp: $ts,
      feature_slug: $fs,
      subagent_id: $sid
    }' | "$python_bin" "$script_path"
}

# 코드 품질 리뷰 결과 정규화
normalize_code_quality_review_result() {
  local parsed_review_json="${1:-}"
  local feature_slug="${2:-}"
  local subagent_id="${3:-}"
  local timestamp="${4:-}"
  local normalized_result=""

  if normalized_result=$(normalize_code_quality_review_result_python "$parsed_review_json" "$feature_slug" "$subagent_id" "$timestamp" 2> /dev/null); then
    echo "$normalized_result"
    return 0
  fi

  normalize_code_quality_review_result_bash "$parsed_review_json" "$feature_slug" "$subagent_id" "$timestamp"
}

# 최신 실제 코드 품질 리뷰 결과 조회
load_latest_code_quality_result() {
  local project_root="${1:-}"
  local feature_slug="${2:-}"

  local results_dir="${project_root}/${REVIEW_DIR}"
  if [[ ! -d "$results_dir" ]]; then
    return 1
  fi

  local file
  for file in $(find "$results_dir" -name "code_quality_result_*.json" -type f 2> /dev/null | sort -r); do
    if jq -e --arg fs "$feature_slug" '.feature_slug == $fs and .status == "completed" and (.overall_score != null)' "$file" > /dev/null 2>&1; then
      cat "$file"
      return 0
    fi
  done

  return 1
}

# fallback 품질 점수 생성
build_quality_fallback_result() {
  local project_root="${1:-}"
  local feature_slug="${2:-}"
  local trigger_result="${3:-}"
  local fallback_reason="${4:-actual_review_output_unavailable}"

  if [[ -z "$trigger_result" ]]; then
    trigger_result='{}'
  fi

  local estimated_score
  estimated_score=$(estimate_quality_score "$project_root")
  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)

  jq -n \
    --arg ts "$timestamp" \
    --arg fs "$feature_slug" \
    --arg reason "$fallback_reason" \
    --arg score "$estimated_score" \
    --argjson trigger "$trigger_result" \
    '{
      timestamp: $ts,
      feature_slug: $fs,
      stage: "code_quality",
      subagent_id: ($trigger.subagent_id // ""),
      status: "fallback_estimated",
      overall_score: ($score | tonumber),
      summary: "Used static estimation because actual code review output was unavailable.",
      scores: {},
      issues: [],
      failure_reason: null,
      fallback: {
        applied: true,
        reason: $reason,
        trigger_status: ($trigger.status // "missing_result"),
        strategy: "estimate_quality_score"
      },
      source: "static_estimate"
    }'
}

build_two_stage_review_result_bash() {
  local timestamp="${1:-}"
  local feature_slug="${2:-}"
  local spec_result="${3:-}"
  local quality_result="${4:-}"

  local spec_score quality_score combined_score passed
  spec_score=$(echo "$spec_result" | jq -r '.overall_score // 0')
  quality_score=$(echo "$quality_result" | jq -r '.overall_score // 1')
  combined_score=$(awk -v ss="$spec_score" -v qs="$quality_score" 'BEGIN {printf "%.2f", (ss * 0.6) + (qs * 0.4)}')

  passed="false"
  if awk "BEGIN {exit !($combined_score >= $REVIEW_PASS_THRESHOLD)}"; then
    passed="true"
  fi

  jq -n \
    --arg ts "$timestamp" \
    --arg fs "$feature_slug" \
    --arg passed "$passed" \
    --arg spec_score "$spec_score" \
    --arg quality_score "$quality_score" \
    --arg combined_score "$combined_score" \
    --argjson spec_result "$spec_result" \
    --argjson quality_result "$quality_result" \
    '{
      timestamp: $ts,
      feature_slug: $fs,
      stage1_spec_compliance: $spec_result,
      stage2_code_quality: $quality_result,
      overall: {
        spec_score: ($spec_score | tonumber),
        quality_score: ($quality_score | tonumber),
        combined_score: ($combined_score | tonumber),
        passed: ($passed == "true")
      }
    }'
}

build_two_stage_review_result_python() {
  local timestamp="${1:-}"
  local feature_slug="${2:-}"
  local spec_result="${3:-}"
  local quality_result="${4:-}"
  local python_bin script_path

  if ! can_use_review_score_helper; then
    return 1
  fi

  python_bin=$(review_runtime_python_bin)
  script_path=$(review_score_script_path)

  jq -n \
    --arg ts "$timestamp" \
    --arg fs "$feature_slug" \
    --arg threshold "$REVIEW_PASS_THRESHOLD" \
    --argjson spec_result "$spec_result" \
    --argjson quality_result "$quality_result" \
    '{
      timestamp: $ts,
      feature_slug: $fs,
      review_pass_threshold: ($threshold | tonumber),
      spec_weight: 0.6,
      quality_weight: 0.4,
      spec_result: $spec_result,
      quality_result: $quality_result
    }' | "$python_bin" "$script_path"
}

build_two_stage_review_result() {
  local timestamp="${1:-}"
  local feature_slug="${2:-}"
  local spec_result="${3:-}"
  local quality_result="${4:-}"
  local combined_result=""

  if combined_result=$(build_two_stage_review_result_python "$timestamp" "$feature_slug" "$spec_result" "$quality_result" 2> /dev/null); then
    echo "$combined_result"
    return 0
  fi

  build_two_stage_review_result_bash "$timestamp" "$feature_slug" "$spec_result" "$quality_result"
}

# 서브에이전트로 코드 품질 리뷰 스폰
# Usage: spawn_subagent_for_review <project_root> <feature_slug>
# Output: JSON with quality report info
spawn_subagent_for_review() {
  local project_root="${1:-}"
  local feature_slug="${2:-}"

  # 라이브러리 로드
  local lib_dir
  lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  if ! declare -f spawn_subagent &> /dev/null; then
    if [[ -f "${lib_dir}/subagent-spawner.sh" ]]; then
      source "${lib_dir}/subagent-spawner.sh"
    fi
  fi

  # 리뷰 태스크 생성
  local task_content
  task_content=$(create_review_task "$project_root" "$feature_slug")

  # 결과 디렉토리
  local results_dir="${project_root}/${REVIEW_DIR}"
  mkdir -p "$results_dir"

  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)

  # 서브에이전트 스폰 (함수가 있으면)
  local subagent_id=""
  local execution_contract='{}'
  if declare -f spawn_subagent &> /dev/null; then
    local task_file
    task_file=$(mktemp)
    echo "$task_content" > "$task_file"
    subagent_id=$(spawn_subagent "$task_file" "$project_root" "sonnet" "code_review" 2> /dev/null || echo "")
    if [[ -n "$subagent_id" ]] && declare -f prepare_for_agent_execution &> /dev/null; then
      execution_contract=$(prepare_for_agent_execution "$subagent_id" "$project_root" 2> /dev/null || echo '{}')
    fi
    rm -f "$task_file"
  fi

  # 결과 반환
  local result
  result=$(jq -n \
    --arg ts "$timestamp" \
    --arg fs "$feature_slug" \
    --arg sid "$subagent_id" \
    --argjson contract "$execution_contract" \
    '{
      timestamp: $ts,
      feature_slug: $fs,
      stage: "code_quality",
      subagent_id: $sid,
      status: (if $sid == "" then "spawn_failed" else "pending_execution" end),
      overall_score: null,
      summary: (if $sid == "" then "Failed to spawn code quality review subagent." else "Fresh subagent prepared for external execution." end),
      issues: [],
      execution_request_file: ($contract.execution_request_file // null),
      artifacts: ($contract.artifacts // null),
      fallback_policy: {
        when: ["pending_execution", "review_execution_failed", "parse_failed", "missing_result", "spawn_failed"],
        strategy: "estimate_quality_score"
      }
    }')

  # 결과 저장
  echo "$result" > "${results_dir}/code_quality_${timestamp}.json"

  echo "$result"
}

# 서브에이전트 결과 처리
# Usage: process_review_result <project_root> <subagent_id> <result_content>
process_review_result() {
  local project_root="${1:-}"
  local subagent_id="${2:-}"
  local result_content="${3:-}"

  local results_dir="${project_root}/${REVIEW_DIR}"
  mkdir -p "$results_dir"
  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)

  local lib_dir
  lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if ! declare -f collect_subagent_execution_result &> /dev/null; then
    if [[ -f "${lib_dir}/subagent-spawner.sh" ]]; then
      source "${lib_dir}/subagent-spawner.sh"
    fi
  fi

  local execution_result="{}"
  local execution_status="completed"
  local execution_failure="null"
  local review_payload="$result_content"

  if [[ -n "$subagent_id" ]] && declare -f collect_subagent_execution_result &> /dev/null; then
    execution_result=$(collect_subagent_execution_result "$subagent_id" "$project_root" "$result_content" 2> /dev/null || echo '{}')
    if echo "$execution_result" | jq -e '.' > /dev/null 2>&1; then
      execution_status=$(echo "$execution_result" | jq -r '.status // "completed"' 2> /dev/null)
      execution_failure=$(echo "$execution_result" | jq -c '.failure_reason // null' 2> /dev/null)
      review_payload=$(echo "$execution_result" | jq -r '
        if (.result_content // "") != "" then
          .result_content
        elif (.raw.overall_score // .raw.score // .raw.issues // .raw.findings // .raw.problems // .raw.scores) != null then
          (.raw | tojson)
        else
          ""
        end
      ' 2> /dev/null)
    fi
  fi

  local feature_slug=""
  if [[ -n "$subagent_id" ]]; then
    feature_slug=$(extract_review_feature_slug_from_task "$project_root" "$subagent_id")
  fi

  local parsed_review_json=""
  local normalized_result=""
  local finalization_payload=""

  if [[ "$execution_status" != "completed" ]]; then
    normalized_result=$(jq -n \
      --arg ts "$timestamp" \
      --arg fs "$feature_slug" \
      --arg sid "$subagent_id" \
      --arg exec_status "$execution_status" \
      --argjson exec_failure "$execution_failure" \
      '{
        timestamp: $ts,
        feature_slug: $fs,
        stage: "code_quality",
        subagent_id: $sid,
        status: "review_execution_failed",
        overall_score: null,
        summary: "Subagent execution failed before a review result could be parsed.",
        scores: {},
        issues: [
          {
            severity: "high",
            category: "execution",
            title: "Code quality review execution failed",
            details: ($exec_failure.message // "No structured failure reason provided."),
            file: null
          }
        ],
        failure_reason: ($exec_failure // {code: "review_execution_failed", message: "Code quality review execution failed", details: null}),
        execution: {
          status: $exec_status,
          failure_reason: $exec_failure
        },
        source: "subagent_execution"
      }')
    finalization_payload=$(jq -n \
      --arg status "$execution_status" \
      --arg content "$review_payload" \
      --argjson failure "$execution_failure" \
      '{status: $status, result_content: $content, failure_reason: $failure}')
  elif parsed_review_json=$(extract_review_json_payload "$review_payload"); then
    if [[ -z "$feature_slug" ]]; then
      feature_slug=$(echo "$parsed_review_json" | jq -r '.feature_slug // .feature // .slug // empty' 2> /dev/null)
    fi

    normalized_result=$(normalize_code_quality_review_result "$parsed_review_json" "$feature_slug" "$subagent_id" "$timestamp")
    finalization_payload=$(jq -n \
      --arg content "$review_payload" \
      '{status: "completed", result_content: $content, failure_reason: null}')
  else
    normalized_result=$(jq -n \
      --arg ts "$timestamp" \
      --arg fs "$feature_slug" \
      --arg sid "$subagent_id" \
      --arg raw "$review_payload" \
      '{
        timestamp: $ts,
        feature_slug: $fs,
        stage: "code_quality",
        subagent_id: $sid,
        status: "parse_failed",
        overall_score: null,
        summary: "Code quality review output was not valid JSON.",
        scores: {},
        issues: [
          {
            severity: "high",
            category: "parsing",
            title: "Invalid code quality review JSON",
            details: "The subagent output could not be parsed into the expected JSON schema.",
            file: null
          }
        ],
        failure_reason: {
          code: "parse_failed",
          message: "Code quality review output was not valid JSON.",
          details: {
            raw_output: $raw
          }
        },
        execution: {
          status: "completed",
          failure_reason: null
        },
        source: "subagent_review_output"
      }')
    finalization_payload=$(jq -n \
      --arg content "$review_payload" \
      '{
        status: "failed",
        result_content: $content,
        failure_reason: {
          code: "parse_failed",
          message: "Code quality review output was not valid JSON.",
          details: null
        }
      }')
  fi

  if [[ -n "$subagent_id" ]] && declare -f finalize_subagent_execution &> /dev/null; then
    finalize_subagent_execution "$subagent_id" "$project_root" "$finalization_payload" > /dev/null 2>&1 || true
  fi

  # 결과 저장
  local result_file="${results_dir}/code_quality_result_${timestamp}.json"
  echo "$normalized_result" > "$result_file"

  echo "$normalized_result"
}

# ============================================================================
# 통합 2단계 리뷰 실행
# ============================================================================

# 2단계 리뷰 통합 실행
# Usage: run_two_stage_review <project_root> <feature_slug> [--skip-quality]
# Output: JSON with combined results
run_two_stage_review() {
  local project_root="${1:-}"
  local feature_slug="${2:-}"
  local skip_quality="${3:-}"

  local results_dir="${project_root}/${REVIEW_DIR}"
  mkdir -p "$results_dir"

  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)

  echo "🔍 Running 2-Stage Review"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  # ========================================
  # Stage 1: 스펙 준수 검증
  # ========================================
  echo "📋 Stage 1: Spec Compliance Review..."

  local spec_result spec_score
  spec_result=$(verify_spec_compliance "$project_root" "$feature_slug")
  spec_score=$(echo "$spec_result" | jq -r '.overall_score // 0')

  local spec_pct
  spec_pct=$(awk -v score="$spec_score" 'BEGIN {printf "%.0f", score * 100}')
  echo "  Score: ${spec_pct}%"
  echo ""

  # ========================================
  # Stage 2: 코드 품질 리뷰 (옵션)
  # ========================================
  local quality_result quality_score
  quality_result='{"status":"skipped","overall_score":1,"issues":[],"summary":"Quality review skipped."}'
  quality_score="1.00"

  if [[ "$skip_quality" != "--skip-quality" ]]; then
    echo "🔎 Stage 2: Code Quality Review..."
    echo "  Spawning fresh subagent for independent review..."

    quality_result=$(spawn_subagent_for_review "$project_root" "$feature_slug")

    local actual_quality_result=""
    actual_quality_result=$(load_latest_code_quality_result "$project_root" "$feature_slug" 2> /dev/null || true)
    if [[ -n "$actual_quality_result" ]]; then
      quality_result="$actual_quality_result"
    else
      quality_result=$(build_quality_fallback_result "$project_root" "$feature_slug" "$quality_result" "actual_review_output_unavailable")
    fi

    quality_score=$(echo "$quality_result" | jq -r '.overall_score // 0')

    local quality_pct
    quality_pct=$(awk -v score="$quality_score" 'BEGIN {printf "%.0f", score * 100}')
    echo "  Score: ${quality_pct}%"
    echo ""
  else
    echo "🔎 Stage 2: (Skipped)"
    echo ""
  fi

  # ========================================
  # 종합 판정
  # ========================================
  local combined_result
  combined_result=$(build_two_stage_review_result "$timestamp" "$feature_slug" "$spec_result" "$quality_result")

  local combined_score passed
  combined_score=$(echo "$combined_result" | jq -r '.overall.combined_score // 0')
  passed=$(echo "$combined_result" | jq -r '.overall.passed // false')

  # 결과 저장
  echo "$combined_result" > "${results_dir}/two_stage_review_${timestamp}.json"

  # ========================================
  # 결과 출력
  # ========================================
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📊 Review Summary"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  local spec_pct quality_pct combined_pct
  spec_pct=$(awk -v score="$spec_score" 'BEGIN {printf "%.0f", score * 100}')
  quality_pct=$(awk -v score="$quality_score" 'BEGIN {printf "%.0f", score * 100}')
  combined_pct=$(awk -v score="$combined_score" 'BEGIN {printf "%.0f", score * 100}')

  echo "  Stage 1 (Spec Compliance):  ${spec_pct}%"
  echo "  Stage 2 (Code Quality):     ${quality_pct}%"
  echo ""
  echo "  📈 Combined Score: ${combined_pct}%"
  echo ""

  if [[ "$passed" == "true" ]]; then
    echo "  ✅ VERDICT: PASSED"
  else
    echo "  ❌ VERDICT: NEEDS IMPROVEMENT"
    echo ""

    # 실패 시 상세 정보
    echo "  Missing Files:"
    echo "$spec_result" | jq -r '.checks.file_existence.missing[]? // empty' 2> /dev/null | while read -r file; do
      echo "    - $file"
    done

    local missing_files
    missing_files=$(echo "$spec_result" | jq -r '.checks.file_existence.missing | length' 2> /dev/null)
    if [[ "$missing_files" == "0" ]] || [[ -z "$missing_files" ]]; then
      echo "    (none)"
    fi
  fi

  echo ""
  echo "$combined_result"
}

# ============================================================================
# 헬퍼 함수
# ============================================================================

# 정적 분석으로 품질 점수 추정
# Usage: estimate_quality_score <project_root>
estimate_quality_score() {
  local project_root="${1:-}"
  local score=0.85

  # 소스 파일 수 확인
  local src_file_count
  src_file_count=$(find "${project_root}/src" \( -name "*.ts" -o -name "*.js" -o -name "*.py" \) 2> /dev/null | wc -l | tr -d ' ')

  # 테스트 파일 수 확인
  local test_file_count
  test_file_count=$(find "${project_root}" \( -name "*.test.*" -o -name "*.spec.*" \) 2> /dev/null | wc -l | tr -d ' ')

  # 테스트 비율이 높으면 점수 증가
  if [[ "$src_file_count" -gt 0 ]] && [[ "$test_file_count" -gt 0 ]]; then
    local test_ratio
    test_ratio=$(awk "BEGIN {printf \"%.2f\", $test_file_count / $src_file_count}")
    if awk "BEGIN {exit !($test_ratio >= 0.5)}"; then
      score=0.90
    fi
  fi

  # 린트 에러 확인 (package.json이 있는 경우)
  if [[ -f "${project_root}/package.json" ]]; then
    local lint_errors
    lint_errors=$(cd "$project_root" && npm run lint 2>&1 | grep -c "error" || echo 0)
    if [[ "$lint_errors" -gt 0 ]]; then
      score=$(awk -v s="$score" -v errs="$lint_errors" 'BEGIN {printf "%.2f", s - (errs * 0.02)}')
    fi
  fi

  # 점수 범위 제한
  if awk -v s="$score" 'BEGIN {exit !(s < 0)}'; then
    score=0
  elif awk -v s="$score" 'BEGIN {exit !(s > 1)}'; then
    score=1
  fi

  echo "$score"
}

# 일치도 계산
# Usage: calculate_match_rate <spec_result> <quality_result>
calculate_match_rate() {
  local spec_result="${1:-}"
  local quality_result="${2:-}"
  local score_payload spec_payload quality_payload

  spec_payload="${spec_result:-}"
  quality_payload="${quality_result:-}"
  if [[ -z "$spec_payload" ]]; then
    spec_payload='{}'
  fi
  if [[ -z "$quality_payload" ]]; then
    quality_payload='{}'
  fi

  score_payload=$(build_two_stage_review_result "$(date +%Y%m%d_%H%M%S)" "" "$spec_payload" "$quality_payload")
  echo "$score_payload" | jq -r '.overall.combined_score // 0'
}

# 리뷰 히스토리 조회
# Usage: get_review_history <project_root> [limit]
get_review_history() {
  local project_root="${1:-}"
  local limit="${2:-10}"

  local results_dir="${project_root}/${REVIEW_DIR}"

  if [[ ! -d "$results_dir" ]]; then
    echo '[]'
    return 0
  fi

  local history='[]'
  local count=0

  for file in $(find "$results_dir" -name "two_stage_review_*.json" -type f 2> /dev/null | sort -r); do
    if [[ $count -ge $limit ]]; then
      break
    fi

    local entry
    entry=$(jq -c '{timestamp: .timestamp, feature_slug: .feature_slug, passed: .overall.passed, score: .overall.combined_score}' "$file" 2> /dev/null)

    if [[ -n "$entry" ]]; then
      history=$(jq -n --argjson current "$history" --argjson entry "$entry" '$current + [$entry]' 2> /dev/null || echo "$history")
      count=$((count + 1))
    fi
  done

  echo "$history"
}

# 리뷰 결과 정리 (오래된 결과 삭제)
# Usage: cleanup_old_reviews <project_root> [max_age_days]
cleanup_old_reviews() {
  local project_root="${1:-}"
  local max_age_days="${2:-30}"

  local results_dir="${project_root}/${REVIEW_DIR}"

  if [[ ! -d "$results_dir" ]]; then
    echo "0"
    return 0
  fi

  local cleaned=0
  local now
  now=$(date +%s)
  local max_age_seconds=$((max_age_days * 86400))

  for file in "$results_dir"/*.json; do
    if [[ -f "$file" ]]; then
      local file_ts
      file_ts=$(stat -f %m "$file" 2> /dev/null || stat -c %Y "$file" 2> /dev/null || echo 0)
      local age=$((now - file_ts))

      if [[ $age -gt $max_age_seconds ]]; then
        rm -f "$file"
        cleaned=$((cleaned + 1))
      fi
    fi
  done

  echo "$cleaned"
}
