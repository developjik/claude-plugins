#!/usr/bin/env bash
# review-evidence.sh — review-engine Stage 1 evidence collection helpers

set -euo pipefail

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
  if grep -q "파일 변경\|File Changes\|## Files" "$design_file" 2> /dev/null; then
    while IFS= read -r line; do
      # 파일 경로 추출 (backtick 제거)
      local file_path
      file_path=$(echo "$line" | sed -E 's/^[[:space:]]*-[[:space:]]*`?([^`[:space:]]+)`?.*/\1/')

      # 유효한 경로인지 확인 (확장자가 있는 파일)
      if [[ "$file_path" =~ \.[a-zA-Z0-9]+$ ]] && [[ ! "$file_path" =~ ^# ]]; then
        if [[ -n "$file_path" ]] && [[ "$file_path" != "$line" ]]; then
          files=$(jq -n --argjson current "$files" --arg file_path "$file_path" '$current + [$file_path]' 2> /dev/null || echo "$files")
        fi
      fi
    done < <(grep -A 50 "파일 변경\|File Changes\|## Files" "$design_file" 2> /dev/null | grep -E '^\s*-\s*')
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
  if grep -q "API\|함수\|Function\|Interface" "$design_file" 2> /dev/null; then
    while IFS= read -r line; do
      local api_name=""
      # 함수명 추출 (다양한 패턴)
      if [[ "$line" =~ (function|def|const|let|var)[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
        api_name="${BASH_REMATCH[2]}"
      fi

      if [[ -n "$api_name" ]]; then
        apis=$(jq -n \
          --argjson current "$apis" \
          --arg api_name "$api_name" \
          '$current + [{name: $api_name}]' 2> /dev/null || echo "$apis")
      fi
    done < <(grep -E '(function|def|const|let|var)\s+[a-zA-Z_]' "$design_file" 2> /dev/null)
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
      missing=$(jq -n --argjson current "$missing" --arg file_path "$file_path" '$current + [$file_path]' 2> /dev/null || echo "$missing")
    fi

    details=$(jq -n \
      --argjson current "$details" \
      --arg file_path "$file_path" \
      --arg status "$status" \
      '$current + [{path: $file_path, status: $status}]' 2> /dev/null || echo "$details")

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
    api_name=$(echo "$expected_apis" | jq -r "if .[$i] | type == \"object\" then .[$i].name else .[$i] end")

    local status="missing"

    # 여러 소스 디렉토리에서 검색
    for dir in $source_dirs; do
      local search_dir="${project_root}/${dir}"
      if [[ -d "$search_dir" ]]; then
        if grep -rq "$api_name" "$search_dir" 2> /dev/null; then
          status="found"
          found=$((found + 1))
          break
        fi
      fi
    done

    if [[ "$status" == "missing" ]]; then
      missing=$(jq -n --argjson current "$missing" --arg api_name "$api_name" '$current + [$api_name]' 2> /dev/null || echo "$missing")
    fi

    details=$(jq -n \
      --argjson current "$details" \
      --arg api_name "$api_name" \
      --arg status "$status" \
      '$current + [{name: $api_name, status: $status}]' 2> /dev/null || echo "$details")

    i=$((i + 1))
  done

  jq -n \
    --argjson total "$total" \
    --argjson found "$found" \
    --argjson missing "$missing" \
    --argjson details "$details" \
    '{total: $total, found: $found, missing: $missing, details: $details}'
}

# JSON 배열 헬퍼
lines_to_json_array() {
  jq -R . 2> /dev/null | jq -s 'map(select(length > 0)) | unique' 2> /dev/null || echo '[]'
}

merge_unique_json_arrays() {
  local merged='[]'
  local array_json

  for array_json in "$@"; do
    merged=$(jq -n \
      --argjson current "$merged" \
      --argjson incoming "${array_json:-[]}" \
      '$current + $incoming | map(select(. != null and . != "")) | unique' 2> /dev/null || echo "$merged")
  done

  echo "$merged"
}

append_requirement_item() {
  local items_json="${1:-[]}"
  local requirement_id="${2:-}"
  local title="${3:-}"
  local body="${4:-}"

  [[ -n "$requirement_id" ]] || {
    echo "$items_json"
    return 0
  }

  jq -n \
    --argjson items "$items_json" \
    --arg requirement_id "$requirement_id" \
    --arg title "$title" \
    --arg body "$body" \
    '$items + [{
      id: $requirement_id,
      title: $title,
      text: $body
    }]' 2> /dev/null || echo "$items_json"
}

extract_requirement_items() {
  local plan_file="${1:-}"

  if [[ ! -f "$plan_file" ]]; then
    echo '[]'
    return 1
  fi

  local fr_section
  fr_section=$(awk '
    /^###[[:space:]]*기능 요구사항/ || /^##[[:space:]]*기능 요구사항/ {in_section=1; next}
    /^###[[:space:]]*비기능 요구사항/ || /^##[[:space:]]*비기능 요구사항/ {in_section=0}
    in_section {print}
  ' "$plan_file" 2> /dev/null)

  [[ -n "$fr_section" ]] || {
    echo '[]'
    return 0
  }

  local mode="heading"
  if printf '%s\n' "$fr_section" | grep -qE '^- \[[ xX]\][[:space:]]*FR-[0-9]'; then
    mode="checklist"
  fi

  local items='[]'
  local current_id=""
  local current_title=""
  local current_body=""
  local line=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$mode" == "checklist" ]] && [[ "$line" =~ ^-[[:space:]]*\[[[:space:]xX]\][[:space:]]*(FR-[0-9]+(\.[0-9]+)?):[[:space:]]*(.+)$ ]]; then
      items=$(append_requirement_item "$items" "$current_id" "$current_title" "$current_body")
      current_id="${BASH_REMATCH[1]}"
      current_title="${BASH_REMATCH[3]}"
      current_body="$line"
      continue
    fi

    if [[ "$mode" == "heading" ]] && [[ "$line" =~ ^####[[:space:]]*(FR-[0-9]+):[[:space:]]*(.+)$ ]]; then
      items=$(append_requirement_item "$items" "$current_id" "$current_title" "$current_body")
      current_id="${BASH_REMATCH[1]}"
      current_title="${BASH_REMATCH[2]}"
      current_body="$line"
      continue
    fi

    if [[ -n "$current_id" ]]; then
      current_body+=$'\n'"$line"
    fi
  done <<< "$fr_section"

  append_requirement_item "$items" "$current_id" "$current_title" "$current_body"
}

extract_file_references_from_text() {
  local text="${1:-}"

  printf '%s\n' "$text" | perl -ne '
    while(/((?:\.?[\w-]+\/)+(?:[\w.-]+))/g) {
      next if $1 =~ /^https?:/;
      print "$1\n";
    }
  ' | lines_to_json_array
}

extract_symbol_references_from_text() {
  local text="${1:-}"

  printf '%s\n' "$text" | perl -ne '
    while(/([A-Za-z_][A-Za-z0-9_]*)\s*\(/g) {
      next if $1 =~ /^(if|for|while|case|echo|return|local|function|then)$/;
      print "$1\n";
    }
  ' | lines_to_json_array
}

extract_config_references_from_text() {
  local text="${1:-}"

  printf '%s\n' "$text" | perl -ne '
    while(/\b([A-Za-z][A-Za-z0-9_-]*(?:\.[A-Za-z0-9_-]+)+)\b/g) {
      next if $1 =~ /^(?:FR|NFR)-/i;
      next if $1 =~ /\.(?:sh|bash|ts|tsx|js|jsx|py|go|rs|java|rb|json|yaml|yml|toml|md)$/;
      print "$1\n";
    }
  ' | lines_to_json_array
}

extract_requirement_keywords() {
  local text="${1:-}"

  printf '%s\n' "$text" | perl -ne '
    while(/\b([A-Za-z][A-Za-z0-9_-]{2,})\b/g) {
      my $term = lc($1);
      next if $term =~ /^(?:fr|nfr)-[0-9]+/;
      next if $term =~ /^(and|the|with|from|that|this|then|than|user|users|can|should|must|for|not|none|into|able|all|each|will|when|where|have|has)$/;
      print "$term\n";
    }
  ' | lines_to_json_array
}

derive_file_search_terms() {
  local file_refs="${1:-[]}"
  local terms='[]'
  local total
  total=$(echo "$file_refs" | jq 'length')

  local i=0
  while [[ $i -lt $total ]]; do
    local file_path basename stem
    file_path=$(echo "$file_refs" | jq -r ".[$i]")
    basename=$(basename "$file_path" 2> /dev/null || echo "")
    stem="${basename%.*}"

    if [[ -n "$basename" ]]; then
      terms=$(jq -n --argjson current "$terms" --arg basename "$basename" '$current + [$basename]' 2> /dev/null || echo "$terms")
    fi

    if [[ -n "$stem" ]] && [[ "${#stem}" -ge 3 ]]; then
      terms=$(jq -n --argjson current "$terms" --arg stem "$stem" '$current + [$stem]' 2> /dev/null || echo "$terms")
    fi

    i=$((i + 1))
  done

  echo "$terms" | jq 'map(select(length > 0)) | unique' 2> /dev/null || echo '[]'
}

search_scope_for_string() {
  local project_root="${1:-}"
  local scope="${2:-implementation}"
  local term="${3:-}"

  [[ -n "$term" ]] || return 0

  if command -v rg > /dev/null 2>&1; then
    if [[ "$scope" == "tests" ]]; then
      rg -l -F --hidden \
        -g 'tests/**' \
        -g '**/__tests__/**' \
        -g '**/*.test.*' \
        -g '**/*.spec.*' \
        -- "$term" "$project_root" 2> /dev/null || true
    else
      rg -l -F --hidden \
        -g '!docs/**' \
        -g '!.harness/review/**' \
        -g '!tests/**' \
        -g '!**/__tests__/**' \
        -g '!**/*.test.*' \
        -g '!**/*.spec.*' \
        -g '!**/*.md' \
        -- "$term" "$project_root" 2> /dev/null || true
    fi
    return 0
  fi

  local candidate_file
  if [[ "$scope" == "tests" ]]; then
    while IFS= read -r candidate_file; do
      grep -FIl -- "$term" "$candidate_file" 2> /dev/null || true
    done < <(
      find "$project_root" -type f \
        \( -path '*/tests/*' -o -path '*/__tests__/*' -o -name '*.test.*' -o -name '*.spec.*' \) \
        2> /dev/null
    )
  else
    while IFS= read -r candidate_file; do
      grep -FIl -- "$term" "$candidate_file" 2> /dev/null || true
    done < <(
      find "$project_root" \
        \( -path "$project_root/docs" -o -path "$project_root/.git" -o -path "$project_root/.harness/review" -o -path '*/tests' -o -path '*/__tests__' \) -prune -o \
        -type f ! -name '*.md' ! -name '*.test.*' ! -name '*.spec.*' -print 2> /dev/null
    )
  fi
}

search_terms_in_scope() {
  local project_root="${1:-}"
  local scope="${2:-implementation}"
  local terms_json="${3:-[]}"

  local matched_terms='[]'
  local matched_files='[]'
  local total
  total=$(echo "$terms_json" | jq 'length')

  local i=0
  while [[ $i -lt $total ]]; do
    local term
    term=$(echo "$terms_json" | jq -r ".[$i]")

    if [[ -z "$term" ]]; then
      i=$((i + 1))
      continue
    fi

    local search_results
    search_results=$(search_scope_for_string "$project_root" "$scope" "$term")

    if [[ -n "$search_results" ]]; then
      matched_terms=$(jq -n --argjson current "$matched_terms" --arg term "$term" '$current + [$term]' 2> /dev/null || echo "$matched_terms")

      while IFS= read -r matched_file; do
        [[ -n "$matched_file" ]] || continue
        matched_file="${matched_file#"${project_root}"/}"
        matched_files=$(jq -n --argjson current "$matched_files" --arg matched_file "$matched_file" '$current + [$matched_file]' 2> /dev/null || echo "$matched_files")
      done <<< "$search_results"
    fi

    i=$((i + 1))
  done

  jq -n \
    --argjson matched_terms "$matched_terms" \
    --argjson matched_files "$matched_files" \
    '{
      matched_terms: ($matched_terms | unique),
      matched_files: ($matched_files | unique)
    }'
}

check_config_references() {
  local project_root="${1:-}"
  local config_refs="${2:-[]}"

  local total found
  total=$(echo "$config_refs" | jq 'length')
  found=0

  local missing='[]'
  local details='[]'

  local i=0
  while [[ $i -lt $total ]]; do
    local ref status matched_files
    ref=$(echo "$config_refs" | jq -r ".[$i]")
    status="missing"
    matched_files='[]'

    local search_results
    search_results=$(search_scope_for_string "$project_root" "implementation" "$ref")

    if [[ -n "$search_results" ]]; then
      status="found"
      found=$((found + 1))
      while IFS= read -r matched_file; do
        [[ -n "$matched_file" ]] || continue
        matched_file="${matched_file#"${project_root}"/}"
        matched_files=$(jq -n --argjson current "$matched_files" --arg matched_file "$matched_file" '$current + [$matched_file]' 2> /dev/null || echo "$matched_files")
      done <<< "$search_results"
    else
      missing=$(jq -n --argjson current "$missing" --arg ref "$ref" '$current + [$ref]' 2> /dev/null || echo "$missing")
    fi

    details=$(jq -n \
      --argjson current "$details" \
      --arg ref "$ref" \
      --arg status "$status" \
      --argjson matched_files "$matched_files" \
      '$current + [{
        reference: $ref,
        status: $status,
        matched_files: ($matched_files | unique)
      }]' 2> /dev/null || echo "$details")

    i=$((i + 1))
  done

  jq -n \
    --argjson total "$total" \
    --argjson found "$found" \
    --argjson missing "$missing" \
    --argjson details "$details" \
    '{total: $total, found: $found, missing: $missing, details: $details}'
}

evaluate_requirement_match() {
  local project_root="${1:-}"
  local requirement_json="${2:-}"

  if [[ -z "$requirement_json" ]]; then
    requirement_json='{}'
  fi

  local requirement_id title requirement_text
  requirement_id=$(echo "$requirement_json" | jq -r '.id // ""')
  title=$(echo "$requirement_json" | jq -r '.title // ""')
  requirement_text=$(echo "$requirement_json" | jq -r '.text // ""')

  local file_refs symbol_refs config_refs keywords file_terms
  file_refs=$(extract_file_references_from_text "$requirement_text")
  symbol_refs=$(extract_symbol_references_from_text "$requirement_text")
  config_refs=$(extract_config_references_from_text "$requirement_text")
  keywords=$(extract_requirement_keywords "$title"$'\n'"$requirement_text")
  file_terms=$(derive_file_search_terms "$file_refs")

  local file_check api_check config_check
  file_check=$(check_file_existence "$project_root" "$file_refs")
  api_check=$(check_api_signatures "$project_root" "$symbol_refs" "src lib hooks scripts")
  config_check=$(check_config_references "$project_root" "$config_refs")

  local implementation_terms test_terms
  implementation_terms=$(merge_unique_json_arrays "$symbol_refs" "$config_refs" "$keywords" "$file_terms")
  test_terms="$implementation_terms"

  local code_evidence test_evidence
  code_evidence=$(search_terms_in_scope "$project_root" "implementation" "$implementation_terms")
  test_evidence=$(search_terms_in_scope "$project_root" "tests" "$test_terms")

  local file_total file_found api_total api_found config_total config_found explicit_total explicit_found
  file_total=$(echo "$file_check" | jq -r '.total // 0')
  file_found=$(echo "$file_check" | jq -r '.found // 0')
  api_total=$(echo "$api_check" | jq -r '.total // 0')
  api_found=$(echo "$api_check" | jq -r '.found // 0')
  config_total=$(echo "$config_check" | jq -r '.total // 0')
  config_found=$(echo "$config_check" | jq -r '.found // 0')

  explicit_total=$((file_total + api_total + config_total))
  explicit_found=$((file_found + api_found + config_found))

  local implementation_hits test_hits
  implementation_hits=$(echo "$code_evidence" | jq -r '(.matched_terms | length) + (.matched_files | length)')
  test_hits=$(echo "$test_evidence" | jq -r '(.matched_terms | length) + (.matched_files | length)')

  local explicit_score implementation_score test_score requirement_score status
  if [[ "$explicit_total" -gt 0 ]]; then
    explicit_score=$(awk -v found="$explicit_found" -v total="$explicit_total" 'BEGIN {printf "%.2f", found / total}')
    implementation_score="$explicit_score"
    if [[ "$implementation_hits" -gt 0 ]] && awk -v score="$implementation_score" 'BEGIN {exit !(score < 0.50)}'; then
      implementation_score="0.50"
    fi
  else
    if [[ "$implementation_hits" -gt 0 ]]; then
      implementation_score="0.60"
    else
      implementation_score="0.00"
    fi
  fi

  if [[ "$test_hits" -gt 0 ]]; then
    test_score="1.00"
  else
    test_score="0.00"
  fi

  requirement_score=$(awk -v impl="$implementation_score" -v test="$test_score" 'BEGIN {printf "%.2f", (impl * 0.8) + (test * 0.2)}')

  status="missing"
  if awk -v score="$requirement_score" 'BEGIN {exit !(score >= 0.85)}'; then
    status="complete"
  elif awk -v score="$requirement_score" 'BEGIN {exit !(score >= 0.35)}'; then
    status="partial"
  fi

  jq -n \
    --arg requirement_id "$requirement_id" \
    --arg title "$title" \
    --arg status "$status" \
    --arg requirement_score "$requirement_score" \
    --arg implementation_score "$implementation_score" \
    --arg test_score "$test_score" \
    --argjson file_refs "$file_refs" \
    --argjson symbol_refs "$symbol_refs" \
    --argjson config_refs "$config_refs" \
    --argjson keywords "$keywords" \
    --argjson file_check "$file_check" \
    --argjson api_check "$api_check" \
    --argjson config_check "$config_check" \
    --argjson code_evidence "$code_evidence" \
    --argjson test_evidence "$test_evidence" \
    '{
      id: $requirement_id,
      title: $title,
      status: $status,
      score: ($requirement_score | tonumber),
      evidence: {
        implementation_score: ($implementation_score | tonumber),
        test_score: ($test_score | tonumber),
        file_references: $file_refs,
        symbol_references: $symbol_refs,
        config_references: $config_refs,
        keywords: $keywords,
        file_check: $file_check,
        api_check: $api_check,
        config_check: $config_check,
        implementation_matches: $code_evidence,
        test_matches: $test_evidence
      }
    }'
}

# 기능 요구사항 확인
# Usage: check_functional_requirements <project_root> <plan_file>
check_functional_requirements() {
  local project_root="${1:-}"
  local plan_file="${2:-}"

  if [[ ! -f "$plan_file" ]]; then
    echo '{"total": 0, "covered": 0, "complete": 0, "partial": 0, "missing": 0, "score": 1.00, "details": []}'
    return 0
  fi

  local fr_items
  fr_items=$(extract_requirement_items "$plan_file")

  local total
  total=$(echo "$fr_items" | jq 'length')

  if [[ "$total" -eq 0 ]]; then
    echo '{"total": 0, "covered": 0, "complete": 0, "partial": 0, "missing": 0, "score": 1.00, "details": []}'
    return 0
  fi

  local details='[]'
  local complete=0
  local partial=0
  local missing=0
  local score_sum="0.00"

  local i=0
  while [[ $i -lt $total ]]; do
    local requirement_json result status item_score
    requirement_json=$(echo "$fr_items" | jq -c ".[$i]")
    result=$(evaluate_requirement_match "$project_root" "$requirement_json")
    status=$(echo "$result" | jq -r '.status // "missing"')
    item_score=$(echo "$result" | jq -r '.score // 0')

    case "$status" in
      complete)
        complete=$((complete + 1))
        ;;
      partial)
        partial=$((partial + 1))
        ;;
      *)
        missing=$((missing + 1))
        ;;
    esac

    score_sum=$(awk -v current="$score_sum" -v add="$item_score" 'BEGIN {printf "%.2f", current + add}')
    details=$(jq -n \
      --argjson current "$details" \
      --argjson item "$result" \
      '$current + [$item]' 2> /dev/null || echo "$details")

    i=$((i + 1))
  done

  local score covered
  score=$(awk -v total="$total" -v sum="$score_sum" 'BEGIN {printf "%.2f", sum / total}')
  covered=$((complete + partial))

  jq -n \
    --argjson total "$total" \
    --argjson covered "$covered" \
    --argjson complete "$complete" \
    --argjson partial "$partial" \
    --argjson missing "$missing" \
    --arg score "$score" \
    --argjson details "$details" \
    '{
      total: $total,
      covered: $covered,
      complete: $complete,
      partial: $partial,
      missing: $missing,
      score: ($score | tonumber),
      details: $details
    }'
}
