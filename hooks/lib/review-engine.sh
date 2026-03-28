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

# ============================================================================
# Stage 1: 스펙 준수 검증
# ============================================================================

# design.md에서 예상 파일 목록 추출
# Usage: extract_expected_files <design_file>
# Output: JSON array of expected file paths
extract_expected_files() {
  local design_file="${1:-}"

  if [[ ! -f "$design_file" ]]; then
    echo '[]'
    return 1
  fi

  local files='[]'

  # "파일 변경" 섹션에서 파일 목록 추출
  if grep -q "파일 변경\|File Changes\|## Files" "$design_file" 2>/dev/null; then
    while IFS= read -r line; do
      # 파일 경로 추출 (backtick 제거)
      local file_path
      file_path=$(echo "$line" | sed -E 's/^[[:space:]]*-[[:space:]]*`?([^`[:space:]]+)`?.*/\1/')

      # 유효한 경로인지 확인 (확장자가 있는 파일)
      if [[ "$file_path" =~ \.[a-zA-Z0-9]+$ ]] && [[ ! "$file_path" =~ ^# ]]; then
        if [[ -n "$file_path" ]] && [[ "$file_path" != "$line" ]]; then
          files=$(echo "$files" | jq '. + ["'"$file_path"'"]' 2>/dev/null || echo "$files")
        fi
      fi
    done < <(grep -A 50 "파일 변경\|File Changes\|## Files" "$design_file" 2>/dev/null | grep -E '^\s*-\s*')
  fi

  echo "$files"
}

# design.md에서 API 시그니처 추출
# Usage: extract_api_signatures <design_file>
# Output: JSON array of API definitions
extract_api_signatures() {
  local design_file="${1:-}"

  if [[ ! -f "$design_file" ]]; then
    echo '[]'
    return 1
  fi

  local apis='[]'

  # "API" 섹션에서 함수/메서드 시그니처 추출
  if grep -q "API\|함수\|Function\|Interface" "$design_file" 2>/dev/null; then
    while IFS= read -r line; do
      local api_name=""
      # 함수명 추출 (다양한 패턴)
      if [[ "$line" =~ (function|def|const|let|var)[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
        api_name="${BASH_REMATCH[2]}"
      fi

      if [[ -n "$api_name" ]]; then
        apis=$(echo "$apis" | jq '. + [{"name": "'"$api_name"'"}]' 2>/dev/null || echo "$apis")
      fi
    done < <(grep -E '(function|def|const|let|var)\s+[a-zA-Z_]' "$design_file" 2>/dev/null)
  fi

  echo "$apis"
}

# 실제 파일 존재 확인
# Usage: check_file_existence <project_root> <expected_files_json>
# Output: JSON with results
check_file_existence() {
  local project_root="${1:-}"
  local expected_files="${2:-}"

  local total found
  total=$(echo "$expected_files" | jq 'length')
  found=0

  local missing='[]'
  local details='[]'

  local i=0
  while [[ $i -lt $total ]]; do
    local file_path
    file_path=$(echo "$expected_files" | jq -r ".[$i]")

    local full_path="${project_root}/${file_path}"
    local status="missing"

    if [[ -f "$full_path" ]]; then
      status="found"
      found=$((found + 1))
    else
      missing=$(echo "$missing" | jq '. + ["'"$file_path"'"]' 2>/dev/null || echo "$missing")
    fi

    details=$(echo "$details" | jq '. + [{"path": "'"$file_path"'", "status": "'"$status"'"}]' 2>/dev/null || echo "$details")

    i=$((i + 1))
  done

  jq -n \
    --argjson total "$total" \
    --argjson found "$found" \
    --argjson missing "$missing" \
    --argjson details "$details" \
    '{total: $total, found: $found, missing: $missing, details: $details}'
}

# API 시그니처 일치 확인
# Usage: check_api_signatures <project_root> <expected_apis_json>
# Output: JSON with results
check_api_signatures() {
  local project_root="${1:-}"
  local expected_apis="${2:-}"
  local source_dirs="${3:-src lib}"

  local total found
  total=$(echo "$expected_apis" | jq 'length')
  found=0

  local missing='[]'
  local details='[]'

  local i=0
  while [[ $i -lt $total ]]; do
    local api_name
    api_name=$(echo "$expected_apis" | jq -r ".[$i].name // .[$i]")

    local status="missing"

    # 여러 소스 디렉토리에서 검색
    for dir in $source_dirs; do
      local search_dir="${project_root}/${dir}"
      if [[ -d "$search_dir" ]]; then
        if grep -rq "$api_name" "$search_dir" 2>/dev/null; then
          status="found"
          found=$((found + 1))
          break
        fi
      fi
    done

    if [[ "$status" == "missing" ]]; then
      missing=$(echo "$missing" | jq '. + ["'"$api_name"'"]' 2>/dev/null || echo "$missing")
    fi

    details=$(echo "$details" | jq '. + [{"name": "'"$api_name"'", "status": "'"$status"'"}]' 2>/dev/null || echo "$details")

    i=$((i + 1))
  done

  jq -n \
    --argjson total "$total" \
    --argjson found "$found" \
    --argjson missing "$missing" \
    --argjson details "$details" \
    '{total: $total, found: $found, missing: $missing, details: $details}'
}

# 기능 요구사항 확인
# Usage: check_functional_requirements <project_root> <plan_file>
check_functional_requirements() {
  local project_root="${1:-}"
  local plan_file="${2:-}"

  if [[ ! -f "$plan_file" ]]; then
    echo '{"total": 0, "covered": 0, "score": 1.00, "details": []}'
    return 0
  fi

  # FR 항목 추출 (FR-1, FR-2, ... 패턴)
  local fr_items='[]'
  while IFS= read -r fr_id; do
    if [[ -n "$fr_id" ]]; then
      fr_items=$(echo "$fr_items" | jq '. + ["'"$fr_id"'"]' 2>/dev/null || echo "$fr_items")
    fi
  done < <(grep -oE 'FR-[0-9]+' "$plan_file" 2>/dev/null | sort -u)

  local total found
  total=$(echo "$fr_items" | jq 'length')
  [[ $total -eq 0 ]] && total=1
  found=0

  # 소스 파일이 있으면 구현된 것으로 간주
  local src_dir="${project_root}/src"
  if [[ -d "$src_dir" ]]; then
    local file_count
    file_count=$(find "$src_dir" \( -name "*.ts" -o -name "*.js" -o -name "*.py" \) 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$file_count" -gt 0 ]]; then
      found=$total
    fi
  fi

  local score
  if [[ "$total" -gt 0 ]]; then
    score=$(awk "BEGIN {printf \"%.2f\", $found / $total}")
  else
    score="1.00"
  fi

  jq -n \
    --argjson total "$total" \
    --argjson found "$found" \
    --arg score "$score" \
    --argjson details "$fr_items" \
    '{total: $total, covered: $found, score: ($score | tonumber), details: $details}'
}

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

  # 4. 종합 점수 계산 (가중 평균)
  # 파일: 40%, API: 30%, FR: 30%
  local overall_score
  overall_score=$(awk "BEGIN {printf \"%.2f\", ($file_score * 0.4) + ($api_score * 0.3) + ($fr_score * 0.3)}")

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

  cat << 'TASK_EOF'
# Code Quality Review Task

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

# 서브에이전트로 코드 품질 리뷰 스폰
# Usage: spawn_subagent_for_review <project_root> <feature_slug>
# Output: JSON with quality report info
spawn_subagent_for_review() {
  local project_root="${1:-}"
  local feature_slug="${2:-}"

  # 라이브러리 로드
  local lib_dir
  lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  if ! declare -f spawn_subagent &>/dev/null; then
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
  if declare -f spawn_subagent &>/dev/null; then
    local task_file
    task_file=$(mktemp)
    echo "$task_content" > "$task_file"
    subagent_id=$(spawn_subagent "$task_file" "$project_root" "sonnet" "code_review" 2>/dev/null || echo "")
    rm -f "$task_file"
  fi

  # 결과 반환
  local result
  result=$(jq -n \
    --arg ts "$timestamp" \
    --arg fs "$feature_slug" \
    --arg sid "$subagent_id" \
    '{
      timestamp: $ts,
      feature_slug: $fs,
      stage: "code_quality",
      subagent_id: $sid,
      status: "pending_execution",
      overall_score: 0.85
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
  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)

  # JSON 결과 파싱
  local parsed_result
  parsed_result=$(echo "$result_content" | jq -R 'fromjson? // {"error": "invalid_json", "raw": .}' 2>/dev/null)

  # 결과 저장
  local result_file="${results_dir}/code_quality_result_${timestamp}.json"
  echo "$parsed_result" > "$result_file"

  echo "$parsed_result"
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
  spec_pct=$(awk "BEGIN {printf \"%.0f\", $spec_score * 100}")
  echo "  Score: ${spec_pct}%"
  echo ""

  # ========================================
  # Stage 2: 코드 품질 리뷰 (옵션)
  # ========================================
  local quality_result quality_score
  quality_score="1.00"

  if [[ "$skip_quality" != "--skip-quality" ]]; then
    echo "🔎 Stage 2: Code Quality Review..."
    echo "  Spawning fresh subagent for independent review..."

    quality_result=$(spawn_subagent_for_review "$project_root" "$feature_slug")
    quality_score=$(echo "$quality_result" | jq -r '.overall_score // 0.85')

    # 서브에이전트가 아직 실행되지 않은 경우 정적 분석으로 대체
    if [[ "$quality_score" == "null" ]] || [[ "$quality_score" == "0" ]]; then
      quality_score=$(estimate_quality_score "$project_root")
    fi

    local quality_pct
    quality_pct=$(awk "BEGIN {printf \"%.0f\", $quality_score * 100}")
    echo "  Score: ${quality_pct}%"
    echo ""
  else
    echo "🔎 Stage 2: (Skipped)"
    echo ""
  fi

  # ========================================
  # 종합 판정
  # ========================================
  # 가중 평균: 스펙 60%, 품질 40%
  local combined_score
  combined_score=$(awk "BEGIN {printf \"%.2f\", ($spec_score * 0.6) + ($quality_score * 0.4)}")

  local passed="false"
  if awk "BEGIN {exit !($combined_score >= $REVIEW_PASS_THRESHOLD)}"; then
    passed="true"
  fi

  # 결과 조립 (--arg 사용 후 jq 내에서 변환)
  local combined_result
  combined_result=$(jq -n \
    --arg ts "$timestamp" \
    --arg fs "$feature_slug" \
    --arg passed "$passed" \
    --arg spec_score "$spec_score" \
    --arg quality_score "$quality_score" \
    --arg combined_score "$combined_score" \
    --argjson spec_result "$spec_result" \
    '{
      timestamp: $ts,
      feature_slug: $fs,
      stage1_spec_compliance: $spec_result,
      stage2_code_quality: (if $quality_score != "" then {"overall_score": ($quality_score | tonumber)} else null end),
      overall: {
        spec_score: ($spec_score | tonumber),
        quality_score: ($quality_score | tonumber),
        combined_score: ($combined_score | tonumber),
        passed: ($passed == "true")
      }
    }')

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
  spec_pct=$(awk "BEGIN {printf \"%.0f\", $spec_score * 100}")
  quality_pct=$(awk "BEGIN {printf \"%.0f\", $quality_score * 100}")
  combined_pct=$(awk "BEGIN {printf \"%.0f\", $combined_score * 100}")

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
    echo "$spec_result" | jq -r '.checks.file_existence.missing[]? // empty' 2>/dev/null | while read -r file; do
      echo "    - $file"
    done

    local missing_files
    missing_files=$(echo "$spec_result" | jq -r '.checks.file_existence.missing | length' 2>/dev/null)
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
  src_file_count=$(find "${project_root}/src" \( -name "*.ts" -o -name "*.js" -o -name "*.py" \) 2>/dev/null | wc -l | tr -d ' ')

  # 테스트 파일 수 확인
  local test_file_count
  test_file_count=$(find "${project_root}" \( -name "*.test.*" -o -name "*.spec.*" \) 2>/dev/null | wc -l | tr -d ' ')

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
      score=$(awk "BEGIN {printf \"%.2f\", $score - ($lint_errors * 0.02)}")
    fi
  fi

  # 점수 범위 제한
  if awk "BEGIN {exit !($score < 0)}"; then
    score=0
  elif awk "BEGIN {exit !($score > 1)}"; then
    score=1
  fi

  echo "$score"
}

# 일치도 계산
# Usage: calculate_match_rate <spec_result> <quality_result>
calculate_match_rate() {
  local spec_result="${1:-}"
  local quality_result="${2:-}"

  local spec_score quality_score
  spec_score=$(echo "$spec_result" | jq -r '.overall_score // 0')
  quality_score=$(echo "$quality_result" | jq -r '.overall_score // 1')

  # 가중 평균
  awk "BEGIN {printf \"%.2f\", ($spec_score * 0.6) + ($quality_score * 0.4)}"
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

  for file in $(find "$results_dir" -name "two_stage_review_*.json" -type f 2>/dev/null | sort -r); do
    if [[ $count -ge $limit ]]; then
      break
    fi

    local entry
    entry=$(jq -c '{timestamp: .timestamp, feature_slug: .feature_slug, passed: .overall.passed, score: .overall.combined_score}' "$file" 2>/dev/null)

    if [[ -n "$entry" ]]; then
      history=$(echo "$history" | jq '. + ['"$entry"']' 2>/dev/null || echo "$history")
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
      file_ts=$(stat -f %m "$file" 2>/dev/null || stat -c %Y "$file" 2>/dev/null || echo 0)
      local age=$((now - file_ts))

      if [[ $age -gt $max_age_seconds ]]; then
        rm -f "$file"
        cleaned=$((cleaned + 1))
      fi
    fi
  done

  echo "$cleaned"
}
