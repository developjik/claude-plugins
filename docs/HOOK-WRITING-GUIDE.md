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
  "tool_name": "Bash",
  "input": {
    "command": "npm test"
  }
}
```

## 훅 스크립트 템플릿

```bash
#!/usr/bin/env bash
set -euo pipefail

PAYLOAD=$(cat)   # stdin에서 JSON 읽기

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

## 수동 검증법

```bash
# hooks.json 유효성 검사
cat hooks.json | jq .

# 개별 훅 스크립트 테스트
echo '{"tool_name":"Bash","input":{"command":"ls"}}' | bash hooks/pre-tool.sh

# 훅 로그 확인
cat ~/.harness-engineering/logs/session.log
tail -f ~/.harness-engineering/logs/security.log
```
