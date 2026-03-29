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

readonly LSP_TIMEOUT=30        # LSP 요청 타임아웃 (초)
readonly LSP_MAX_RETRIES=3     # 최대 재시도 횟수
readonly LSP_CACHE_DIR=".harness/lsp-cache"

# 언어별 서버 매핑 (bash 3.2 호환)
get_lsp_server() {
  local lang="${1:-}"
  case "$lang" in
    typescript|javascript|typescriptreact|javascriptreact)
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
    c|cpp)
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
    mjs|cjs) echo "javascript" ;;
    py) echo "python" ;;
    go) echo "go" ;;
    rs) echo "rust" ;;
    java) echo "java" ;;
    c) echo "c" ;;
    cpp|cc|cxx) echo "cpp" ;;
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
  command -v "$server_name" >/dev/null 2>&1
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
  if [[ -f "${project_root}/pyproject.toml" ]] || \
     [[ -f "${project_root}/setup.py" ]] || \
     [[ -f "${project_root}/requirements.txt" ]]; then
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
  if [[ -f "${project_root}/pom.xml" ]] || \
     [[ -f "${project_root}/build.gradle" ]]; then
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
  local cache_file="${project_root}/${LSP_CACHE_DIR}/diagnostics/$(basename "$file_path").json"
  if [[ -f "$cache_file" ]] && [[ $(($(date +%s) - $(stat -f %m "$cache_file" 2>/dev/null || echo 0))) -lt 60 ]]; then
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
    typescript|javascript)
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
  local file_path="${1:-}"
  local project_root="${2:-}"

  if [[ ! -f "${project_root}/tsconfig.json" ]]; then
    echo '[]'
    return 0
  fi

  local result
  result=$(cd "$project_root" && npx tsc --noEmit --pretty false 2>&1 || true)

  # tsc 출력 파싱
  local diagnostics="[]"
  while IFS= read -r line; do
    if [[ "$line" =~ ^(.+)\(([0-9]+),([0-9]+)\):\ error\ (.+)$ ]]; then
      local file="${BASH_REMATCH[1]}"
      local line_num="${BASH_REMATCH[2]}"
      local col="${BASH_REMATCH[3]}"
      local message="${BASH_REMATCH[4]}"

      if [[ "$file" == "$file_path" ]] || [[ "$file" == *$(basename "$file_path")* ]]; then
        diagnostics=$(echo "$diagnostics" | jq --arg line "$line_num" --arg col "$col" --arg msg "$message" \
          '. += [{"range": {"start": {"line": ($line | tonumber), "character": ($col | tonumber)}, "end": {"line": ($line | tonumber), "character": (($col | tonumber) + 1)}}, "severity": 1, "message": $msg, "source": "typescript"}]')
      fi
    fi
  done <<< "$result"

  echo "$diagnostics"
}

# Python 진단 (mypy/pylint 사용)
_get_python_diagnostics() {
  local file_path="${1:-}"
  local project_root="${2:-}"

  local diagnostics="[]"

  # mypy 시도
  if command -v mypy &>/dev/null; then
    local result
    result=$(cd "$project_root" && mypy --output json "$file_path" 2>/dev/null || true)

    if [[ -n "$result" ]]; then
      while IFS= read -r item; do
        local severity=3
        if echo "$item" | jq -e '.error' &>/dev/null; then
          severity=1
        fi

        diagnostics=$(echo "$diagnostics" | jq --argjson item "$item" --argjson sev "$severity" \
          '. += [{"range": {"start": {"line": ($item.line | tonumber), "character": ($item.column | tonumber)}, "end": {"line": ($item.line | tonumber), "character": (($item.column | tonumber) + 1)}}, "severity": $sev, "message": $item.message, "source": "mypy"}]')
      done <<< "$(echo "$result" | jq -c '.[]' 2>/dev/null || true)"
    fi
  fi

  echo "$diagnostics"
}

# Go 진단 (go vet 사용)
_get_go_diagnostics() {
  local file_path="${1:-}"
  local project_root="${2:-}"

  local diagnostics="[]"

  if command -v go &>/dev/null; then
    local result
    result=$(cd "$project_root" && go vet ./... 2>&1 || true)

    # go vet 출력 파싱 (간소화)
    while IFS= read -r line; do
      if [[ "$line" =~ ^(.+):([0-9]+):([0-9]+):\ (.+)$ ]]; then
        local file="${BASH_REMATCH[1]}"
        local line_num="${BASH_REMATCH[2]}"
        local col="${BASH_REMATCH[3]}"
        local message="${BASH_REMATCH[4]}"

        diagnostics=$(echo "$diagnostics" | jq --arg line "$line_num" --arg col "$col" --arg msg "$message" \
          '. += [{"range": {"start": {"line": ($line | tonumber), "character": ($col | tonumber)}, "end": {"line": ($line | tonumber), "character": (($col | tonumber) + 1)}}, "severity": 2, "message": $msg, "source": "go vet"}]')
      fi
    done <<< "$result"
  fi

  echo "$diagnostics"
}

# Rust 진단 (cargo check 사용)
_get_rust_diagnostics() {
  local file_path="${1:-}"
  local project_root="${2:-}"

  local diagnostics="[]"

  if command -v cargo &>/dev/null; then
    local result
    result=$(cd "$project_root" && cargo check --message-format=json 2>&1 || true)

    # cargo check JSON 출력 파싱
    while IFS= read -r line; do
      if echo "$line" | jq -e '.reason == "compiler-message"' &>/dev/null; then
        local message=$(echo "$line" | jq -r '.message.rendered')
        local severity=2
        if echo "$line" | jq -e '.message.level == "error"' &>/dev/null; then
          severity=1
        fi

        local spans=$(echo "$line" | jq -c '.message.spans[0] // empty')
        if [[ "$spans" != "null" ]] && [[ -n "$spans" ]]; then
          local line_num=$(echo "$spans" | jq -r '.line_start')
          local col=$(echo "$spans" | jq -r '.column_start')

          diagnostics=$(echo "$diagnostics" | jq --arg line "$line_num" --arg col "$col" --arg msg "$message" --argjson sev "$severity" \
            '. += [{"range": {"start": {"line": ($line | tonumber), "character": ($col | tonumber)}, "end": {"line": ($line | tonumber), "character": (($col | tonumber) + 1)}}, "severity": $sev, "message": $msg, "source": "rustc"}]')
        fi
      fi
    done <<< "$result"
  fi

  echo "$diagnostics"
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
  done < <(cd "$project_root" && grep -rn "$symbol" --include="*.ts" --include="*.js" --include="*.py" --include="*.go" src/ 2>/dev/null | head -20)

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
  symbol=$(sed -n "$((line + 1))p" "$file_path" | grep -o '[A-Za-z_][A-Za-z0-9_]*' | head -1)

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

    references=$(echo "$references" | jq \
      --arg uri "file://${project_root}/${found_file}" \
      --argjson line "$found_line" \
      '. += [{"uri": $uri, "range": {"start": {"line": $line, "character": 0}, "end": {"line": $line, "character": 10}}}]')
  done < <(cd "$project_root" && grep -rn "\b$symbol\b" --include="*.ts" --include="*.js" --include="*.tsx" --include="*.jsx" src/ 2>/dev/null | head -50)

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
  old_symbol=$(sed -n "$((line + 1))p" "$file_path" | grep -o '[A-Za-z_][A-Za-z0-9_]*' | head -1)

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
  changes=$(echo "$changes" | jq --arg uri "file://${file_path}" \
    '.[$uri] = [{"range": {"start": {"line": '"$line"', "character": 0}, "end": {"start": {"line": '"$line"', "character": 10}}}, "newText": "'"$new_name"'"}]')

  # 참조 포함
  local ref_count
  ref_count=$(echo "$references" | jq 'length')

  for ((i=0; i<ref_count; i++)); do
    local ref_uri ref_line
    ref_uri=$(echo "$references" | jq -r ".[$i].uri")
    ref_line=$(echo "$references" | jq -r ".[$i].range.start.line")

    changes=$(echo "$changes" | jq --arg uri "$ref_uri" --argjson line "$ref_line" --arg new "$new_name" \
      '.[$uri] += [{"range": {"start": {"line": $line, "character": 0}}, "newText": $new}]')
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
    ts|tsx|js|jsx)
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
  local file_path="${1:-}"
  local symbols="[]"
  local line_num=0

  # 간단한 regex 기반 심볼 추출
  while IFS= read -r line; do
    local name="" kind=""

    # Class
    if [[ "$line" =~ (class|interface|type)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*) ]]; then
      name="${BASH_REMATCH[2]}"
      kind="${BASH_REMATCH[1]}"
    # Function
    elif [[ "$line" =~ (function|const|let|var)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*= ]]; then
      name="${BASH_REMATCH[2]}"
      kind="${BASH_REMATCH[1]}"
    # Function declaration
    elif [[ "$line" =~ function[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*\(|function[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*\< ]]; then
      name="${BASH_REMATCH[1]}"
      kind="function"
    fi

    if [[ -n "$name" ]]; then
      symbols=$(echo "$symbols" | jq --arg name "$name" --arg kind "$kind" --argjson line "$line_num" \
        '. += [{"name": $name, "kind": $kind, "range": {"start": {"line": $line, "character": 0}}}]')
    fi

    line_num=$((line_num + 1))
  done < "$file_path"

  echo "$symbols"
}

# Python 심볼 추출
_get_python_symbols() {
  local file_path="${1:-}"
  local symbols="[]"
  local line_num=0

  while IFS= read -r line; do
    local name="" kind=""

    # Class
    if [[ "$line" =~ ^class[[:space:]]+([A-Za-z_][A-Za-z0-9_]*) ]]; then
      name="${BASH_REMATCH[1]}"
      kind="class"
    # Function
    elif [[ "$line" =~ ^def[[:space:]]+([a-z_][a-z0-9_]*) ]]; then
      name="${BASH_REMATCH[1]}"
      kind="function"
    # Async function
    elif [[ "$line" =~ ^async[[:space:]]+def[[:space:]]+([a-z_][a-z0-9_]*) ]]; then
      name="${BASH_REMATCH[1]}"
      kind="function"
    fi

    if [[ -n "$name" ]]; then
      symbols=$(echo "$symbols" | jq --arg name "$name" --arg kind "$kind" --argjson line "$line_num" \
        '. += [{"name": $name, "kind": $kind, "range": {"start": {"line": $line, "character": 0}}}]')
    fi

    line_num=$((line_num + 1))
  done < "$file_path"

  echo "$symbols"
}

# Go 심볼 추출
_get_go_symbols() {
  local file_path="${1:-}"
  local symbols="[]"
  local line_num=0

  while IFS= read -r line; do
    local name="" kind=""

    # Struct/Interface
    if [[ "$line" =~ ^(type|struct|interface)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*) ]]; then
      name="${BASH_REMATCH[2]}"
      kind="${BASH_REMATCH[1]}"
    # Function
    elif [[ "$line" =~ ^func[[:space:]]+\(?[A-Za-z_*]+\)?[[:space:]]*([A-Za-z_][A-Za-z0-9_]*) ]]; then
      name="${BASH_REMATCH[1]}"
      kind="function"
    fi

    if [[ -n "$name" ]]; then
      symbols=$(echo "$symbols" | jq --arg name "$name" --arg kind "$kind" --argjson line "$line_num" \
        '. += [{"name": $name, "kind": $kind, "range": {"start": {"line": $line, "character": 0}}}]')
    fi

    line_num=$((line_num + 1))
  done < "$file_path"

  echo "$symbols"
}

# Rust 심볼 추출
_get_rust_symbols() {
  local file_path="${1:-}"
  local symbols="[]"
  local line_num=0

  while IFS= read -r line; do
    local name="" kind=""

    # Struct/Enum/Trait
    if [[ "$line" =~ ^(struct|enum|trait|type)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*) ]]; then
      name="${BASH_REMATCH[2]}"
      kind="${BASH_REMATCH[1]}"
    # Function
    elif [[ "$line" =~ ^(pub[[:space:]]+)?fn[[:space:]]+([a-z_][a-z0-9_]*) ]]; then
      name="${BASH_REMATCH[2]}"
      kind="function"
    fi

    if [[ -n "$name" ]]; then
      symbols=$(echo "$symbols" | jq --arg name "$name" --arg kind "$kind" --argjson line "$line_num" \
        '. += [{"name": $name, "kind": $kind, "range": {"start": {"line": $line, "character": 0}}}]')
    fi

    line_num=$((line_num + 1))
  done < "$file_path"

  echo "$symbols"
}

# ============================================================================
# 통합 진단 (프로젝트 전체)
# ============================================================================

# lsp_project_diagnostics <project_root>
# Returns: JSON with all project diagnostics
lsp_project_diagnostics() {
  local project_root="${1:-$(pwd)}"

  local language
  language=$(detect_project_language "$project_root")

  local all_diagnostics="[]"

  case "$language" in
    typescript|javascript)
      # TypeScript: tsc --noEmit
      local result
      result=$(cd "$project_root" && npx tsc --noEmit --pretty false 2>&1 || true)

      while IFS= read -r line; do
        if [[ "$line" =~ ^(.+)\(([0-9]+),([0-9]+)\):\ (error|warning)\ (.+)$ ]]; then
          local file="${BASH_REMATCH[1]}"
          local line_num="${BASH_REMATCH[2]}"
          local col="${BASH_REMATCH[3]}"
          local severity_word="${BASH_REMATCH[4]}"
          local message="${BASH_REMATCH[5]}"

          local severity=3
          [[ "$severity_word" == "error" ]] && severity=1
          [[ "$severity_word" == "warning" ]] && severity=2

          all_diagnostics=$(echo "$all_diagnostics" | jq \
            --arg file "$file" --argjson line "$line_num" --argjson col "$col" \
            --argjson sev "$severity" --arg msg "$message" \
            '. += [{"file": $file, "line": $line, "column": $col, "severity": $sev, "message": $msg}]')
        fi
      done <<< "$result"
      ;;

    python)
      # Python: mypy
      if command -v mypy &>/dev/null; then
        local result
        result=$(cd "$project_root" && mypy --output json . 2>/dev/null || true)

        while IFS= read -r item; do
          local file=$(echo "$item" | jq -r '.file')
          local line=$(echo "$item" | jq -r '.line')
          local col=$(echo "$item" | jq -r '.column // 0')
          local message=$(echo "$item" | jq -r '.message')
          local severity=3
          [[ "$(echo "$item" | jq -r '.severity')" == "error" ]] && severity=1

          all_diagnostics=$(echo "$all_diagnostics" | jq \
            --arg file "$file" --argjson line "$line" --argjson col "$col" \
            --argjson sev "$severity" --arg msg "$message" \
            '. += [{"file": $file, "line": $line, "column": $col, "severity": $sev, "message": $msg}]')
        done <<< "$(echo "$result" | jq -c '.[]' 2>/dev/null || true)"
      fi
      ;;

    go)
      # Go: go vet
      local result
      result=$(cd "$project_root" && go vet ./... 2>&1 || true)

      while IFS= read -r line; do
        if [[ "$line" =~ ^(.+):([0-9]+):([0-9]+):\ (.+)$ ]]; then
          all_diagnostics=$(echo "$all_diagnostics" | jq \
            --arg file "${BASH_REMATCH[1]}" \
            --argjson line "${BASH_REMATCH[2]}" \
            --argjson col "${BASH_REMATCH[3]}" \
            --arg msg "${BASH_REMATCH[4]}" \
            '. += [{"file": $file, "line": $line, "column": $col, "severity": 2, "message": $msg}]')
        fi
      done <<< "$result"
      ;;

    rust)
      # Rust: cargo check
      local result
      result=$(cd "$project_root" && cargo check --message-format=json 2>&1 || true)

      while IFS= read -r line; do
        if echo "$line" | jq -e '.reason == "compiler-message"' &>/dev/null; then
          local message=$(echo "$line" | jq -r '.message.rendered')
          local spans=$(echo "$line" | jq -c '.message.spans[0] // empty')

          if [[ "$spans" != "null" ]]; then
            all_diagnostics=$(echo "$all_diagnostics" | jq \
              --arg file "$(echo "$spans" | jq -r '.file_name')" \
              --argjson line "$(echo "$spans" | jq -r '.line_start')" \
              --argjson col "$(echo "$spans" | jq -r '.column_start')" \
              --arg msg "$message" \
              '. += [{"file": $file, "line": $line, "column": $col, "severity": 1, "message": $msg}]')
          fi
        fi
      done <<< "$result"
      ;;
  esac

  # 요약 추가
  local error_count warning_count
  error_count=$(echo "$all_diagnostics" | jq '[.[] | select(.severity == 1)] | length')
  warning_count=$(echo "$all_diagnostics" | jq '[.[] | select(.severity == 2)] | length')

  echo "$all_diagnostics" | jq --argjson errors "$error_count" --argjson warnings "$warning_count" \
    '{"diagnostics": ., "summary": {"errors": $errors, "warnings": $warnings}}'
}

# ============================================================================
# 편의 함수
# ============================================================================

# lsp_has_errors <project_root>
# Returns: 0 if no errors, 1 if errors exist
lsp_has_errors() {
  local project_root="${1:-$(pwd)}"

  local result
  result=$(lsp_project_diagnostics "$project_root")

  local error_count
  error_count=$(echo "$result" | jq '.summary.errors')

  [[ "$error_count" -gt 0 ]] && return 1
  return 0
}

# lsp_format_diagnostic_report <project_root>
# Returns: Human-readable diagnostic report
lsp_format_diagnostic_report() {
  local project_root="${1:-$(pwd)}"

  local result
  result=$(lsp_project_diagnostics "$project_root")

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
