---
name: switch-ticket
description: Safely switches the active ticket to another known local ticket.
user-invocable: true
argument-hint: <JIRA-KEY>
allowed-tools: Read, Write, Bash, Grep, Glob
---

# switch-ticket

현재 active ticket을 다른 로컬 ticket으로 전환합니다.

- 대상 ticket이 로컬 state에 존재하는지 먼저 확인합니다.
- 성공하면 `index.json.active_ticket`과 `last_ticket`이 갱신됩니다.

## 구현 기준

- `hooks/lib/utility.sh`
- `cff_utility_switch_ticket`
