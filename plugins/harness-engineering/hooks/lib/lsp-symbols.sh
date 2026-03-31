#!/usr/bin/env bash
# lsp-symbols.sh — LSP symbol and location formatting helpers

set -euo pipefail

lsp_append_symbol() {
  local symbols_json="${1:-[]}"
  local name="${2:-}"
  local kind="${3:-}"
  local line_num="${4:-0}"

  jq -n \
    --argjson symbols "$symbols_json" \
    --arg name "$name" \
    --arg kind "$kind" \
    --argjson line "$line_num" \
    '$symbols + [{
      name: $name,
      kind: $kind,
      range: {start: {line: $line, character: 0}}
    }]'
}

lsp_append_location() {
  local locations_json="${1:-[]}"
  local uri="${2:-}"
  local line_num="${3:-0}"

  jq -n \
    --argjson locations "$locations_json" \
    --arg uri "$uri" \
    --argjson line "$line_num" \
    '$locations + [{
      uri: $uri,
      range: {
        start: {line: $line, character: 0},
        end: {line: $line, character: 10}
      }
    }]'
}

lsp_append_workspace_edit() {
  local changes_json="${1:-{}}"
  local uri="${2:-}"
  local line_num="${3:-0}"
  local new_name="${4:-}"

  jq -n \
    --argjson changes "$changes_json" \
    --arg uri "$uri" \
    --argjson line "$line_num" \
    --arg new_name "$new_name" \
    '
    ($changes[$uri] // []) as $existing |
    $changes + {
      ($uri): ($existing + [{
        range: {
          start: {line: $line, character: 0},
          end: {line: $line, character: 10}
        },
        newText: $new_name
      }])
    }'
}

lsp_extract_symbol_zero_based_line() {
  local file_path="${1:-}"
  local line_num="${2:-0}"

  sed -n "$((line_num + 1))p" "$file_path" | grep -o '[A-Za-z_][A-Za-z0-9_]*' | head -1
}

lsp_js_ts_symbols() {
  local file_path="${1:-}"
  local symbols="[]"
  local line_num=0
  local line name kind

  while IFS= read -r line; do
    name=""
    kind=""

    if [[ "$line" =~ (class|interface|type)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*) ]]; then
      name="${BASH_REMATCH[2]}"
      kind="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ (function|const|let|var)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*= ]]; then
      name="${BASH_REMATCH[2]}"
      kind="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ function[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*\(|function[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*\< ]]; then
      name="${BASH_REMATCH[1]}"
      kind="function"
    fi

    if [[ -n "$name" ]]; then
      symbols=$(lsp_append_symbol "$symbols" "$name" "$kind" "$line_num")
    fi

    line_num=$((line_num + 1))
  done < "$file_path"

  echo "$symbols"
}

lsp_python_symbols() {
  local file_path="${1:-}"
  local symbols="[]"
  local line_num=0
  local line name kind

  while IFS= read -r line; do
    name=""
    kind=""

    if [[ "$line" =~ ^[[:space:]]*class[[:space:]]+([A-Za-z_][A-Za-z0-9_]*) ]]; then
      name="${BASH_REMATCH[1]}"
      kind="class"
    elif [[ "$line" =~ ^[[:space:]]*async[[:space:]]+def[[:space:]]+([a-z_][a-z0-9_]*) ]]; then
      name="${BASH_REMATCH[1]}"
      kind="function"
    elif [[ "$line" =~ ^[[:space:]]*def[[:space:]]+([a-z_][a-z0-9_]*) ]]; then
      name="${BASH_REMATCH[1]}"
      kind="function"
    fi

    if [[ -n "$name" ]]; then
      symbols=$(lsp_append_symbol "$symbols" "$name" "$kind" "$line_num")
    fi

    line_num=$((line_num + 1))
  done < "$file_path"

  echo "$symbols"
}

lsp_go_symbols() {
  local file_path="${1:-}"
  local symbols="[]"
  local line_num=0
  local line name kind

  while IFS= read -r line; do
    name=""
    kind=""

    if [[ "$line" =~ ^(type|struct|interface)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*) ]]; then
      name="${BASH_REMATCH[2]}"
      kind="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^func[[:space:]]+\(?[A-Za-z_*]+\)?[[:space:]]*([A-Za-z_][A-Za-z0-9_]*) ]]; then
      name="${BASH_REMATCH[1]}"
      kind="function"
    fi

    if [[ -n "$name" ]]; then
      symbols=$(lsp_append_symbol "$symbols" "$name" "$kind" "$line_num")
    fi

    line_num=$((line_num + 1))
  done < "$file_path"

  echo "$symbols"
}

lsp_rust_symbols() {
  local file_path="${1:-}"
  local symbols="[]"
  local line_num=0
  local line name kind

  while IFS= read -r line; do
    name=""
    kind=""

    if [[ "$line" =~ ^(struct|enum|trait|type)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*) ]]; then
      name="${BASH_REMATCH[2]}"
      kind="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^(pub[[:space:]]+)?fn[[:space:]]+([a-z_][a-z0-9_]*) ]]; then
      name="${BASH_REMATCH[2]}"
      kind="function"
    fi

    if [[ -n "$name" ]]; then
      symbols=$(lsp_append_symbol "$symbols" "$name" "$kind" "$line_num")
    fi

    line_num=$((line_num + 1))
  done < "$file_path"

  echo "$symbols"
}
