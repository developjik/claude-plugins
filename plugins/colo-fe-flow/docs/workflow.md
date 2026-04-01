# Workflow

`colo-fe-flow`의 기본 목적은 Jira 티켓을 시작점으로 삼아, 필요한 컨텍스트를 보강하고 승인 게이트를 통과한 뒤 구현과 검증, 문서 동기화까지 강제하는 것입니다.

`route-workflow`의 상세 계약은 [route-workflow-contract.md](./route-workflow-contract.md) 를 기준으로 봅니다.

## Main Flow

```mermaid
flowchart TD
    U[User request] --> R[route-workflow]

    R --> S{Ticket state exists?}
    S -- No --> TS[start-jira-ticket]
    S -- Yes --> P{Current phase}

    TS --> J[Read Jira ticket]
    J --> X[Collect Confluence, Figma, GitHub links]
    X --> C[Analyze local codebase]
    C --> W[Create ticket worktree and branch]
    W --> I[Generate intake.md]
    I --> IA[Developer approval]

    IA --> CL[Generate clarify.md]
    CL --> CA[Developer approval]

    CA --> PL[Generate plan.md]
    PL --> PA[Developer approval]

    PA --> DG[Generate design.md]
    DG --> DA[Developer approval]

    DA --> TD[Decompose implementation into atomic tasks]
    TD --> IM[Implement with TDD]

    IM --> CH[Run check]
    CH --> GAP{Check failed or open_gaps > 0?}

    GAP -- Yes --> IT[Iterate]
    IT --> IM

    GAP -- No --> DS[Doc sync]
    DS --> DOC[Update wrapup.md and affected local docs]
    DOC --> DONE[Done]

    P -->|Missing intake| TS
    P -->|Need clarify| CL
    P -->|Need plan| PL
    P -->|Need design| DG
    P -->|design-approved| IM
    P -->|Need check| CH
    P -->|Need sync-docs| DS
    P -->|All complete| DONE
```

## Intent

- Entry point is always `route-workflow`.
- Work starts from Jira and is enriched by Confluence, Figma, and the local codebase.
- `clarify -> plan -> design -> implement -> check -> iterate -> sync-docs` is enforced.
- Stage jumping is blocked.
- `done` is forbidden before verification and local docs sync.

## Agents

- `intake-agent`: reads Jira, Confluence, and Figma references and normalizes ticket context.
- `context-agent`: inspects the codebase, related modules, components, routes, and tests.
- `planning-agent`: writes `clarify.md`, `plan.md`, `design.md`, and `wrapup.md`.
- `implementation-agent`: implements from `design.md` using atomic tasks and TDD.
- `check-agent`: verifies implementation against `plan.md` and `design.md`, and reports gaps.

## Implementation Flow

Implementation is not treated as one large step. It is decomposed into small atomic tasks, and only explicitly safe tasks are allowed to run in parallel.

```mermaid
flowchart LR
    D[design-approved] --> T[tasks.json generated from plan.md and design.md]
    T --> F{parallel_safe and no file conflict?}

    F -- No --> SQ[Run sequentially]
    F -- Yes --> PX[Run in limited parallel groups]

    SQ --> T1[write_test]
    PX --> T1

    T1 --> T2[run_test_fail]
    T2 --> T3[write_code]
    T3 --> T4[run_test_pass]
    T4 --> T5[refactor]
    T5 --> T6[run_regression]
    T6 --> V[Mark task done]
    V --> C[check]
```

## Router Rules

- If there is no ticket state, route to `start-jira-ticket`.
- If `intake.md` exists but `clarify.md` does not, route to `clarify`.
- If `clarify.md` exists but clarify is not approved, stay in `clarify`.
- If `plan.md` is missing or unapproved, route to or stay in `plan`.
- If `design.md` is missing or unapproved, route to or stay in `design`.
- If design is approved but `tasks.json` is missing, stay in `design` until execution tasks are generated.
- If design is approved and `tasks.json` exists, `implement` is allowed.
- After implementation, `check` is mandatory.
- If the last check failed or `open_gaps > 0`, route to `iterate`.
- If check passed but `wrapup.md` or affected docs are not updated, route to `sync-docs`.
- Only after verification passes and docs sync is complete can the ticket move to `done`.

## State And Artifacts

Router decisions depend on file state under `.colo-fe-flow/.state/` and artifact presence under `docs/specs/<JIRA-KEY>/`.

### Runtime State

- `.colo-fe-flow/.state/index.json`
- `.colo-fe-flow/.state/tickets/<JIRA-KEY>.json`

### Required Artifacts

- `intake.md`
- `clarify.md`
- `plan.md`
- `design.md`
- `tasks.json`
- `check.md`
- `wrapup.md`

## Completion Criteria

The workflow is complete only when all of the following are true:

- `design` approval is finished.
- Implementation is finished.
- Class A checks pass.
- Class B checks pass.
- Class D checks pass.
- `check.md` reports `open_gaps = 0`.
- `wrapup.md` exists.
- Affected local `docs/` files are updated.
