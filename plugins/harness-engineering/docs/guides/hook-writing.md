# 훅 작성 가이드

## 훅이란?

훅은 Claude Code의 **이벤트에 반응하는 스크립트**입니다. 세션 시작, 도구 사용 전/후, 에이전트 전환 등에 자동 실행됩니다.

## 설정 (hooks.json)

```json
{
  "hooks": {
    "이벤트명": [
      {
        "matcher": "도구/에이전트 이름 패턴",
        "hooks": [
          {
            "type": "command",
            "command": "bash hooks/my-hook.sh",
            "description": "설명"
          }
        ]
      }
    ]
  }
}
```

## 이벤트 목록

| 이벤트 | 시점 | 입력 |
|:-------|:-----|:-----|
| `SessionStart` | 세션 시작 | 세션 정보 |
| `SessionEnd` | 세션 종료 | 세션 정보 |
| `PreToolUse` | 도구 실행 전 | 도구 이름, 입력 |
| `PostToolUse` | 도구 실행 후 | 도구 이름, 결과 |
| `SubagentStart` | 에이전트 시작 | 에이전트 이름 |
| `SubagentStop` | 에이전트 종료 | 에이전트 이름 |

## stdin JSON 스키마

훅 스크립트는 **stdin으로 JSON 페이로드**를 받습니다:

```json
{
  "cwd": "/path/to/project",
  "tool_name": "Bash",
  "tool_input": {
    "command": "npm test"
  }
}
```

Claude Code는 훅 실행 시 프로젝트 루트를 나타내는 `CLAUDE_PROJECT_DIR` 환경변수도 제공합니다. 이 저장소의 훅은 `CLAUDE_PROJECT_DIR`를 우선 사용하고, 없으면 payload의 `cwd`를 fallback으로 사용합니다. Git 저장소에서는 세션 시작 시 `.harness/`를 `.git/info/exclude`에 자동 등록해 런타임 파일이 커밋 대상에 섞이지 않게 합니다.

## 훅 스크립트 템플릿

```bash
#!/usr/bin/env bash
set -euo pipefail

PAYLOAD=$(cat)   # stdin에서 JSON 읽기
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
HARNESS_DIR="${PROJECT_ROOT}/.harness"

# jq로 필드 추출
TOOL_NAME=$(echo "$PAYLOAD" | jq -r '.tool_name // ""')

case "$TOOL_NAME" in
  Bash) echo "Bash 호출됨" ;;
  Write) echo "Write 호출됨" ;;
esac
```

## 차단 응답

PreToolUse에서 도구 실행을 차단하려면:

```bash
echo '{"decision":"block","reason":"차단 사유"}'
```

## 작성 팁

1. **`set -euo pipefail`** 을 항상 포함하세요
2. **jq 없이도 동작**하도록 fallback을 넣으세요
3. **민감 정보를 로그에 남기지** 마세요
4. **빠르게 실행**되어야 합니다 — 사용자 대기 시간이 늘어남
5. **프로젝트 로컬 상태 디렉토리**가 필요하면 `CLAUDE_PROJECT_DIR/.harness` 또는 payload의 `cwd`를 사용하세요
6. **자동 ignore는 `.git/info/exclude` 우선**으로 처리하면 팀 공용 `.gitignore`를 오염시키지 않을 수 있습니다

## 수동 검증법

```bash
# hooks.json 유효성 검사
cat hooks/hooks.json | jq .

# 개별 훅 스크립트 테스트
echo '{"cwd":"'"$(pwd)"'","tool_name":"Bash","tool_input":{"command":"ls"}}' | bash hooks/pre-tool.sh

# 훅 로그 확인
cat .harness/logs/session.log
tail -f .harness/logs/security.log
```

## 라이브러리 모듈 (hooks/lib/)

훅 스크립트에서 공통으로 사용하는 모듈들입니다:

| 모듈 | 용도 |
|:-----|:-----|
| `json-utils.sh` | JSON 파싱, jq fallback |
| `logging.sh` | 로그 기록 유틸리티 |
| `context-rot.sh` | Context Rot 점수 계산 |
| `automation-level.sh` | 자동화 레벨 판단 |
| `feature-registry.sh` | Feature Slug 관리 |
| `wave-executor.sh` | Wave 실행 시스템 |

### 모듈 사용 예시

```bash
#!/usr/bin/env bash
set -euo pipefail

# 모듈 로드
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/logging.sh"
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/json-utils.sh"

# 로그 기록
log_info "메시지"

# JSON 파싱 (jq 없어도 동작)
PAYLOAD=$(cat)
TOOL_NAME=$(json_get "$PAYLOAD" '.tool_name')
```

## 테스트 (hooks/__tests__/)

훅 모듈에 대한 단위 테스트가 있습니다:

```bash
# 테스트 실행
bash hooks/__tests__/common.test.sh
```
