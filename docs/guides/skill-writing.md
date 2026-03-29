# 스킬 작성 가이드

## 스킬이란?

스킬은 Claude Code에서 **실행 가능한 작업 단위**입니다. `/skill-name` 또는 `/plugin-name:skill-name` 으로 호출합니다.

## 디렉토리 구조

```
skills/
└── my-skill/
    ├── SKILL.md          # 필수: 메인 지시문
    ├── reference.md      # 선택: 상세 참고 자료
    ├── examples/         # 선택: 예제
    └── scripts/          # 선택: 유틸 스크립트
```

## SKILL.md 템플릿

```markdown
---
name: my-skill
description: 이 스킬이 하는 일. 언제 사용하는지 설명.
user-invocable: true
argument-hint: <인자 설명>
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

# My Skill

$ARGUMENTS 를 받아서 수행할 작업 설명.

## 프로세스
1. 단계 1
2. 단계 2

## 출력 형식
...
```

## Frontmatter 필드

| 필드 | 필수 | 설명 |
|:-----|:----:|:-----|
| `name` | ○ | 스킬 이름 (슬래시 커맨드) |
| `description` | ○ | 설명. 자동 트리거에 사용됨 |
| `user-invocable` | - | `true`면 `/name`으로 직접 호출 가능 |
| `argument-hint` | - | 인자 힌트 (예: `<파일명>`) |
| `allowed-tools` | - | 사용 가능한 도구 제한 (예: `Read, Write, Edit, Bash, Grep, Glob, AskUserQuestion`) |
| `disable-model-invocation` | - | `true`면 명시 호출만 가능 |
| `context` | - | `fork`면 서브에이전트로 실행 |

## 변수 치환

- `$ARGUMENTS` — 사용자가 전달한 인자 전체
- `$ARGUMENTS[0]`, `$ARGUMENTS[1]` — 개별 인자
- `${CLAUDE_SESSION_ID}` — 세션 ID
- `${CLAUDE_SKILL_DIR}` — SKILL.md가 있는 디렉토리

## 작성 팁

1. **description을 풍부하게** 작성하면 자동 트리거 확률이 높아집니다
2. **allowed-tools로 도구를 제한**하면 스킬이 안전하게 작동합니다
3. **"다음 단계"를 안내**하면 워크플로우가 자연스럽게 이어집니다
4. 별도 파일은 SKILL.md에서 `[참고](reference.md)` 형태로 링크합니다
