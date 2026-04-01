# colo-fe-flow

Colo 사내 프론트엔드 개발용 Jira-first workflow orchestrator 플러그인입니다.

현재 스캐폴드 범위:

- `route-workflow` 기반 단계 라우팅 구조
- `start-jira-ticket` + `intake` 기반 ticket bootstrap 골격
- `clarify -> plan -> design -> tasks.json` planning chain 골격
- `implement -> check -> iterate -> sync-docs -> complete-ticket` execution loop 골격
- `show-ticket-status`, `list-tickets`, `switch-ticket` utility skill 골격
- 5개 agent의 입력/출력 계약과 skill handoff 규칙 강화
- session/tool/agent hook 기반 dependency check, stale reset, lifecycle logging
- Jira/Confluence/Figma/Codebase 컨텍스트 수집 전제
- 필수 MCP 선언: `atlassian`, `figma`
- `clarify -> plan -> design -> implement -> check -> sync-docs` 스킬 골격
- 5개 에이전트 골격
- hooks/lib 기반 런타임 구조

상세 설계 문서는 저장소 루트 `plans/` 아래 문서를 기준으로 합니다.

사람이 읽는 로컬 런타임 구조 설명은 `plugins/colo-fe-flow/docs/local-runtime-schema.md` 를 기준으로 합니다.
`route-workflow` 계약은 `plugins/colo-fe-flow/docs/route-workflow-contract.md` 를 기준으로 합니다.
artifact lifecycle은 `plugins/colo-fe-flow/docs/artifact-lifecycle.md` 를 기준으로 합니다.
skill 책임은 `plugins/colo-fe-flow/docs/skill-responsibility.md` 를 기준으로 합니다.
agent 책임은 `plugins/colo-fe-flow/docs/agent-responsibility.md` 를 기준으로 합니다.
구현 순서는 `plugins/colo-fe-flow/docs/implementation-phases.md` 를 기준으로 합니다.
실전 수동 검증은 `plugins/colo-fe-flow/docs/manual-test-checklist.md` 를 기준으로 합니다.
