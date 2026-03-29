# 레퍼런스 프로젝트 분석 보고서

분석 일자: 2026-03-27

## 분석 대상

1. [oh-my-openagent](https://github.com/code-yeongyu/oh-my-openagent)
2. [bkit-claude-code](https://github.com/popup-studio-ai/bkit-claude-code)
3. [superpowers](https://github.com/obra/superpowers)
4. [gstack](https://github.com/garrytan/gstack)
5. [get-shit-done](https://github.com/gsd-build/get-shit-done) (v1)
6. [gsd-2](https://github.com/gsd-build/gsd-2)

---

## 1. oh-my-openagent (omo)

### 개요
멀티모델 오케스트레이션을 지원하는 에이전트 하네스. Claude Code, OpenCode 등 다양한 런타임에서 동작하며, 여러 LLM 제공자를 오케스트레이션.

### 핵심 기능

| 기능 | 설명 |
|------|------|
| **Discipline Agents** | Sisyphus(오케스트레이터), Hephaestus(심층 작업), Prometheus(전략 계획), Oracle(아키텍처), Librarian(문서), Explore(탐색) |
| **`ultrawork`** | 원커맨드 실행 - 모든 에이전트 활성화 |
| **IntentGate** | 사용자 의도 분석 후 행동 분류 |
| **Hash-Anchored Edit Tool** | 라인 해시로 에디트 무결성 검증 (stale-line 에러 방지) |
| **LSP + AST-Grep** | IDE 수준의 정밀한 코드 조작 |
| **Background Agents** | 5+ 스페셜리스트 병렬 실행 |
| **Skill-Embedded MCPs** | 스킬이 자체 MCP 서버 탑재 |
| **Ralph Loop** | 자기참조 루프 - 100% 완료까지 반복 |
| **Todo Enforcer** | 에이전트가 멈추면 시스템이 강제로 재개 |
| **Tmux Integration** | 대화형 터미널 지원 |
| **`/init-deep`** | 계층적 AGENTS.md 자동 생성 |

### 도입 검토 사항
- [ ] Hash-Anchored Edit Tool - 매우 혁신적
- [ ] IntentGate - 의도 분석 레이어
- [ ] Background Agents - 병렬 에이전트 실행
- [ ] Todo Enforcer - 작업 완료 강제

---

## 2. bkit-claude-code

### 개요
PDCA 방법론 기반의 Context Engineering 시스템. 21개 에이전트, 28개 스킬, 208개 유틸리티 함수 제공.

### 핵심 기능

| 기능 | 설명 |
|------|------|
| **5-Layer Hook System** | hooks.json → Skill Frontmatter → Agent Frontmatter → Description Triggers → Scripts |
| **Skill Evals** | A/B 테스팅, 모델 패리티 테스트, 스킬 분류 (Workflow/Capability/Hybrid) |
| **CTO-Led Agent Teams** | CTO 에이전트가 병렬 PDCA 실행 오케스트레이션 |
| **PM Agent Team** | Plan 전 PRD 자동 생성 |
| **Output Styles** | bkit-learning, bkit-pdca-guide, bkit-enterprise 등 |
| **Agent Memory** | 세션 간 컨텍스트 지속 |
| **Check-Act Iteration Loop** | 90% 임계값 자동 반복 (최대 5회) |

### Skill Classification 체계
- **Workflow** (9개): 프로세스 자동화 - 품질 회귀만 측정
- **Capability** (18개): 모델 능력 증강 - 패리티 테스트
- **Hybrid** (1개): 둘 다

### 도입 검토 사항
- [ ] Skill Evals 프레임워크
- [ ] Output Styles
- [ ] Agent Memory (세션 간 지속)
- [ ] CTO-Led Teams 개념

---

## 3. superpowers

### 개요
TDD 중심의 에이전트 스킬 프레임워크. 체계적인 소프트웨어 개발 방법론 제공.

### 핵심 기능

| 기능 | 설명 |
|------|------|
| **Brainstorming** | 소크라테스식 설계 정제 |
| **Writing Plans** | 2-5분 단위의 상세 구현 계획 |
| **Subagent-driven-development** | 태스크별 fresh subagent 실행 |
| **Git Worktrees** | 병렬 개발 브랜치 |
| **Test-Driven Development** | RED-GREEN-REFACTOR 강제 |
| **Systematic Debugging** | 4단계 근본 원인 분석 |
| **Verification before Completion** | 완료 전 검증 |

### Workflow
```
brainstorming → using-git-worktrees → writing-plans →
subagent-driven-development → test-driven-development →
requesting-code-review → finishing-a-development-branch
```

### 도입 검토 사항
- [ ] Subagent-driven-development 패턴
- [ ] Brainstorming 스킬
- [ ] Git Worktrees 활용

---

## 4. gstack

### 개요
Garry Tan의 Claude Code 셋업. CEO, Designer, Eng Manager 등 6개 역할 기반 스킬 세트.

### Sprint Process
```
Think → Plan → Build → Review → Test → Ship → Reflect
```

### 핵심 스킬

| 스킬 | 역할 | 설명 |
|------|------|------|
| `/office-hours` | YC Office Hours | 6개 핵심 질문으로 제품 리프레임 |
| `/plan-ceo-review` | CEO/Founder | 10섹션 리뷰, 4가지 모드 |
| `/plan-eng-review` | Eng Manager | 아키텍처, 데이터 플로우, 다이어그램 |
| `/plan-design-review` | Senior Designer | 0-10 디자인 평가, AI Slop 감지 |
| `/review` | Staff Engineer | CI 통과 but 프로덕션 터지는 버그 탐지 |
| `/qa` | QA Lead | 실제 브라우저 테스트, 버그 수정 |
| `/cso` | Chief Security Officer | OWASP Top 10 + STRIDE 위협 모델 |
| `/ship` | Release Engineer | 테스트, 커버리지, PR 생성 |
| `/land-and-deploy` | Release Engineer | 머지 → CI → 배포 → 검증 |
| `/canary` | SRE | 배포 후 모니터링 루프 |
| `/benchmark` | Performance Engineer | 페이지 로드, Core Web Vitals |
| `/retro` | Eng Manager | 팀 인식 주간 회고 |

### Power Tools
- `/careful` - 위험 명령 경고
- `/freeze` - 파일 편집 디렉토리 제한
- `/guard` - careful + freeze

### Conductor
- 병렬 스프린트 실행
- 각 세션이 독립 워크스페이스에서 실행

### 도입 검토 사항
- [ ] `/retro` 회고 스킬
- [ ] `/cso` 보안 감사
- [ ] `/benchmark` 성능 베이스라인
- [ ] Power tools (careful, freeze, guard)
- [ ] `/ship` 배포 자동화

---

## 5. get-shit-done (GSD v1)

### 개요
Meta-prompting + Context Engineering + Spec-driven 개발 시스템.

### 핵심 기능

| 기능 | 설명 |
|------|------|
| **Wave Execution** | 의존성 기반 병렬/순차 계획 실행 |
| **Workstreams** | 병렬 마일스톤 작업 |
| **Multi-Project Workspaces** | Git worktrees/clones로 격리 |
| **UI Design Contracts** | UI-SPEC.md 생성 |
| **Brownfield Support** | 기존 코드베이스 분석 |
| **Session Management** | pause/resume, HANDOFF.json |
| **Quick Mode** | 경량 태스크 실행 |
| **Backlog & Threads** | 아이디어 캡처, 세션 간 컨텍스트 |
| **Seeds** | 조건부 아이디어 서피싱 |

### State Files
```
PROJECT.md | REQUIREMENTS.md | ROADMAP.md | STATE.md |
PLAN.md | SUMMARY.md | CONTEXT.md | RESEARCH.md
```

### 도입 검토 사항
- [ ] Wave Execution 패턴
- [ ] Workstreams 개념
- [ ] Quick Mode
- [ ] Session management (pause/resume)
- [ ] Seeds (조건부 아이디어)

---

## 6. gsd-2 (GSD v2)

### 개요
Pi SDK 기반 독립 CLI. 완전 자율 실행 지원.

### v1 대비 개선점

| 영역 | v1 | v2 |
|------|----|----|
| Runtime | 슬래시 커맨드 | 독립 CLI |
| Context | LLM에 의존 | 프로그래밍 제어 |
| Auto mode | LLM 자기 루프 | 상태 머신 |
| Crash recovery | 없음 | Lock 파일 + 세션 포렌식 |
| Cost tracking | 없음 | 단위별 토큰/비용 |
| Stuck detection | 없음 | 슬라이딩 윈도우 감지 |

### 핵심 기능

| 기능 | 설명 |
|------|------|
| **Auto Mode** | walk away, come back to built software |
| **Crash Recovery** | 세션 파일 복구, 지수 백오프 재시작 |
| **Provider Error Recovery** | 일시적 에러 자동 재시도, 모델 폴백 |
| **Stuck Detection** | 슬라이딩 윈도우 패턴 감지 |
| **Timeout Supervision** | soft/idle/hard 타임아웃 |
| **Cost Tracking** | 단위별, 모델별 비용 추적 |
| **Git Worktree Isolation** | 마일스톤별 독립 브랜치 |
| **Milestone Validation** | 로드맵 vs 실제 결과 비교 |
| **HTML Reports** | 자동 생성 보고서 |
| **Token Optimization** | 프로필별 40-60% 절감 |
| **Remote Questions** | Slack/Discord로 의사결정 라우팅 |
| **Web UI** | `gsd --web` 브라우저 인터페이스 |
| **Dynamic Model Routing** | 복잡도 기반 모델 선택 |

### 도입 검토 사항
- [ ] Crash recovery 메커니즘
- [ ] Stuck detection
- [ ] Timeout supervision
- [ ] Cost tracking
- [ ] HTML Reports
- [ ] Remote Questions (Slack/Discord)

---

## 종합 비교표

### 에이전트 비교

| 프로젝트 | 에이전트 수 | 주요 에이전트 |
|----------|------------|---------------|
| **omo** | 6+ | Sisyphus, Hephaestus, Prometheus, Oracle, Librarian, Explore |
| **bkit** | 21 | CTO, PM Team, Domain specialists |
| **superpowers** | 0 (스킬 중심) | - |
| **gstack** | 6+ (역할) | CEO, Designer, Eng Manager, QA, CSO, SRE |
| **GSD v1** | 4 | Orchestrator, Researcher, Planner, Executor |
| **GSD v2** | 3 | Scout, Researcher, Worker |
| **harness-engineering** | 6 | strategist, architect, engineer, guardian, librarian, debugger |

### 스킬 비교

| 프로젝트 | 스킬 수 | 주요 특징 |
|----------|---------|-----------|
| **omo** | ? | ultrawork, init-deep |
| **bkit** | 28 | Skill Evals, PDCA 통합 |
| **superpowers** | 12+ | TDD 강제, brainstorming |
| **gstack** | 28 | Sprint process, power tools |
| **GSD v1** | 30+ | Wave execution, quick mode |
| **GSD v2** | 19 extensions | Auto mode, remote questions |
| **harness-engineering** | 10 | PDCA 5단계, grill-me |

---

## 도입 우선순위 제안

### P0 - 즉시 도입 권장

1. **Power Tools** (gstack)
   - `/careful` - 위험 명령 경고
   - `/freeze` - 편집 범위 제한
   - `/guard` - 전체 안전

2. **회고 스킬** (gstack)
   - `/retro` - 팀 인식 주간 회고

3. **보안 감사** (gstack)
   - `/cso` - OWASP + STRIDE

### P1 - 단기 도입 검토

4. **Skill Evals** (bkit)
   - 스킬 품질 관리 프레임워크
   - A/B 테스팅, 패리티 테스트

5. **Crash Recovery** (gsd-2)
   - 세션 복구 메커니즘
   - Lock 파일 기반

6. **Stuck Detection** (gsd-2)
   - 슬라이딩 윈도우 패턴 감지

### P2 - 중기 도입 검토

7. **Hash-Anchored Edit Tool** (omo)
   - 라인 해시 기반 에디트 검증

8. **Wave Execution** (GSD)
   - 의존성 기반 병렬 실행

9. **Output Styles** (bkit)
   - 레벨별 응답 포맷

10. **Remote Questions** (gsd-2)
    - Slack/Discord 의사결정 라우팅

### P3 - 장기 검토

11. **Background Agents** (omo)
    - 병렬 에이전트 실행

12. **IntentGate** (omo)
    - 의도 분석 레이어

13. **HTML Reports** (gsd-2)
    - 마일스톤 완료 보고서

14. **Cost Tracking** (gsd-2)
    - 토큰/비용 추적

---

## 새 에이전트 제안

### 1. CSO (Chief Security Officer) - gstack 영감

```markdown
---
name: cso
description: OWASP Top 10 + STRIDE 위협 모델 기반 보안 감사
tools: read-only
---

역할:
- OWASP Top 10 취약점 스캔
- STRIDE 위협 모델링
- Zero-noise: 8/10+ 신뢰도 게이트
- 구체적 익스플로잇 시나리오 포함
```

### 2. QA Lead - gstack 영감

```markdown
---
name: qa
description: 실제 브라우저 테스트, 버그 탐지 및 수정
tools: full
---

역할:
- E2E 테스트 실행
- 버그 탐지 및 자동 수정
- 회귀 테스트 생성
- 테스트 매트릭스 작성
```

### 3. SRE - gstack 영감

```markdown
---
name: sre
description: 배포 후 모니터링, 카나리 배포
tools: full
---

역할:
- 카나리 배포 모니터링
- 성능 메트릭 수집
- 인시던트 대응
- SLO/SLI 정의
```

### 4. PM (Product Manager) - bkit 영감

```markdown
---
name: pm
description: 제품 요구사항 분석, PRD 생성
tools: read-only
---

역할:
- Opportunity Solution Tree 분석
- JTBD + Lean Canvas
- Personas, Competitors, TAM/SAM/SOM
- 8섹션 PRD 생성
```

---

## 새 스킬 제안

### 1. `/retro` - 회고

**출처**: gstack

```markdown
---
name: retro
description: 팀 인식 주간 회고
---

기능:
- 개인별 기여 분석
- 커밋/테스트 트렌드
- 성장 기회 식별
- JSON/마크다운 리포트
```

### 2. `/benchmark` - 성능 베이스라인

**출처**: gstack

```markdown
---
name: benchmark
description: 페이지 로드, Core Web Vitals 베이스라인
---

기능:
- 성능 메트릭 수집
- Before/After 비교
- 회귀 감지
```

### 3. `/ship` - 배포 자동화

**출처**: gstack

```markdown
---
name: ship
description: 테스트, 커버리지, PR 생성
---

기능:
- 테스트 실행
- 커버리지 감사
- PR 자동 생성
- 체인지로그 업데이트
```

### 4. `/careful`, `/freeze`, `/guard` - Power Tools

**출처**: gstack

```markdown
---
name: careful
description: 위험 명령 경고 (rm -rf, DROP TABLE, force-push)
---

---
name: freeze
description: 파일 편집 디렉토리 제한
---

---
name: guard
description: careful + freeze 전체 안전
---
```

### 5. `/brainstorm` - 브레인스토밍

**출처**: superpowers

```markdown
---
name: brainstorm
description: 소크라테스식 설계 정제
---

기능:
- 질문을 통한 아이디어 정제
- 대안 탐색
- 설계 문서 생성
- 청크 단위 검증
```

---

## 결론

6개 프로젝트 분석 결과, harness-engineering에 즉시 도입할 수 있는 주요 기능들:

1. **Power Tools** - 안전 장치 (careful, freeze, guard)
2. **CSO 에이전트** - 보안 감사
3. **QA 에이전트** - E2E 테스트
4. **`/retro` 스킬** - 회고
5. **`/benchmark` 스킬** - 성능 측정
6. **`/ship` 스킬** - 배포 자동화
7. **`/brainstorm` 스킬** - 설계 정제

이 기능들은 현재 harness-engineering의 PDCA 워크플로우와 잘 통합되며, 개발 생산성과 품질을 크게 향상시킬 수 있습니다.
