# 에이전트 작성 가이드

## 에이전트란?

에이전트는 Claude Code의 **인지 모드(persona)**입니다. "어떤 두뇌로 생각할 것인가"를 결정합니다.

## 파일 위치

```
agents/
└── my-agent.md     # 마크다운 파일
```

## 에이전트 템플릿

```markdown
---
name: my-agent
description: 역할 설명. 언제 이 에이전트를 사용하는지.
tools: Read, Grep, Glob
model: sonnet
color: blue
---

# My Agent

당신은 [역할]입니다. [핵심 철학].

## 인지 모드
- [이 에이전트의 사고방식]

## 프로세스
1. [단계]

## 출력 형식
...

## 주의사항
- [제약 사항]
```

## Frontmatter 필드

| 필드 | 필수 | 설명 |
|:-----|:----:|:-----|
| `name` | ○ | 에이전트 이름 |
| `description` | ○ | 역할 설명 |
| `tools` | - | 사용 가능 도구. 쉼표 구분 |
| `model` | - | `sonnet`, `opus`, `haiku`, `inherit` |
| `color` | - | UI 표시 색상 |
| `permissionMode` | - | `default`, `acceptEdits`, `plan` 등 |
| `maxTurns` | - | 최대 턴 수 제한 |

## 도구 제한 가이드

| 역할 유형 | 추천 도구 | 이유 |
|:---------|:---------|:-----|
| **분석/리뷰** | `Read, Grep, Glob, Bash` | 읽기 전용으로 안전한 분석 |
| **구현/수정** | `Read, Write, Edit, Bash, Grep, Glob` | 코드 작성 권한 필요 |
| **문서화** | `Read, Write, Edit, Grep, Glob` | 문서 작성, Bash 불필요 |

## 작성 팁

1. **인지 모드를 명확히** 정의하세요 — "어떤 관점에서 생각하는가"
2. **도구를 최소한으로** 제한하세요 — 역할에 필요한 것만
3. **다음 단계를 안내**하세요 — 워크플로우 연결
4. **Write/Edit 없이 분석만** 하는 에이전트가 더 안전합니다
