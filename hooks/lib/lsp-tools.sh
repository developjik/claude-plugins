#!/usr/bin/env bash
# lsp-tools.sh — LSP (Language Server Protocol) Integration
# P1-5: 코드 분석/리팩토링 정밀도 향상
#
# DEPENDENCIES: json-utils.sh, logging.sh
#
# Reference: oh-my-openagent LSP Tools
#
# 지원 언어 서버:
# - TypeScript: typescript-language-server
# - Python: pylsp (python-lsp-server)
# - Go: gopls
# - Rust: rust-analyzer
# - Java: jdtls
# - C/C++: clangd
#
# 사용 전제:
# - 언어 서버가 설치되어 있어야 함
# - 프로젝트가 LSP 지원 에디터/IDE 설정되어 있어야 함

set -euo pipefail

# ============================================================================
# 설정
# ============================================================================

readonly LSP_TIMEOUT=30    # LSP 요청 타임아웃 (초)
readonly LSP_MAX_RETRIES=3 # 최대 재시도 횟수
readonly LSP_CACHE_DIR=".harness/lsp-cache"

if ! declare -f lsp_typescript_diagnostics > /dev/null 2>&1; then
  # shellcheck source=hooks/lib/lsp-diagnostics.sh
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lsp-diagnostics.sh"
fi

if ! declare -f lsp_js_ts_symbols > /dev/null 2>&1; then
  # shellcheck source=hooks/lib/lsp-symbols.sh
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lsp-symbols.sh"
fi

# 언어별 서버 매핑 (bash 3.2 호환)
get_lsp_server() {
  local lang="${1:-}"
  case "$lang" in
    typescript | javascript | typescriptreact | javascriptreact)
      echo "typescript-language-server --stdio"
      ;;
    python)
      echo "pylsp"
      ;;
    go)
      echo "gopls serve"
      ;;
    rust)
      echo "rust-analyzer"
      ;;
    java)
      echo "jdtls"
      ;;
    c | cpp)
      echo "clangd"
      ;;
    *)
      echo ""
      ;;
  esac
}

# 파일 확장자 → 언어 매핑 (bash 3.2 호환)
_get_language_from_extension() {
  local ext="${1:-}"
  case "$ext" in
    ts) echo "typescript" ;;
    tsx) echo "typescriptreact" ;;
    js) echo "javascript" ;;
    jsx) echo "javascriptreact" ;;
    mjs | cjs) echo "javascript" ;;
    py) echo "python" ;;
    go) echo "go" ;;
    rs) echo "rust" ;;
    java) echo "java" ;;
    c) echo "c" ;;
    cpp | cc | cxx) echo "cpp" ;;
    h) echo "c" ;;
    hpp) echo "cpp" ;;
    *) echo "" ;;
  esac
}

# ============================================================================
# LSP 서버 감지 및 관리
# ============================================================================

# detect_language_server <file_path>
# Returns: LSP server command or empty string
detect_language_server() {
  local file_path="${1:-}"
  local ext="${file_path##*.}"

  local language
  language=$(_get_language_from_extension "$ext")

  if [[ -z "$language" ]]; then
    echo ""
    return 0
  fi

  local server_cmd
  server_cmd=$(get_lsp_server "$language")

  echo "$server_cmd"
  return 0
}

language_server_available() {
  local file_path="${1:-}"
  local server_cmd
  server_cmd=$(detect_language_server "$file_path")

  if [[ -z "$server_cmd" ]]; then
    return 1
  fi

  local server_name
  server_name=$(echo "$server_cmd" | cut -d' ' -f1)
  command -v "$server_name" > /dev/null 2>&1
}

# detect_project_language <project_root>
# Returns: primary language of project
detect_project_language() {
  local project_root="${1:-}"

  # TypeScript/JavaScript
  if [[ -f "${project_root}/tsconfig.json" ]]; then
    echo "typescript"
    return 0
  fi

  if [[ -f "${project_root}/package.json" ]]; then
    echo "javascript"
    return 0
  fi

  # Python
  if [[ -f "${project_root}/pyproject.toml" ]] \
    || [[ -f "${project_root}/setup.py" ]] \
    || [[ -f "${project_root}/requirements.txt" ]]; then
    echo "python"
    return 0
  fi

  # Go
  if [[ -f "${project_root}/go.mod" ]]; then
    echo "go"
    return 0
  fi

  # Rust
  if [[ -f "${project_root}/Cargo.toml" ]]; then
    echo "rust"
    return 0
  fi

  # Java
  if [[ -f "${project_root}/pom.xml" ]] \
    || [[ -f "${project_root}/build.gradle" ]]; then
    echo "java"
    return 0
  fi

  echo "unknown"
  return 1
}

# ============================================================================
# LSP 요청 유틸리티
# ============================================================================

# LSP 초기화 (프로젝트 루트에서 서버 시작)
# 주의: 실제 구현에서는 LSP 서버를 백그라운드에서 실행하고 stdio로 통신
# 이 스크립트는 LSP 요청을 JSON-RPC 형식으로 생성

_lsp_create_request() {
  local method="${1:-}"
  local params="${2:-}"
  local id="${3:-1}"

  jq -n \
    --arg method "$method" \
    --argjson params "$params" \
    --argjson id "$id" \
    '{"jsonrpc": "2.0", "id": $id, "method": $method, "params": $params}'
}

# LSP initialize 요청
_lsp_initialize_request() {
  local project_root="${1:-}"
  local root_uri="file://${project_root}"

  _lsp_create_request "initialize" '{
    "processId": null,
    "rootUri": "'"$root_uri"'",
    "capabilities": {
      "textDocument": {
        "definition": {"linkSupport": true},
        "references": {},
        "rename": {"prepareSupport": true},
        "publishDiagnostics": {}
      }
    }
  }' 1
}

# ============================================================================
# LSP 도구 함수 (공개 API)
# ============================================================================

# lsp_diagnostics <file_path> [project_root]
# Returns: JSON array of diagnostics for the file
#
# 진단 정보 조회 (에러, 경고, 정보)
#
# Example output:
# [
#   {
#     "range": {"start": {"line": 10, "character": 0}, "end": {"line": 10, "character": 5}},
#     "severity": 1,  // 1=Error, 2=Warning, 3=Information, 4=Hint
#     "message": "Cannot find name 'foo'",
#     "source": "typescript"
#   }
# ]
lsp_diagnostics() {
  local file_path="${1:-}"
  local project_root="${2:-$(pwd)}"

  local server_cmd
  server_cmd=$(detect_language_server "$file_path")

  if [[ -z "$server_cmd" ]]; then
    echo '[]'
    return 0
  fi

  # 캐시 확인
  local cache_file
  cache_file="${project_root}/${LSP_CACHE_DIR}/diagnostics/$(basename "$file_path").json"
  if lsp_cache_is_fresh "$cache_file" 60; then
    cat "$cache_file"
    return 0
  fi

  # 실제 LSP 통신은 복잡하므로, 대체 방법 사용
  # 1. TypeScript: npx tsc --noEmit
  # 2. Python: pylint or mypy
  # 3. Go: go vet
  # 4. Rust: cargo check

  local diagnostics="[]"
  local language
  language=$(detect_project_language "$project_root")

  case "$language" in
    typescript | javascript)
      diagnostics=$(_get_typescript_diagnostics "$file_path" "$project_root")
      ;;
    python)
      diagnostics=$(_get_python_diagnostics "$file_path" "$project_root")
      ;;
    go)
      diagnostics=$(_get_go_diagnostics "$file_path" "$project_root")
      ;;
    rust)
      diagnostics=$(_get_rust_diagnostics "$file_path" "$project_root")
      ;;
  esac

  # 캐시 저장
  mkdir -p "$(dirname "$cache_file")"
  echo "$diagnostics" > "$cache_file"

  echo "$diagnostics"
}

# TypeScript 진단 (tsc 사용)
_get_typescript_diagnostics() {
  lsp_typescript_diagnostics "$@"
}

# Python 진단 (mypy/pylint 사용)
_get_python_diagnostics() {
  lsp_python_diagnostics "$@"
}

# Go 진단 (go vet 사용)
_get_go_diagnostics() {
  lsp_go_diagnostics "$@"
}

# Rust 진단 (cargo check 사용)
_get_rust_diagnostics() {
  lsp_rust_diagnostics "$@"
}

# ============================================================================
# lsp_goto_definition <file_path> <line> <character> [project_root]
# Returns: JSON with definition location
#
# 정의로 이동 (Go to Definition)
#
# Example output:
# {
#   "uri": "file:///path/to/definition.ts",
#   "range": {"start": {"line": 10, "character": 5}, "end": {"line": 10, "character": 15}}
# }
lsp_goto_definition() {
  local file_path="${1:-}"
  local line="${2:-0}"
  local character="${3:-0}"
  local project_root="${4:-$(pwd)}"

  local server_cmd
  server_cmd=$(detect_language_server "$file_path")

  if [[ -z "$server_cmd" ]]; then
    echo '{"error": "no_lsp_server", "file": "'"$file_path"'"}'
    return 1
  fi

  # LSP textDocument/definition 요청
  local file_uri="file://${file_path}"

  local request
  request=$(_lsp_create_request "textDocument/definition" '{
    "textDocument": {"uri": "'"$file_uri"'"},
    "position": {"line": '"$line"', "character": '"$character"'}
  }' 2)

  # 실제 LSP 통신은 복잡하므로 대체 구현
  # grep 기반 정의 검색
  local symbol
  symbol=$(sed -n "${line}p" "$file_path" | grep -o '[A-Za-z_][A-Za-z0-9_]*' | head -1)

  if [[ -z "$symbol" ]]; then
    echo '{"error": "symbol_not_found"}'
    return 1
  fi

  # 정의 검색 (function, class, const, let, var 등)
  local def_file def_line
  while IFS=: read -r found_file found_line found_content; do
    if [[ "$found_content" =~ (function|class|interface|type|const|let|var)[[:space:]]+"$symbol" ]]; then
      def_file="$found_file"
      def_line="$found_line"
      break
    fi
  done < <(cd "$project_root" && grep -rn "$symbol" --include="*.ts" --include="*.js" --include="*.py" --include="*.go" src/ 2> /dev/null | head -20)

  if [[ -n "$def_file" ]] && [[ -n "$def_line" ]]; then
    jq -n \
      --arg uri "file://${project_root}/${def_file}" \
      --argjson line "$def_line" \
      '{"uri": $uri, "range": {"start": {"line": $line, "character": 0}, "end": {"line": $line, "character": 10}}}'
  else
    echo '{"error": "definition_not_found", "symbol": "'"$symbol"'"}'
    return 1
  fi
}

# ============================================================================
# lsp_find_references <file_path> <line> <character> [project_root]
# Returns: JSON array of reference locations
#
# 참조 찾기 (Find All References)
#
# Example output:
# [
#   {"uri": "file:///path/to/file1.ts", "range": {...}},
#   {"uri": "file:///path/to/file2.ts", "range": {...}}
# ]
lsp_find_references() {
  local file_path="${1:-}"
  local line="${2:-0}"
  local character="${3:-0}"
  local project_root="${4:-$(pwd)}"

  local server_cmd
  server_cmd=$(detect_language_server "$file_path")

  if [[ -z "$server_cmd" ]]; then
    echo '[]'
    return 0
  fi

  # 현재 라인에서 심볼 추출
  local symbol
  symbol=$(lsp_extract_symbol_zero_based_line "$file_path" "$line")

  if [[ -z "$symbol" ]]; then
    echo '[]'
    return 0
  fi

  # grep으로 참조 검색
  local references="[]"
  while IFS=: read -r found_file found_line found_content; do
    # 정의 자체는 제외
    if [[ "$found_content" =~ (function|class|interface|type|const|let|var)[[:space:]]+"$symbol" ]]; then
      continue
    fi

    references=$(lsp_append_location "$references" "file://${project_root}/${found_file}" "$found_line")
  done < <(cd "$project_root" && grep -rn "\b$symbol\b" --include="*.ts" --include="*.js" --include="*.tsx" --include="*.jsx" src/ 2> /dev/null | head -50)

  echo "$references"
}

# ============================================================================
# lsp_rename <file_path> <line> <character> <new_name> [project_root]
# Returns: JSON with workspace edit
#
# 심볼 이름 변경 (Rename)
#
# 이 함수는 미리보기만 제공. 실제 변경은 별도로 수행.
#
# Example output:
# {
#   "changes": {
#     "file:///path/to/file1.ts": [{"range": {...}, "newText": "newName"}],
#     "file:///path/to/file2.ts": [{"range": {...}, "newText": "newName"}]
#   }
# }
lsp_rename() {
  local file_path="${1:-}"
  local line="${2:-0}"
  local character="${3:-0}"
  local new_name="${4:-}"
  local project_root="${5:-$(pwd)}"

  if [[ -z "$new_name" ]]; then
    echo '{"error": "new_name_required"}'
    return 1
  fi

  local server_cmd
  server_cmd=$(detect_language_server "$file_path")

  if [[ -z "$server_cmd" ]]; then
    echo '{"error": "no_lsp_server"}'
    return 1
  fi

  # 현재 심볼 추출
  local old_symbol
  old_symbol=$(lsp_extract_symbol_zero_based_line "$file_path" "$line")

  if [[ -z "$old_symbol" ]]; then
    echo '{"error": "symbol_not_found"}'
    return 1
  fi

  # 참조 찾기
  local references
  references=$(lsp_find_references "$file_path" "$line" "$character" "$project_root")

  # 변경 사항 생성
  local changes="{}"

  # 정의 포함
  changes=$(lsp_append_workspace_edit "$changes" "file://${file_path}" "$line" "$new_name")

  # 참조 포함
  local ref_count
  ref_count=$(echo "$references" | jq 'length')

  for ((i = 0; i < ref_count; i++)); do
    local ref_uri ref_line
    ref_uri=$(echo "$references" | jq -r ".[$i].uri")
    ref_line=$(echo "$references" | jq -r ".[$i].range.start.line")

    changes=$(lsp_append_workspace_edit "$changes" "$ref_uri" "$ref_line" "$new_name")
  done

  jq -n --argjson changes "$changes" \
    '{"documentChanges": [], "changes": $changes, "oldName": "'"$old_symbol"'", "newName": "'"$new_name"'"}'
}

# ============================================================================
# lsp_get_symbols <file_path> [project_root]
# Returns: JSON array of symbols in the file
#
# 파일 내 심볼 목록 조회
#
# Example output:
# [
#   {"name": "MyClass", "kind": "class", "range": {...}},
#   {"name": "myFunction", "kind": "function", "range": {...}}
# ]
lsp_get_symbols() {
  local file_path="${1:-}"
  local project_root="${2:-$(pwd)}"

  local server_cmd
  server_cmd=$(detect_language_server "$file_path")

  if [[ -z "$server_cmd" ]]; then
    echo '[]'
    return 0
  fi

  local symbols="[]"
  local ext="${file_path##*.}"

  case "$ext" in
    ts | tsx | js | jsx)
      symbols=$(_get_js_ts_symbols "$file_path")
      ;;
    py)
      symbols=$(_get_python_symbols "$file_path")
      ;;
    go)
      symbols=$(_get_go_symbols "$file_path")
      ;;
    rs)
      symbols=$(_get_rust_symbols "$file_path")
      ;;
  esac

  echo "$symbols"
}

# JavaScript/TypeScript 심볼 추출
_get_js_ts_symbols() {
  lsp_js_ts_symbols "$@"
}

# Python 심볼 추출
_get_python_symbols() {
  lsp_python_symbols "$@"
}

# Go 심볼 추출
_get_go_symbols() {
  lsp_go_symbols "$@"
}

# Rust 심볼 추출
_get_rust_symbols() {
  lsp_rust_symbols "$@"
}

# ============================================================================
# 통합 진단 (프로젝트 전체)
# ============================================================================

# lsp_project_diagnostics <project_root>
# Returns: JSON with all project diagnostics
lsp_project_diagnostics() {
  lsp_collect_project_diagnostics "$@"
}

# ============================================================================
# 편의 함수
# ============================================================================

# lsp_has_errors <project_root>
# Returns: 0 if no errors, 1 if errors exist
lsp_has_errors() {
  local project_root="${1:-$(pwd)}"

  if lsp_project_has_errors "$project_root"; then
    return 1
  fi

  return 0
}

# lsp_format_diagnostic_report <project_root>
# Returns: Human-readable diagnostic report
lsp_format_diagnostic_report() {
  lsp_render_diagnostic_report "$@"
}
