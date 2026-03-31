#!/usr/bin/env bash
# lsp-diagnostics.sh — LSP diagnostic parsing and reporting helpers

set -euo pipefail

: "${LSP_CACHE_DIR:=.harness/lsp-cache}"

lsp_file_mtime_epoch() {
  local file_path="${1:-}"

  if [[ "$OSTYPE" == "darwin"* ]]; then
    stat -f %m "$file_path" 2> /dev/null || echo 0
  else
    stat -c %Y "$file_path" 2> /dev/null || echo 0
  fi
}

lsp_cache_is_fresh() {
  local cache_file="${1:-}"
  local max_age_seconds="${2:-60}"

  if [[ ! -f "$cache_file" ]]; then
    return 1
  fi

  local modified_at now
  modified_at=$(lsp_file_mtime_epoch "$cache_file")
  now=$(date +%s)

  [[ $((now - modified_at)) -lt $max_age_seconds ]]
}

lsp_append_diagnostic() {
  local diagnostics_json="${1:-[]}"
  local line_num="${2:-0}"
  local column_num="${3:-0}"
  local message="${4:-}"
  local severity="${5:-1}"
  local source="${6:-lsp}"

  jq -n \
    --argjson diagnostics "$diagnostics_json" \
    --argjson line "$line_num" \
    --argjson col "$column_num" \
    --arg msg "$message" \
    --argjson severity "$severity" \
    --arg source "$source" \
    '$diagnostics + [{
      range: {
        start: {line: $line, character: $col},
        end: {line: $line, character: ($col + 1)}
      },
      severity: $severity,
      message: $msg,
      source: $source
    }]'
}

lsp_append_project_diagnostic() {
  local diagnostics_json="${1:-[]}"
  local file_path="${2:-}"
  local line_num="${3:-0}"
  local column_num="${4:-0}"
  local message="${5:-}"
  local severity="${6:-1}"

  jq -n \
    --argjson diagnostics "$diagnostics_json" \
    --arg file "$file_path" \
    --argjson line "$line_num" \
    --argjson col "$column_num" \
    --arg msg "$message" \
    --argjson severity "$severity" \
    '$diagnostics + [{
      file: $file,
      line: $line,
      column: $col,
      severity: $severity,
      message: $msg
    }]'
}

lsp_typescript_diagnostics() {
  local file_path="${1:-}"
  local project_root="${2:-}"

  if [[ ! -f "${project_root}/tsconfig.json" ]]; then
    echo '[]'
    return 0
  fi

  local result
  result=$({
    cd "$project_root" || exit 1
    npx tsc --noEmit --pretty false 2>&1
  } || true)

  local diagnostics="[]"
  local line file line_num col message
  while IFS= read -r line; do
    if [[ "$line" =~ ^(.+)\(([0-9]+),([0-9]+)\):\ error\ (.+)$ ]]; then
      file="${BASH_REMATCH[1]}"
      line_num=$((BASH_REMATCH[2]))
      col=$((BASH_REMATCH[3]))
      message="${BASH_REMATCH[4]}"

      if [[ "$file" == "$file_path" ]] || [[ "$file" == *"$(basename "$file_path")"* ]]; then
        diagnostics=$(lsp_append_diagnostic "$diagnostics" "$line_num" "$col" "$message" 1 "typescript")
      fi
    fi
  done <<< "$result"

  echo "$diagnostics"
}

lsp_python_diagnostics() {
  local file_path="${1:-}"
  local project_root="${2:-}"

  local diagnostics="[]"

  if command -v mypy > /dev/null 2>&1; then
    local result
    result=$({
      cd "$project_root" || exit 1
      mypy --output json "$file_path" 2> /dev/null
    } || true)

    if [[ -n "$result" ]]; then
      local item severity
      while IFS= read -r item; do
        severity=3
        if echo "$item" | jq -e '.error' > /dev/null 2>&1; then
          severity=1
        fi

        diagnostics=$(lsp_append_diagnostic \
          "$diagnostics" \
          "$(echo "$item" | jq -r '.line | tonumber')" \
          "$(echo "$item" | jq -r '.column | tonumber')" \
          "$(echo "$item" | jq -r '.message')" \
          "$severity" \
          "mypy")
      done <<< "$(echo "$result" | jq -c '.[]' 2> /dev/null || true)"
    fi
  fi

  echo "$diagnostics"
}

lsp_go_diagnostics() {
  local file_path="${1:-}"
  local project_root="${2:-}"

  local diagnostics="[]"

  if command -v go > /dev/null 2>&1; then
    local result line file line_num col message
    result=$({
      cd "$project_root" || exit 1
      go vet ./... 2>&1
    } || true)

    while IFS= read -r line; do
      if [[ "$line" =~ ^(.+):([0-9]+):([0-9]+):\ (.+)$ ]]; then
        file="${BASH_REMATCH[1]}"
        line_num=$((BASH_REMATCH[2]))
        col=$((BASH_REMATCH[3]))
        message="${BASH_REMATCH[4]}"

        if [[ "$file" == "$file_path" ]] || [[ "$file" == *"$(basename "$file_path")"* ]]; then
          diagnostics=$(lsp_append_diagnostic "$diagnostics" "$line_num" "$col" "$message" 2 "go vet")
        fi
      fi
    done <<< "$result"
  fi

  echo "$diagnostics"
}

lsp_rust_diagnostics() {
  local file_path="${1:-}"
  local project_root="${2:-}"

  local diagnostics="[]"

  if command -v cargo > /dev/null 2>&1; then
    local result line message severity spans line_num col span_file
    result=$({
      cd "$project_root" || exit 1
      cargo check --message-format=json 2>&1
    } || true)

    while IFS= read -r line; do
      if echo "$line" | jq -e '.reason == "compiler-message"' > /dev/null 2>&1; then
        message=$(echo "$line" | jq -r '.message.rendered')
        severity=2
        if echo "$line" | jq -e '.message.level == "error"' > /dev/null 2>&1; then
          severity=1
        fi

        spans=$(echo "$line" | jq -c '.message.spans[0] // empty')
        if [[ "$spans" != "null" ]] && [[ -n "$spans" ]]; then
          span_file=$(echo "$spans" | jq -r '.file_name // ""')
          if [[ "$span_file" == "$file_path" ]] || [[ "$span_file" == *"$(basename "$file_path")"* ]]; then
            line_num=$(echo "$spans" | jq -r '.line_start')
            col=$(echo "$spans" | jq -r '.column_start')
            diagnostics=$(lsp_append_diagnostic "$diagnostics" "$line_num" "$col" "$message" "$severity" "rustc")
          fi
        fi
      fi
    done <<< "$result"
  fi

  echo "$diagnostics"
}

lsp_collect_project_diagnostics() {
  local project_root="${1:-$(pwd)}"

  local language
  language=$(detect_project_language "$project_root")

  local all_diagnostics="[]"

  case "$language" in
    typescript | javascript)
      local result line file line_num col severity_word message severity
      result=$({
        cd "$project_root" || exit 1
        npx tsc --noEmit --pretty false 2>&1
      } || true)

      while IFS= read -r line; do
        if [[ "$line" =~ ^(.+)\(([0-9]+),([0-9]+)\):\ (error|warning)\ (.+)$ ]]; then
          file="${BASH_REMATCH[1]}"
          line_num=$((BASH_REMATCH[2]))
          col=$((BASH_REMATCH[3]))
          severity_word="${BASH_REMATCH[4]}"
          message="${BASH_REMATCH[5]}"
          severity=3
          [[ "$severity_word" == "error" ]] && severity=1
          [[ "$severity_word" == "warning" ]] && severity=2

          all_diagnostics=$(lsp_append_project_diagnostic "$all_diagnostics" "$file" "$line_num" "$col" "$message" "$severity")
        fi
      done <<< "$result"
      ;;
    python)
      if command -v mypy > /dev/null 2>&1; then
        local result item file line_num col message severity_word severity
        result=$({
          cd "$project_root" || exit 1
          mypy --output json . 2> /dev/null
        } || true)

        while IFS= read -r item; do
          file=$(echo "$item" | jq -r '.file')
          line_num=$(echo "$item" | jq -r '.line')
          col=$(echo "$item" | jq -r '.column // 0')
          message=$(echo "$item" | jq -r '.message')
          severity_word=$(echo "$item" | jq -r '.severity // "note"')
          severity=3
          [[ "$severity_word" == "error" ]] && severity=1

          all_diagnostics=$(lsp_append_project_diagnostic "$all_diagnostics" "$file" "$line_num" "$col" "$message" "$severity")
        done <<< "$(echo "$result" | jq -c '.[]' 2> /dev/null || true)"
      fi
      ;;
    go)
      local result line
      result=$({
        cd "$project_root" || exit 1
        go vet ./... 2>&1
      } || true)

      while IFS= read -r line; do
        if [[ "$line" =~ ^(.+):([0-9]+):([0-9]+):\ (.+)$ ]]; then
          all_diagnostics=$(lsp_append_project_diagnostic \
            "$all_diagnostics" \
            "${BASH_REMATCH[1]}" \
            "$((BASH_REMATCH[2]))" \
            "$((BASH_REMATCH[3]))" \
            "${BASH_REMATCH[4]}" \
            2)
        fi
      done <<< "$result"
      ;;
    rust)
      local result line message spans file line_num col severity
      result=$({
        cd "$project_root" || exit 1
        cargo check --message-format=json 2>&1
      } || true)

      while IFS= read -r line; do
        if echo "$line" | jq -e '.reason == "compiler-message"' > /dev/null 2>&1; then
          message=$(echo "$line" | jq -r '.message.rendered')
          spans=$(echo "$line" | jq -c '.message.spans[0] // empty')

          if [[ "$spans" != "null" ]]; then
            file=$(echo "$spans" | jq -r '.file_name')
            line_num=$(echo "$spans" | jq -r '.line_start')
            col=$(echo "$spans" | jq -r '.column_start')
            severity=1
            all_diagnostics=$(lsp_append_project_diagnostic "$all_diagnostics" "$file" "$line_num" "$col" "$message" "$severity")
          fi
        fi
      done <<< "$result"
      ;;
  esac

  local error_count warning_count
  error_count=$(echo "$all_diagnostics" | jq '[.[] | select(.severity == 1)] | length')
  warning_count=$(echo "$all_diagnostics" | jq '[.[] | select(.severity == 2)] | length')

  echo "$all_diagnostics" | jq --argjson errors "$error_count" --argjson warnings "$warning_count" \
    '{"diagnostics": ., "summary": {"errors": $errors, "warnings": $warnings}}'
}

lsp_project_has_errors() {
  local project_root="${1:-$(pwd)}"
  local result
  result=$(lsp_collect_project_diagnostics "$project_root")

  local error_count
  error_count=$(echo "$result" | jq '.summary.errors')

  [[ "$error_count" -gt 0 ]]
}

lsp_render_diagnostic_report() {
  local project_root="${1:-$(pwd)}"
  local result
  result=$(lsp_collect_project_diagnostics "$project_root")

  local errors warnings
  errors=$(echo "$result" | jq '.summary.errors')
  warnings=$(echo "$result" | jq '.summary.warnings')

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "LSP Diagnostic Report"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "Errors: $errors"
  echo "Warnings: $warnings"
  echo ""

  if [[ "$errors" -gt 0 ]]; then
    echo "❌ Errors:"
    echo "$result" | jq -r '.diagnostics[] | select(.severity == 1) | "  \(.file):\(.line): \(.message)"'
    echo ""
  fi

  if [[ "$warnings" -gt 0 ]]; then
    echo "⚠️  Warnings:"
    echo "$result" | jq -r '.diagnostics[] | select(.severity == 2) | "  \(.file):\(.line): \(.message)"'
    echo ""
  fi

  if [[ "$errors" -eq 0 ]] && [[ "$warnings" -eq 0 ]]; then
    echo "✅ No issues found"
  fi

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}
