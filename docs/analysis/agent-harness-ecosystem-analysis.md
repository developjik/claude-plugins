# AI 코딩 에이전트 하네스 생태계 분석 보고서

**분석 일자:** 2026-03-28
**대상 레포지토리:** 5개 주요 AI 코딩 에이전트 하네스

---

## 1. 개요

본 분석은 주요 AI 코딩 에이전트 하네스 프로젝트들을 비교하여, 각각의 철학, 아키텍처, 핵심 기능을 파악하기 위해 수행되었습니다.

### 분석 대상

| 프로젝트 | 스타 | 포크 | 핵심 철학 |
|---------|------|------|----------|
| **bkit** | - | - | PDCA 방법론 + Context Engineering |
| **superpowers** | - | - | TDD + Subagent-Driven Development |
| **gstack** | - | - | 가상 엔지니어링 팀 (CEO/Designer/QA) |
| **GSD** | 43.5k | 3.5k | Spec-Driven Development + Context Rot 해결 |
| **oh-my-openagent** | - | - | Discipline Agents + Multi-Model Orchestration |

---

## 2. 상세 분석

### 2.1 bkit (popup-studio-ai/bkit-claude-code)

**핵심 컨셉:** "Context Engineering의 실질적 구현"

#### 아키텍처 (5-Layer Hook System)
```
Layer 1: hooks.json (Global)
Layer 2: Skill Frontmatter
Layer 3: Agent Frontmatter
Layer 4: Description Triggers
Layer 5: Scripts (45 modules)
```

#### 구성 요소
- **28 Skills** - 도메인별 지식
- **21 Agents** - 역할 기반 제약 + 모델 선택 (opus/sonnet/haiku)
- **208 Functions** - 상태 관리, 의도 감지, 모호성 스코어링
- **45 Scripts** - Node.js 실행 로직

#### 핵심 기능
1. **PDCA 방법론** - Plan → Design → Do → Check → Act 사이클
2. **CTO-Led Agent Teams** - 병렬 PDCA 실행 (Dynamic: 3, Enterprise: 5 에이전트)
3. **Skill Evals** - 스킬 품질 관리 시스템 (A/B 테스트, 패리티 테스트)
4. **Context Engineering** - 체계적인 컨텍스트 관리

#### 철학
> "Process over output. Verification over trust. Context over prompts. Constraints over features."

#### Skill 분류
| 분류 | 수량 | 목적 |
|------|------|------|
| Workflow | 9 | 프로세스 자동화 (PDCA, 파이프라인) |
| Capability | 18 | 모델 능력 확장 |
| Hybrid | 1 | 프로세스 + 능력 |

---

### 2.2 Superpowers (obra/superpowers)

**핵심 컨셉:** "Subagent-Driven Development"

#### 워크플로우
```
brainstorming → using-git-worktrees → writing-plans
    → subagent-driven-development → test-driven-development
    → requesting-code-review → finishing-a-development-branch
```

#### Skills 라이브러리
**Testing**
- `test-driven-development` - RED-GREEN-REFACTOR 사이클

**Debugging**
- `systematic-debugging` - 4단계 근본 원인 분석
- `verification-before-completion`

**Collaboration**
- `brainstorming` - 소크라테스식 설계 정제
- `writing-plans` - 상세 구현 계획
- `executing-plans` - 체크포인트 배치 실행
- `dispatching-parallel-agents`
- `subagent-driven-development` - 2단계 리뷰 (스펙 준수 → 코드 품질)
- `using-git-worktrees` - 병렬 개발 브랜치

**Meta**
- `writing-skills` - 새 스킬 생성 가이드

#### 철학
- **Test-Driven Development** - 항상 테스트 먼저
- **Systematic over ad-hoc** - 추측 대신 프로세스
- **Complexity reduction** - 단순성이 주요 목표
- **Evidence over claims** - 성공 선언 전 검증

#### 특징
- Claude Code, Cursor, Codex, OpenCode, Gemini CLI 멀티 플랫폼 지원
- 공식 Claude 플러그인 마켓플레이스 등록

---

### 2.3 gstack (garrytan/gstack)

**핵심 컨셉:** "가상 엔지니어링 팀" - Garry Tan(YC CEO)의 개인 설정

#### 스프린트 구조
```
Think → Plan → Build → Review → Test → Ship → Reflect
```

#### 28 Skills (20 Specialists + 8 Power Tools)

**Specialists**
| 스킬 | 역할 | 기능 |
|------|------|------|
| `/office-hours` | YC Office Hours | 6개 핵심 질문으로 제품 리프레이밍 |
| `/plan-ceo-review` | CEO/Founder | 10-star 제품 발견 |
| `/plan-eng-review` | Eng Manager | 아키텍처, 데이터 플로우, 다이어그램 |
| `/plan-design-review` | Senior Designer | 디자인 차원 0-10 평가 |
| `/design-consultation` | Design Partner | 완전한 디자인 시스템 구축 |
| `/review` | Staff Engineer | CI 통과 후 프로덕션 버그 발견 |
| `/investigate` | Debugger | 체계적 근본 원인 디버깅 |
| `/design-review` | Designer Who Codes | 감사 + 수정 |
| `/qa` | QA Lead | 실제 브라우저 테스트 + 자동 수정 |
| `/qa-only` | QA Reporter | 버그 리포트만 (코드 수정 없음) |
| `/cso` | Chief Security Officer | OWASP Top 10 + STRIDE 위협 모델 |
| `/ship` | Release Engineer | 테스트, 커버리지 감사, PR 생성 |
| `/land-and-deploy` | Release Engineer | 승인 → 프로덕션 검증 |
| `/canary` | SRE | 배포 후 모니터링 루프 |
| `/benchmark` | Performance Engineer | Core Web Vitals 베이스라인 |
| `/document-release` | Technical Writer | 문서 자동 업데이트 |
| `/retro` | Eng Manager | 팀 단위 주간 회고 |
| `/browse` | QA Engineer | 실제 Chromium 브라우저 |
| `/setup-browser-cookies` | Session Manager | 쿠키 가져오기 |
| `/autoplan` | Review Pipeline | CEO → design → eng 리뷰 자동화 |

**Power Tools**
| 스킬 | 기능 |
|------|------|
| `/codex` | OpenAI Codex CLI 독립 리뷰 |
| `/careful` | 파괴적 명령 경고 |
| `/freeze` | 디렉토리 편집 잠금 |
| `/guard` | `/careful` + `/freeze` |
| `/unfreeze` | 잠금 해제 |
| `/setup-deploy` | 배포 설정 |
| `/gstack-upgrade` | 자동 업데이트 |

#### 핵심 특징
- **실제 브라우저 모드** - `$B connect`로 실제 Chrome 제어
- **Sidebar Agent** - Chrome 사이드 패널에서 자연어 명령
- **Multi-AI Second Opinion** - `/codex`로 OpenAI 독립 리뷰
- **10-15 병렬 스프린트** - Conductor로 다중 세션 관리

#### 철학
> "This is my open source software factory. I use it every day."

---

### 2.4 GSD - Get Shit Done (gsd-build/get-shit-done)

**핵심 컨셉:** "Context Rot 해결 + Spec-Driven Development"

**규모:** 43.5k 스타, 3.5k 포크 - 가장 인기 있는 하네스

#### 워크플로우
```
new-project → discuss-phase → plan-phase → execute-phase → verify-work → ship
```

#### 핵심 문제 해결
> "Solves context rot — the quality degradation that happens as Claude fills its context window."

#### 아키텍처

**Context Engineering Layer**
| 파일 | 역할 |
|------|------|
| `PROJECT.md` | 프로젝트 비전 |
| `research/` | 생태계 지식 |
| `REQUIREMENTS.md` | v1/v2 범위 요구사항 |
| `ROADMAP.md` | 진행 상황 |
| `STATE.md` | 결정, 블로커, 위치 |
| `PLAN.md` | XML 구조 원자적 태스크 |
| `SUMMARY.md` | 변경 사항 |
| `todos/` | 나중에 할 아이디어 |
| `threads/` | 세션 간 지속 컨텍스트 |
| `seeds/` | 적절한 마일스톤에 표면화되는 아이디어 |

**Wave Execution**
```
WAVE 1 (parallel)    WAVE 2 (parallel)    WAVE 3
┌─────────┐ ┌─────┐    ┌─────────┐ ┌─────┐    ┌─────────┐
│ Plan 01 │ │Plan│ →  │ Plan 03 │ │Plan│ →  │ Plan 05 │
│ Plan 02 │ │   │    │ Plan 04 │ │   │    │         │
└─────────┘ └─────┘    └─────────┘ └─────┘    └─────────┘
```

**XML Prompt Formatting**
```xml
<task type="auto">
  <name>Create login endpoint</name>
  <files>src/app/api/auth/login/route.ts</files>
  <action>Use jose for JWT...</action>
  <verify>curl -X POST localhost:3000/api/auth/login...</verify>
  <done>Valid credentials return cookie</done>
</task>
```

#### 멀티 에이전트 오케스트레이션
| 단계 | 오케스트레이터 | 에이전트 |
|------|---------------|---------|
| Research | 조율, 발표 | 4개 병렬 연구원 |
| Planning | 검증, 반복 관리 | Planner, Checker |
| Execution | Wave 그룹화, 추적 | 병렬 Executor (각 200k 컨텍스트) |
| Verification | 발표, 라우팅 | Verifier, Debuggers |

#### 주요 명령어
| 명령 | 기능 |
|------|------|
| `/gsd:new-project` | 질문 → 연구 → 요구사항 → 로드맵 |
| `/gsd:discuss-phase` | 구현 결정 캡처 |
| `/gsd:plan-phase` | 연구 + 계획 + 검증 |
| `/gsd:execute-phase` | 병렬 Wave 실행 |
| `/gsd:verify-work` | 수동 UAT |
| `/gsd:ship` | PR 생성 |
| `/gsd:quick` | ad-hoc 태스크 |
| `/gsd:next` | 자동 다음 단계 |

#### 멀티 런타임 지원
- Claude Code, OpenCode, Gemini CLI, Codex, Copilot, Cursor, Windsurf, Antigravity

#### 철학
> "No enterprise roleplay bullshit. Just an incredibly effective system for building cool stuff consistently."

---

### 2.5 oh-my-openagent (code-yeongyu/oh-my-openagent)

**핵심 컨셉:** "Discipline Agents + Multi-Model Orchestration"

**이전 명칭:** oh-my-opencode

#### 핵심 기능

**`ultrawork` / `ulw`**
> 한 단어로 모든 에이전트 활성화. 완료될 때까지 멈추지 않음.

**Discipline Agents**
| 에이전트 | 모델 | 역할 |
|---------|------|------|
| **Sisyphus** | claude-opus-4-6 / kimi-k2.5 / glm-5 | 메인 오케스트레이터 |
| **Hephaestus** | gpt-5.4 | 자율 딥 워커 ("The Legitimate Craftsman") |
| **Prometheus** | claude-opus-4-6 / kimi-k2.5 / glm-5 | 전략적 플래너 |

**Agent Orchestration Categories**
| 카테고리 | 용도 |
|---------|------|
| `visual-engineering` | 프론트엔드, UI/UX |
| `deep` | 자율 연구 + 실행 |
| `quick` | 단일 파일 변경 |
| `ultrabrain` | 하드 로직, 아키텍처 |

#### 혁신 기능

**Hash-Anchored Edit Tool (Hashline)**
> "The harness problem is real. Most agent failures aren't the model. It's the edit tool."

```
11#VK| function hello() {
22#XJ|   return "world";
33#MB| }
```

- Grok Code Fast 1: 6.7% → 68.3% 성공률 향상

**Skill-Embedded MCPs**
- 스킬이 자체 MCP 서버 포함
- 온디맨드 실행, 태스크 범위, 완료 후 제거

**LSP + AST-Grep**
- `lsp_rename`, `lsp_goto_definition`, `lsp_find_references`, `lsp_diagnostics`
- 25개 언어 패턴 인식 코드 검색/재작성

**Deep Initialization (`/init-deep`)**
- 계층적 `AGENTS.md` 파일 자동 생성

**Ralph Loop / `/ulw-loop`**
- 자기 참조 루프. 100% 완료까지 멈추지 않음.

#### Claude Code 호환성
> "Every hook, command, skill, MCP, plugin works here unchanged."

#### 철학
> "We ride every model. Claude / Kimi / GLM for orchestration. GPT for reasoning. Minimax for speed. Gemini for creativity."

---

## 3. 비교 매트릭스

### 3.1 철학 비교

| 프로젝트 | 핵심 철학 | 타겟 사용자 |
|---------|----------|------------|
| **bkit** | PDCA 방법론, Context Engineering | 숙련 개발자, 엔터프라이즈 |
| **superpowers** | TDD, 체계적 디버깅 | TDD 실천자 |
| **gstack** | 가상 팀, 실용적 스프린트 | 창업자, CEO |
| **GSD** | Spec-Driven, Context Rot 해결 | 솔로 개발자 |
| **oh-my-openagent** | Multi-Model, Discipline | 오픈소스 애호가 |

### 3.2 기능 비교

| 기능 | bkit | superpowers | gstack | GSD | oh-my-openagent |
|------|------|-------------|--------|-----|-----------------|
| **PDCA/워크플로우** | ✅ 28 Skills | ✅ 12 Skills | ✅ 28 Skills | ✅ 40+ Commands | ✅ Skills |
| **Multi-Agent** | ✅ CTO Team | ✅ Subagent | ✅ 10-15 Parallel | ✅ Wave Execution | ✅ Discipline Agents |
| **TDD 강제** | ❌ | ✅ | ❌ | ❌ | ❌ |
| **Context Rot 해결** | ✅ CE Layer | ❌ | ❌ | ✅ Core Feature | ✅ |
| **브라우저 테스트** | ❌ | ❌ | ✅ Real Chrome | ❌ | ✅ Playwright |
| **Multi-Model** | ❌ Claude Only | ❌ | ❌ Claude Only | ❌ | ✅ 5+ Models |
| **Multi-Platform** | ❌ Claude Only | ✅ 5+ | ✅ 5+ | ✅ 8+ | ✅ OpenCode |
| **XML 포맷팅** | ❌ | ❌ | ❌ | ✅ | ❌ |
| **LSP/AST** | ❌ | ❌ | ❌ | ❌ | ✅ |
| **Security** | ❌ | ❌ | ✅ OWASP+STRIDE | ✅ Hardened | ❌ |

### 3.3 아키텍처 비교

| 프로젝트 | 아키텍처 | 상태 관리 | 확장성 |
|---------|---------|----------|--------|
| **bkit** | 5-Layer Hook | 208 Functions | Skills/Agents |
| **superpowers** | Skills Framework | Git Worktrees | Skills |
| **gstack** | Skills + Tools | In-Memory | Skills |
| **GSD** | Multi-Agent Orchestrator | STATE.md + threads | Commands/Agents |
| **oh-my-openagent** | Skills + MCPs | Agent State | Skills/Embedded MCPs |

---

## 4. 인사이트

### 4.1 공통 패턴

1. **모든 하네스가 "프로세스"를 강조**
   - bkit: PDCA
   - superpowers: TDD + Subagent-Driven
   - gstack: Sprint 구조
   - GSD: Spec-Driven Wave Execution
   - oh-my-openagent: Discipline Agents

2. **Multi-Agent가 표준**
   - 단일 에이전트 대신 전문화된 에이전트 팀
   - 병렬 실행으로 속도 향상

3. **Context Rot이 핵심 문제**
   - GSD가 명시적으로 해결
   - bkit은 Context Engineering으로 접근
   - oh-my-openagent는 fresh context 유지

4. **Skills/Commands 체계**
   - 모든 하네스가 확장 가능한 스킬 시스템 채택

### 4.2 차별화 포인트

| 프로젝트 | 독특한 특징 |
|---------|------------|
| **bkit** | 가장 정교한 Context Engineering, Skill Evals |
| **superpowers** | TDD 강제, Git Worktrees |
| **gstack** | 실제 브라우저 제어, YC Office Hours 스타일 |
| **GSD** | XML 포맷팅, Wave Execution, 가장 높은 인기 |
| **oh-my-openagent** | Multi-Model, Hash-Anchored Edits, LSP/AST |

### 4.3 선택 가이드

| 사용자 유형 | 추천 하네스 | 이유 |
|------------|------------|------|
| **엔터프라이즈 팀** | bkit | PDCA, Skill Evals, Context Engineering |
| **TDD 실천자** | superpowers | RED-GREEN-REFACTOR 강제 |
| **창업자/CEO** | gstack | 가상 팀, 실용적 스프린트 |
| **솔로 개발자** | GSD | 가장 인기, Context Rot 해결 |
| **오픈소스 애호가** | oh-my-openagent | Multi-Model, LSP/AST |

---

## 5. harness-engineering 프로젝트에 대한 시사점

### 5.1 채택 고려사항

1. **Context Engineering** (bkit)
   - 5-Layer Hook 시스템 참고
   - Skill Evals로 스킬 품질 관리

2. **TDD 강제** (superpowers)
   - RED-GREEN-REFACTOR 사이클 통합 고려

3. **브라우저 테스트** (gstack)
   - 실제 Chrome 제어로 QA 자동화

4. **Wave Execution** (GSD)
   - 의존성 기반 병렬 실행

5. **Multi-Model** (oh-my-openagent)
   - 태스크 유형별 모델 라우팅

### 5.2 차별화 기회

1. **통합 하네스** - 각 하네스의 장점 결합
2. **한국어 최적화** - 대부분 영어 중심
3. **Security-First** - gstack의 OWASP+STRIDE 확장
4. **Hybrid Multi-Model** - oh-my-openagent + bkit 결합

---

## 6. 결론

AI 코딩 에이전트 하네스 생태계는 빠르게 진화하고 있으며, 각 프로젝트는 명확한 철학과 타겟 사용자를 가지고 있습니다.

- **bkit**: 엔터프라이즈급 Context Engineering
- **superpowers**: TDD 중심 체계적 개발
- **gstack**: 창업자를 위한 가상 팀
- **GSD**: 솔로 개발자를 위한 Spec-Driven
- **oh-my-openagent**: Multi-Model 오픈소스

harness-engineering 프로젝트는 이들의 장점을 취하고, 한국어 최적화와 보안 강화로 차별화할 수 있습니다.
