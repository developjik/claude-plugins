---
name: list-tickets
description: Lists locally tracked tickets and marks the active ticket.
user-invocable: true
allowed-tools: Read, Grep, Glob, Bash
---

# list-tickets

로컬 runtime state가 추적 중인 open ticket 목록을 보여줍니다.

- `index.json`을 기준으로 active ticket과 last ticket을 함께 확인합니다.
- 각 ticket의 phase/status를 같이 요약합니다.

## 구현 기준

- `hooks/lib/utility.sh`
- `cff_utility_list_tickets_json`
