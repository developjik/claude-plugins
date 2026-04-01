---
name: route-workflow
description: Public entry controller for colo-fe-flow. Normalize the user's raw request, inspect local workflow state, produce a structured route result, and auto-select the next valid skill.
user-invocable: true
allowed-tools: Read, Grep, Glob, Bash, Agent
---

# route-workflow

모든 `colo-fe-flow` 요청의 첫 진입점입니다.

이 스킬은 worker가 아니라 controller입니다. 직접 문서를 쓰거나 코드를 수정하지 않고, 현재 상태에서 다음으로 실행해야 할 skill을 결정하는 역할만 맡습니다.

## 역할

- 사용자 자연어 요청을 받음
- 현재 active ticket과 명시적 Jira key를 해석함
- 자연어를 내부 `resolved_action` enum으로 정규화함
- `.colo-fe-flow/.state/`와 artifact 메타데이터를 읽어 `required_next_skill`을 계산함
- `decision=execute|redirect|block` 으로 판정함
- `route result JSON`을 만들고 다음 skill을 자동 선택함

## 하지 않는 일

- Jira, Confluence, Figma 데이터를 직접 수집하지 않음
- artifact 본문을 직접 작성하지 않음
- approval, verification, doc sync 같은 business state를 직접 변경하지 않음
- 구현, 검증, 문서 동기화를 대신 수행하지 않음

## 내부 흐름

```text
raw user request
-> route-workflow
-> intent normalizer
-> resolved_action
-> decision engine
-> route result JSON
-> short human explanation
-> next skill auto-select
```

## 구현 기준

실제 shell helper 계약은 아래 문서를 기준으로 합니다.

- `docs/route-workflow-contract.md`
- `hooks/lib/routing.sh`

현재 skeleton 구현에는 최소한 아래 함수가 있어야 합니다.

- `cff_routing_normalize_action`
- `cff_routing_extract_requested_ticket`
- `cff_routing_action_to_skill`
- `cff_routing_required_next_skill`
- `cff_routing_critical_revalidate`
- `cff_routing_route_result_json`

## 입력 원칙

- 사용자는 action enum을 직접 입력하지 않습니다.
- 내부에서는 자연어를 `resolved_action`으로 정규화합니다.
- 자연어 원문은 로그와 설명용으로만 쓰고, 상태 판정에는 직접 사용하지 않습니다.

## 출력 원칙

정식 계약은 구조화된 JSON입니다.

예시:

```json
{
  "raw_request": "이제 구현 들어가자",
  "resolved_action": "run_implement",
  "requested_ticket": null,
  "resolved_ticket": "FE-123",
  "current_phase": "design-approved",
  "decision": "execute",
  "next_skill": "implement",
  "reason_code": "ready_to_run_implement",
  "reason": "design 승인 완료, tasks.json 준비됨",
  "requires_user_input": false
}
```

## 판정 규칙

- 필수 MCP 선언이 없으면 `block`
- ticket context가 없고 utility 요청도 아니면 `block`
- utility 요청은 직접 실행 가능
- 일반 workflow 요청은 먼저 `required_next_skill`을 계산
- 요청 skill이 `required_next_skill`과 같으면 `execute`
- 더 뒤 단계를 요청했으면 `redirect`
- 중요한 전이에서는 file system 기준 `critical revalidation`을 한 번 더 수행

## 현재 Phase 2 범위

이 skeleton 단계에서는 아래까지만 보장합니다.

- 자연어를 최소 action enum으로 정규화
- state 기반 `required_next_skill` 계산
- `execute|redirect|block` 판정
- `route result JSON` 생성
- critical revalidation 골격

아직 이 단계에서 완전히 끝내지 않는 것:

- 모든 worker skill의 end-to-end 구현
- 모든 utility skill의 완전 구현
- 실제 hook 기반 자동 실행 연동

## 다음 단계

- Phase 3에서 `start-jira-ticket`와 `intake`를 연결
- Phase 4에서 `clarify -> plan -> design -> tasks.json`
- Phase 5에서 `implement -> check -> iterate -> sync-docs -> complete-ticket`
