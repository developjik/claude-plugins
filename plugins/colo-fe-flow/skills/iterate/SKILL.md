---
name: iterate
description: Re-enters implementation using failed check results and open gaps as the repair input.
user-invocable: true
argument-hint: <JIRA-KEY>
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, Agent
---

# iterate

실패한 `check` 결과를 기준으로 보정 작업을 준비하고 구현 루프로 다시 들어갑니다.

- 결과는 `iteration.*` 갱신과 `phase=iterating` 입니다.
- 보정 후에는 다시 `implement` 또는 `check`로 이어집니다.

## 구현 기준

- `hooks/lib/execution.sh`
- `implementation-agent`

Primary agent: `implementation-agent`
Support agent: `planning-agent`
