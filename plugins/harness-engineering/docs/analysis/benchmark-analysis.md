# Benchmark Analysis: Claude Code 플러그인 비교 분석

> 분석 일자: 2026-03-24
> 분석 대상: superpowers, bkit-claude-code, gstack, get-shit-done

---

## 목차

1. [개요](#1-개요)
2. [레포지토리 상세 분석](#2-레포지토리-상세-분석)
   - [Superpowers](#21-superpowers---obra)
   - [bkit](#22-bkit---popup-studio-ai)
   - [gstack](#23-gstack---garrytan)
   - [GSD](#24-get-shit-done---gsd-build)
3. [비교 매트릭스](#3-비교-매트릭스)
4. [도입 제안](#4-도입-제안)
5. [우선순위 로드맵](#5-우선순위-로드맵)
6. [구현 가이드](#6-구현-가이드)

---

## 1. 개요

본 문서는 4개의 주요 Claude Code 플러그인/프레임워크를 분석하고, 현재 harness-engineering 프로젝트에 적용할 수 있는 개선점을 정리합니다.

### 분석 대상

| 프로젝트 | 개발자 | 핵심 컨셉 |
|----------|--------|-----------|
| Superpowers | obra | TDD 기반 스킬 프레임워크 |
| bkit | popup-studio-ai | 컨텍스트 엔지니어링 OS |
| gstack | garrytan (YC CEO) | 가상 엔지니어링 팀 |
| GSD | gsd-build | Context Rot 해결 |

---

## 2. 레포지토리 상세 분석

### 2.1 Superpowers - obra

**GitHub**: https://github.com/obra/superpowers

#### 개요
TDD(Test-Driven Development) 원칙을 스킬 작성에 적용한 에이전트 스킬 프레임워크입니다.

#### 핵심 철학
- **조기 구현 방지**: 코드 작성 전 요구사항 이해 우선
- **체계적 프로세스 강제**: 선택 아닌 필수 워크플로우
- **단순성 우선**: 복잡성 최소화

#### 주요 컴포넌트

**스킬 시스템 (~15개 스킬)**

| 카테고리 | 스킬 | 설명 |
|----------|------|------|
| Testing | test-driven-development | RED-GREEN-REFACTOR 강제 |
| Debugging | systematic-debugging | 4단계 근본 원인 분석 |
| | verification-before-completion | 수정 완료 검증 |
| Collaboration | brainstorming | 구현 전 소크라테스식 설계 |
| | writing-plans | 정확한 파일 경로 포함 계획 |
| | subagent-driven-development | 2단계 리뷰로 빠른 반복 |
| | dispatching-parallel-agents | 동시 서브에이전트 워크플로우 |
| Meta | writing-skills | 새 스킬 작성 가이드 |

**7단계 필수 워크플로우**
```
1. Brainstorming → 코드 전 아이디어 정제
2. Git Worktrees → 격리된 워크스페이스 생성
3. Writing Plans → 2-5분 단위 태스크 분해
4. Subagent-Driven Development → 태스크별 신선한 서브에이전트
5. Test-Driven Development → RED-GREEN-REFACTOR
6. Requesting Code Review → 계획 대비 리뷰
7. Finishing Development Branch → 테스트 검증, 머지 옵션
```

#### 혁신적 패턴

**1. TDD 기반 스킬 작성**
```
RED   → 서브에이전트로 실패 테스트 작성 (기준 동작)
GREEN → 특정 위반을 해결하는 최소 스킬 작성
REFACTOR → 규칙 준수하며 허점 폐쇄
```

**2. Claude Search Optimization (CSO)**
- 트리거 조건에 중점을 둔 풍부한 description
- 에러 메시지 및 증상에 대한 키워드 커버리지
- 150단어 이내 토큰 효율성

**3. Anti-Rationalization 설계**
- 특정 우회 방법 명시적 금지
- 기준 테스트에서 합리화 테이블 구축
- "정신 vs 문자" 논쟁 사전 대응

#### 기술 스택
- 포맷: Markdown + YAML frontmatter
- 다이어그램: Graphviz (dot)
- 지원 플랫폼: Claude Code, Cursor, Codex, OpenCode, Gemini CLI

---

### 2.2 bkit - popup-studio-ai

**GitHub**: https://github.com/popup-studio-ai/bkit-claude-code

#### 개요
"AI Native Development OS"를 표방하는 가장 포괄적인 Claude Code 플러그인입니다.

#### 핵심 철학
1. **Automation First** - Claude가 자동으로 PDCA 적용
2. **No Guessing** - 문서 확인 또는 사용자 질문, 추측 금지
3. **Docs = Code** - 설계 우선, 구현은 나중

#### 규모

| 구성요소 | 수량 |
|----------|------|
| 스킬 | 36개 |
| 에이전트 | 31개 (10 Opus, 19 Sonnet, 2 Haiku) |
| 훅 이벤트 | 18개 |
| 라이브러리 모듈 | 76개 (~465 exports) |
| 테스트 케이스 | 3,298개 |
| MCP 서버 | 2개 |

#### 6계층 컨텍스트 엔지니어링

```
Layer 1: hooks.json (18 events)
Layer 2: Skill/Agent Frontmatter
Layer 3: Description Triggers (8-language)
Layer 4: Scripts (21 Node.js modules)
Layer 5: Lib Modules (76 modules)
Layer 6: Plugin Data Backup
```

#### 핵심 기능

**1. 선언적 PDCA 상태 머신**
- 20개 상태 전이, 9개 가드
- YAML 정의 워크플로우 프리셋 (default, enterprise, hotfix)
- 체크포인트/롤백 지원

**2. 제어 가능한 AI (L0-L4)**

| 레벨 | 이름 | 설명 |
|------|------|------|
| L0 | Manual | 사용자 주도 |
| L1 | Guided | 제안 후 사용자 승인 |
| L2 | Semi-Auto | 일반 자동, 중요 결정은 사용자 승인 |
| L3 | Auto | 품질 게이트 통과 시 자동 |
| L4 | Full-Auto | 최대 자동화, 사용자 감독 |

**3. 신뢰 점수 시스템**
```
trust_score = (track_record × 0.25)
            + (quality_metrics × 0.20)
            + (velocity × 0.15)
            + (user_ratings × 0.20)
            + (decision_accuracy × 0.10)
            + (safety × 0.10)
```

**4. PM 에이전트 팀**
- 5개 에이전트가 43개 PM 프레임워크 실행
- 구조화된 제품 발견 프로세스

**5. 품질 게이트**
- 7개 품질 게이트
- 메트릭 수집기
- JSONL 감사 로깅

#### 기술 스택
- 런타임: Node.js v18+
- MCP 서버: bkit-pdca, bkit-analysis
- 포맷: JSON, YAML, JSONL
- 지원: Claude Code v2.1.78+

---

### 2.3 gstack - garrytan

**GitHub**: https://github.com/garrytan/gstack

#### 개요
Y Combinator CEO Garry Tan이 만든 AI 엔지니어링 파워 스택으로, Claude Code를 20명 전문가로 구성된 가상 엔지니어링 팀으로 변환합니다.

#### 핵심 성과
- **하루 10,000-20,000줄 코드** (파트타임)
- **60일간 600,000+줄 프로덕션 코드**
- **압축 비율**: 3x (연구) ~ 100x (보일러플레이트)

#### 스킬 시스템 (25+ 스킬)

**코어 워크플로우**
| 스킬 | 설명 |
|------|------|
| `/office-hours` | YC 오피스 아워 진단 |
| `/plan-ceo-review` | 제품 전략 및 범위 정의 |
| `/plan-eng-review` | 아키텍처 및 기술 설계 |
| `/plan-design-review` | 디자인 품질 평가 |
| `/autoplan` | CEO → Design → Eng 순차 파이프라인 |
| `/review` | 프로덕션급 코드 리뷰 + 자동 수정 |
| `/qa` | 자동화된 테스트 + 반복 버그 수정 |
| `/ship` | 릴리스 워크플로우 + PR 생성 |
| `/land-and-deploy` | Merge → Deploy → Verify 파이프라인 |

**전문가 스킬**
| 스킬 | 설명 |
|------|------|
| `/browse` | 고속 헤드리스 브라우저 (~100ms/command) |
| `/cso` | 보안 책임자 (OWASP + STRIDE 감사) |
| `/benchmark` | 성능 회귀 감지 |
| `/canary` | 배포 후 모니터링 |
| `/retro` | 엔지니어링 회고 |

**파워 툴**
| 스킬 | 설명 |
|------|------|
| `/freeze` | 편집 범위 잠금 |
| `/guard` | 최대 안전 모드 |
| `/careful` | 파괴적 명령 경고 |
| `/codex` | 멀티 AI 세컨드 오피니언 |

#### 혁신적 패턴

**1. 병렬 스프린트**
```
Session 1: /office-hours
Session 2: /review
Session 3: Feature implementation
Session 4: /qa
```
→ 여러 Claude Code 세션이 격리된 워크스페이스에서 동시 실행

**2. 멀티 모델 합의**
```
/autoplan 실행 시:
1. 원본 모델 (CEO/Design/Eng)
2. Codex 챌린지
3. Claude 서브에이전트
→ 결과 비교로 취향 결정 표면화
```

**3. LLM-as-Judge 평가**
- 스킬 출력 품질을 LLM으로 자동 평가
- 버그 감지율 측정
- 신뢰도 점수

**4. 3단계 테스트 인프라**

| 단계 | 비용 | 시간 | 설명 |
|------|------|------|------|
| Tier 1 | 무료 | <2s | 스킬 검증, 템플릿 품질 |
| Tier 2 | ~$3.85 | - | E2E 테스트 (claude -p) |
| Tier 3 | ~$0.15 | - | LLM-as-judge 품질 평가 |

#### 기술 스택
- 런타임: Bun
- 브라우저: Playwright
- 언어: TypeScript
- 테스트: Jest
- 인프라: Docker, GitHub Actions, Supabase

---

### 2.4 Get Shit Done - gsd-build

**GitHub**: https://github.com/gsd-build/get-shit-done

#### 개요
Context Rot(컨텍스트 윈도우 품질 저하) 문제를 해결하는 메타 프롬프팅 및 스펙 기반 개발 시스템입니다.

#### 핵심 문제 해결
**Context Rot**: Claude가 컨텍스트 윈도우를 채울 때 발생하는 품질 저하
→ 신선한 컨텍스트로 작업 실행하여 해결

#### 커맨드 시스템 (40+ 커맨드)

**코어 워크플로우**
| 커맨드 | 설명 |
|--------|------|
| `/gsd:new-project` | 전체 프로젝트 초기화 |
| `/gsd:discuss-phase [N]` | 구현 결정 캡처 |
| `/gsd:plan-phase [N]` | 연구 + 계획 + 검증 단계 |
| `/gsd:execute-phase [N]` | 병렬 웨이브로 계획 실행 |
| `/gsd:verify-work [N]` | 사용자 수용 테스트 |
| `/gsd:complete-milestone` | 마일스톤 아카이브 및 태그 |
| `/gsd:new-milestone [name]` | 다음 버전 시작 |

#### 6단계 Phase 워크플로우

```
1. Initialize → 프로젝트 및 로드맵 정의
2. Discuss    → 구현 선호사항 캡처
3. Plan       → 연구 및 원자적 태스크 생성
4. Execute    → 신선한 컨텍스트로 병렬 구현
5. Verify     → 수동 사용자 수용 테스트
6. Complete   → 마일스톤 아카이브, 릴리스 태그
```

#### 핵심 혁신

**1. Wave 기반 병렬 실행**
```yaml
wave_1:
  tasks: [001, 002, 003]  # 독립 태스크 병렬 실행
  status: pending
wave_2:
  tasks: [004, 005]       # Wave 1 완료 후 실행
  depends: [wave_1]
  status: blocked
```

**2. XML 프롬프트 포맷**
```xml
<task id="001" wave="1" depends="[]">
  <title>Create login endpoint</title>
  <file>src/app/api/auth/login/route.ts</file>
  <requirements>
    - Use jose for JWT (not jsonwebtoken)
    - Validate credentials against users table
    - Return httpOnly cookie on success
  </requirements>
  <acceptance_criteria>
    - curl POST /api/auth/login returns 200 + Set-Cookie
    - Valid credentials: cookie, invalid: 401
  </acceptance_criteria>
</task>
```

**3. Atomic Git Commits**
```
abc123f docs(08-02): complete user registration plan
def456g feat(08-02): add email confirmation flow
hij789k feat(08-02): implement password hashing
lmn012o feat(08-02): create registration endpoint
```
→ Git bisect로 정확한 실패 지점 찾기 가능

**4. 모델 프로필**
| 프로필 | Planning | Execution | Verification |
|--------|----------|-----------|--------------|
| Quality | Opus | Opus | Sonnet |
| Balanced | Opus | Sonnet | Sonnet |
| Budget | Sonnet | Sonnet | Haiku |

**5. 컨텍스트 보존 파일들**
```
PROJECT.md      → 프로젝트 비전 (항상 로드)
research/       → 생태계 지식 및 분석
REQUIREMENTS.md → V1/V2 요구사항 (phase 추적)
ROADMAP.md      → 마일스톤 단계 및 진행률
STATE.md        → 결정, 블로커, 세션 메모리
todos/          → 향후 작업 아이디어
```

#### 기술 스택
- 버전: 1.18.0
- 런타임: Node.js >= 16.7.0
- 빌드: esbuild
- 지원: Claude Code, OpenCode, Gemini CLI, Codex

---

## 3. 비교 매트릭스

### 3.1 규모 비교

| 지표 | Superpowers | bkit | gstack | GSD | harness-engineering |
|------|-------------|------|--------|-----|---------------------|
| 에이전트 | ~10 | 31 | 20 | 6+ | 6 |
| 스킬/커맨드 | ~15 | 36 | 25+ | 40+ | 9 |
| 훅 이벤트 | - | 18 | - | - | 6 |
| 테스트 케이스 | - | 3,298 | E2E | - | - |

### 3.2 기능 비교

| 기능 | Superpowers | bkit | gstack | GSD | harness |
|------|:-----------:|:----:|:------:|:---:|:-------:|
| PDCA 워크플로우 | ✅ | ✅ | ✅ | ✅ | ✅ |
| 자동화 레벨 (L0-L4) | ❌ | ✅ | ❌ | ❌ | ❌ |
| 신뢰 점수 시스템 | ❌ | ✅ | ❌ | ❌ | ❌ |
| 컨텍스트 Rot 방지 | ❌ | ✅ | ❌ | ✅ | ❌ |
| Wave 병렬 실행 | ❌ | ❌ | ✅ | ✅ | ❌ |
| LLM-as-Judge | ❌ | ✅ | ✅ | ❌ | ❌ |
| 헤드리스 브라우저 | ❌ | ❌ | ✅ | ❌ | ❌ |
| MCP 서버 | ❌ | ✅ | ❌ | ❌ | ❌ |
| 감사 로깅 | ❌ | ✅ | ✅ | ✅ | ✅ |
| XML 프롬프트 | ❌ | ❌ | ❌ | ✅ | ❌ |
| 멀티 런타임 | ✅ | ❌ | ❌ | ✅ | ❌ |
| CSO | ✅ | ❌ | ❌ | ❌ | ❌ |
| TDD 스킬 작성 | ✅ | ❌ | ❌ | ❌ | ❌ |

### 3.3 철학 비교

| 프로젝트 | 핵심 철학 | 차별화 포인트 |
|----------|-----------|---------------|
| Superpowers | TDD + Anti-rationalization | 스킬 자체를 TDD로 검증 |
| bkit | 컨텍스트 엔지니어링 | L0-L4 자동화, 3,298 TC |
| gstack | 가상 엔지니어링 팀 | 병렬 스프린트, 헤드리스 브라우저 |
| GSD | Context Rot 해결 | Wave 실행, XML 프롬프트 |

---

## 4. 도입 제안

### 4.1 Superpowers에서 도입

| 기능 | 설명 | 난이도 | 영향도 |
|------|------|--------|--------|
| **CSO (Claude Search Optimization)** | 스킬 description 검색 최적화 | 낮음 | 높음 |
| **Anti-rationalization** | 우회 금지 명시적 규칙 | 낮음 | 중간 |
| **TDD 스킬 작성** | 스킬 자체 TDD 검증 | 높음 | 높음 |

**구현 예시 - CSO 적용:**
```yaml
# 현재
---
name: harness-engineering:implement
description: "Design 문서를 기반으로 TDD 구현"
---

# 개선 후
---
name: harness-engineering:implement
description: |
  Use when implementing features from design.md.
  Triggers on: 'implement this', 'write code for', 'build feature',
  'TDD cycle', 'RED-GREEN-REFACTOR', 'test first approach',
  'make it work', 'coding from design'
---
```

### 4.2 bkit에서 도입

| 기능 | 설명 | 난이도 | 영향도 |
|------|------|--------|--------|
| **L0-L4 자동화 레벨** | 사용자 제어 수준 조절 | 중간 | 매우 높음 |
| **신뢰 점수 시스템** | 자동화 수준 동적 결정 | 높음 | 높음 |
| **JSONL 감사 로깅** | AI 결정 투명 추적 | 낮음 | 높음 |
| **MCP 서버 통합** | 외부 도구 표준 통합 | 높음 | 중간 |
| **PM 에이전트 팀** | 43개 PM 프레임워크 | 높음 | 중간 |

### 4.3 gstack에서 도입

| 기능 | 설명 | 난이도 | 영향도 |
|------|------|--------|--------|
| **LLM-as-Judge** | 스킬 출력 자동 품질 평가 | 중간 | 높음 |
| **멀티 모델 합의** | 여러 모델 독립 검토 | 중간 | 중간 |
| **헤드리스 브라우저** | /browse 스킬 | 높음 | 중간 |
| **오피스 아워** | YC 스타일 제품 진단 | 낮음 | 중간 |

### 4.4 GSD에서 도입

| 기능 | 설명 | 난이도 | 영향도 |
|------|------|--------|--------|
| **Context Rot 방지** | 작업별 신선한 컨텍스트 | 중간 | 매우 높음 |
| **Wave 기반 실행** | 의존성 기반 병렬 그룹화 | 중간 | 높음 |
| **XML 프롬프트** | 구조화된 작업 정의 | 낮음 | 중간 |
| **Atomic Git Commits** | 태스크별 개별 커밋 | 낮음 | 중간 |

---

## 5. 우선순위 로드맵

### Phase 1: 필수 (즉시 도입)

| # | 기능 | 출처 | 이유 |
|---|------|------|------|
| 1 | L0-L4 자동화 레벨 | bkit | 사용자 경험 대폭 개선 |
| 2 | Context Rot 방지 | GSD | 대규모 프로젝트 품질 유지 |
| 3 | JSONL 감사 로깅 | bkit | 투명성 및 디버깅 개선 |

### Phase 2: 중요 (단기 도입)

| # | 기능 | 출처 | 이유 | 상태 |
|---|------|------|------|------|
| 4 | Wave 기반 병렬 실행 | GSD | 효율성 증대 | - |
| 5 | LLM-as-Judge 평가 | gstack | 품질 보증 자동화 | - |
| 6 | 신뢰 점수 시스템 | bkit | 적응형 자동화 | ✅ v1.1.0 |
| 7 | CSO | Superpowers | 스킬 자동 트리거 개선 | ✅ v1.3.0 |

### Phase 3: 권장 (중기 도입)

| # | 기능 | 출처 | 이유 |
|---|------|------|------|
| 8 | XML 프롬프트 포맷 | GSD | 작업 정의 표준화 |
| 9 | Atomic Git Commits | GSD | 버전 관리 개선 |
| 10 | MCP 서버 통합 | bkit | 확장성 확보 |

### Phase 4: 고급 (장기 도입)

| # | 기능 | 출처 | 이유 |
|---|------|------|------|
| 11 | 헤드리스 브라우저 | gstack | E2E 테스트 자동화 |
| 12 | 멀티 모델 합의 | gstack | 품질 검증 강화 |
| 13 | PM 에이전트 팀 | bkit | 제품 발견 프로세스 |

---

## 6. 구현 가이드

### 6.1 L0-L4 자동화 레벨 시스템

**파일 구조:**
```
.harness/
├── config.yaml          # 자동화 설정
├── trust.json           # 신뢰 점수
└── logs/
    └── decisions.jsonl  # 결정 로그
```

**설정 파일 예시:**
```yaml
# .harness/config.yaml
automation:
  level: L2  # L0, L1, L2, L3, L4

  levels:
    L0_manual:
      plan: require_approval
      design: require_approval
      implement: require_approval
      check: require_approval
      wrapup: require_approval

    L1_guided:
      plan: suggest_then_approve
      design: suggest_then_approve
      implement: suggest_then_approve
      check: auto_run
      wrapup: auto_run

    L2_semi_auto:  # 권장 기본값
      plan: ask_if_uncertain
      design: ask_if_uncertain
      implement: auto_run
      check: auto_run_with_report
      wrapup: auto_run

    L3_auto:
      plan: auto_run
      design: auto_run
      implement: auto_run
      check: auto_run_with_gates
      wrapup: auto_run
      gates:
        - test_coverage > 80
        - no_security_issues
        - lint_passing

    L4_full_auto:
      plan: auto_run
      design: auto_run
      implement: auto_run
      check: auto_run
      wrapup: auto_run
      oversight: periodic_summary
```

### 6.2 JSONL 감사 로깅

**로그 포맷:**
```json
{"timestamp":"2026-03-24T10:30:00Z","event":"phase_transition","from":"plan","to":"design","slug":"user-auth","automation_level":"L2","trust_score":0.85}
{"timestamp":"2026-03-24T10:35:00Z","event":"tool_use","tool":"Edit","file":"src/auth.ts","agent":"engineer","approved":true}
{"timestamp":"2026-03-24T10:40:00Z","event":"decision","type":"architecture_choice","option":"jwt","alternatives":["session","oauth"],"confidence":0.92}
```

### 6.3 Wave 기반 실행

**태스크 정의:**
```xml
<!-- docs/specs/user-auth/tasks/001-setup.xml -->
<task id="001" wave="1" depends="[]">
  <title>Setup authentication module</title>
  <file>src/auth/index.ts</file>
  <requirements>
    - Install jose package
    - Create JWT utility functions
    - Setup environment variables
  </requirements>
  <acceptance_criteria>
    - npm run build succeeds
    - Environment variables documented
  </acceptance_criteria>
</task>
```

**Wave 상태 파일:**
```yaml
# .harness/state/waves.yaml
current_wave: 1
waves:
  wave_1:
    tasks: [001, 002, 003]
    status: in_progress
    started: "2026-03-24T10:00:00Z"
  wave_2:
    tasks: [004, 005]
    depends: [wave_1]
    status: blocked
  wave_3:
    tasks: [006]
    depends: [wave_2]
    status: blocked
```

### 6.4 CSO 적용 가이드

**Description 작성 원칙:**
1. **트리거 조건 명시**: 언제 이 스킬이 필요한지
2. **키워드 커버리지**: 에러 메시지, 증상, 동의어
3. **토큰 효율성**: 150단어 이내
4. **능동태 사용**: 명확한 액션 표현

**개선 전/후 예시:**
```yaml
# Before
description: "Design 문서를 기반으로 구현"

# After
description: |
  Use when implementing features from design.md.
  Triggers on: 'implement', 'build', 'code', 'develop',
  'write code', 'make it work', 'TDD', 'test-driven',
  Error: 'implementation needed', 'feature not built'
```

---

## 부록: 참고 링크

- [Superpowers GitHub](https://github.com/obra/superpowers)
- [bkit GitHub](https://github.com/popup-studio-ai/bkit-claude-code)
- [gstack GitHub](https://github.com/garrytan/gstack)
- [GSD GitHub](https://github.com/gsd-build/get-shit-done)
- [Claude Code 공식 문서](https://docs.anthropic.com/claude-code)
