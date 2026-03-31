# LSP 통합 (Language Server Protocol Integration)

LSP를 활용하여 IDE 수준의 코드 분석 및 리팩토링 기능을 제공합니다.

---

## 1. 개요

LSP 통합은 Claude Code가 코드를 더 정확하게 이해하고 조작할 수 있게 합니다.

### 지원 언어

| 언어 | LSP 서버 | 설치 |
|------|----------|------|
| TypeScript | `typescript-language-server` | `npm i -g typescript-language-server` |
| JavaScript | `typescript-language-server` | `npm i -g typescript-language-server` |
| Python | `pylsp` | `pip install python-lsp-server` |
| Go | `gopls` | Go 설치 시 자동 포함 |
| Rust | `rust-analyzer` | `rustup component add rust-analyzer` |
| Java | `jdtls` | Eclipse JDT Language Server |
| C/C++ | `clangd` | LLVM 설치 시 포함 |

---

## 2. API

### lsp_diagnostics

파일의 진단 정보(에러, 경고)를 조회합니다.

```bash
lsp_diagnostics <file_path> [project_root]
```

**반환값:**
```json
[
  {
    "range": {
      "start": {"line": 10, "character": 0},
      "end": {"line": 10, "character": 5}
    },
    "severity": 1,
    "message": "Cannot find name 'foo'",
    "source": "typescript"
  }
]
```

**심각도:**
- `1` = Error
- `2` = Warning
- `3` = Information
- `4` = Hint

---

### lsp_goto_definition

심볼의 정의 위치로 이동합니다.

```bash
lsp_goto_definition <file_path> <line> <character> [project_root]
```

**반환값:**
```json
{
  "uri": "file:///path/to/definition.ts",
  "range": {
    "start": {"line": 10, "character": 5},
    "end": {"line": 10, "character": 15}
  }
}
```

---

### lsp_find_references

심볼의 모든 참조를 찾습니다.

```bash
lsp_find_references <file_path> <line> <character> [project_root]
```

**반환값:**
```json
[
  {
    "uri": "file:///path/to/file1.ts",
    "range": {"start": {"line": 10, "character": 0}}
  },
  {
    "uri": "file:///path/to/file2.ts",
    "range": {"start": {"line": 25, "character": 5}}
  }
]
```

---

### lsp_rename

심볼 이름 변경을 위한 변경 사항을 미리보기합니다.

```bash
lsp_rename <file_path> <line> <character> <new_name> [project_root]
```

**반환값:**
```json
{
  "changes": {
    "file:///path/to/file1.ts": [
      {
        "range": {"start": {"line": 10, "character": 0}},
        "newText": "newName"
      }
    ],
    "file:///path/to/file2.ts": [
      {
        "range": {"start": {"line": 25, "character": 5}},
        "newText": "newName"
      }
    ]
  },
  "oldName": "oldName",
  "newName": "newName"
}
```

**주의:** 이 함수는 미리보기만 제공합니다. 실제 변경은 별도로 수행해야 합니다.

---

### lsp_get_symbols

파일 내 모든 심볼을 조회합니다.

```bash
lsp_get_symbols <file_path> [project_root]
```

**반환값:**
```json
[
  {
    "name": "MyClass",
    "kind": "class",
    "range": {"start": {"line": 10, "character": 0}}
  },
  {
    "name": "myFunction",
    "kind": "function",
    "range": {"start": {"line": 25, "character": 0}}
  }
]
```

---

### lsp_project_diagnostics

프로젝트 전체의 진단 정보를 조회합니다.

```bash
lsp_project_diagnostics <project_root>
```

**반환값:**
```json
{
  "diagnostics": [...],
  "summary": {
    "errors": 5,
    "warnings": 12
  }
}
```

---

### lsp_has_errors

프로젝트에 에러가 있는지 확인합니다.

```bash
lsp_has_errors <project_root>
# Returns: 0 if no errors, 1 if errors exist
```

---

### lsp_format_diagnostic_report

사람이 읽을 수 있는 진단 리포트를 생성합니다.

```bash
lsp_format_diagnostic_report <project_root>
```

**출력:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
LSP Diagnostic Report
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Errors: 2
Warnings: 5

❌ Errors:
  src/auth.ts:10: Cannot find name 'foo'
  src/api.ts:25: Type 'string' is not assignable to type 'number'

⚠️  Warnings:
  src/utils.ts:15: Unused variable 'temp'
  ...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## 3. Wave Executor 통합

LSP 진단은 Wave 실행 전후로 자동 실행됩니다:

```bash
# Wave 실행 전 타입 체크
if lsp_has_errors "$PROJECT_ROOT"; then
  echo "❌ Type errors found. Fix before proceeding."
  lsp_format_diagnostic_report "$PROJECT_ROOT"
  exit 1
fi

# Wave 실행
execute_all_waves "$FEATURE_SLUG" "$PROJECT_ROOT"

# Wave 실행 후 검증
lsp_project_diagnostics "$PROJECT_ROOT"
```

---

## 4. Check 스킬 통합

`/check` 스킬에서 LSP 진단을 사용합니다:

```markdown
## Check Process

### 1. LSP Diagnostics
Run type checking and static analysis:

\`\`\`bash
lsp_project_diagnostics "$PROJECT_ROOT"
\`\`\`

### 2. Test Execution
Run tests with coverage:

\`\`\`bash
run_tests "$PROJECT_ROOT"
\`\`\`

### 3. Gap Analysis
Compare implementation against design.md
```

---

## 5. 내부 구현

### 대체 구현 전략

실제 LSP 통신은 복잡하므로, 언어별 네이티브 도구를 사용합니다:

| 언어 | 대체 도구 | 명령어 |
|------|----------|--------|
| TypeScript | tsc | `npx tsc --noEmit` |
| Python | mypy | `mypy --output json` |
| Go | go vet | `go vet ./...` |
| Rust | cargo | `cargo check --message-format=json` |

### 캐싱

진단 결과는 60초간 캐시됩니다:

```
.harness/lsp-cache/diagnostics/<filename>.json
```

---

## 6. 의존성

### 필수
- `jq` - JSON 파싱
- 언어별 LSP 서버 (선택)

### 선택
- `typescript-language-server` - TypeScript/JavaScript
- `pylsp` 또는 `mypy` - Python
- `gopls` - Go
- `rust-analyzer` - Rust

---

## 7. 참고

- [Language Server Protocol Specification](https://microsoft.github.io/language-server-protocol/)
- [oh-my-openagent LSP Tools](https://github.com/code-yeongyu/oh-my-openagent)
- [typescript-language-server](https://github.com/typescript-language-server/typescript-language-server)
