---
name: design
description: Use when an approved plan must be translated into file-level technical design and atomic implementation tasks.
user-invocable: true
argument-hint: <JIRA-KEY>
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, Agent
---

# design

기술 설계와 작업 분해를 통해 `design.md`를 작성합니다.

- Figma 참조가 있으면 구조와 UI 변경 근거를 명시합니다.
- 병렬 실행 가능 여부는 작업 단위별로 표시합니다.
- 입력 기준은 승인된 `plan.md` 입니다.
- 결과는 `design.md` draft 생성, `tasks.json` 생성, `approvals.design=false`, `phase=design-draft` 입니다.
- 승인 이후 `tasks.json`이 존재해야만 `implement`로 넘어갑니다.

## 구현 기준

- `hooks/lib/planning.sh`
- `planning-agent`

Primary agent: `planning-agent`
Support agent: `context-agent`
