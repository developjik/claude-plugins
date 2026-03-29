---
name: clarify
description: |
  Use when receiving any user request. Refines rough ideas through
  Socratic questions, explores alternatives, identifies gray areas.
  MUST run before /plan for any new feature or project.
  Triggers on: 'clarify', '구체화', '정리', '브레인스토밍', 'brainstorm',
  '아이디어', '만들고 싶', '추가하고 싶', '생각나는게 있어'
  Error: 'unclear request', 'what do you mean', 'need more context'
user-invocable: true
argument-hint: <사용자 요청 또는 아이디어>
allowed-tools: Read, Grep, Glob, Bash, AskUserQuestion
---

# Clarify Skill — 요청 구체화 (PDCA 0단계)

**"사용자가 진짜 원하는 게 무엇인가?"** 를 명확히 합니다.
코드를 작성하지 않고, 요청을 구체화하여 Plan 단계의 입력을 준비합니다.

## 프로세스

### 1. 요청 분석 (Request Analysis)

#### 1.1. Feature Slug 추출
`$ARGUMENTS`에서 기능명(Feature Slug)을 추출합니다. (kebab-case, 예: `user-auth`)
추출 직후 `.harness/engine/state.json`과 `.harness/state/current-feature.txt`에 현재 feature context를 초기화합니다.

#### 1.2. 요청 유형 분류
- **신규 기능**: 새로운 기능 개발
- **버그 수정**: 기존 기능의 문제 해결
- **개선**: 기존 기능의 성능/사용성 향상
- **문서**: 문서 작성/수정
- **리팩토링**: 코드 구조 개선

#### 1.3. 모호성 점수 산정
0-10 점수로 요청의 명확성 평가 (높을수록 불명확)
- 0-3: 명확함 (바로 Plan 진행 가능)
- 4-6: 약간 모호함 (기본 질문 필요)
- 7-10: 매우 모호함 (심층 인터뷰 필요)

### 2. 소크라테스식 질문 (Socratic Questions)

Strategist 에이전트의 인지 모드를 활용하여 다음 항목을 파악합니다:

#### 2.1. 핵심 목표 파악
- "이 기능을 통해 해결하고 싶은 문제가 무엇인가요?"
- "이 기능이 없다면 현재 어떤 어려움을 겪고 있나요?"
- "성공적으로 완료되었을 때 어떤 변화가 있나요?"

#### 2.2. 성공 기준 정의
- "완료되었는지 어떻게 알 수 있나요?"
- "측정 가능한 지표가 있나요?"
- "MVP(최소 기능)와 나중에 추가할 기능을 구분해볼까요?"

#### 2.3. 제약 조건 확인
- 기술 스택 제한이 있나요?
- 일정 마감이 있나요?
- 기존 시스템과의 호환성 요구사항이 있나요?

#### 2.4. 스코프 경계 설정
- "이번에 꼭 포함해야 할 것은 무엇인가요?"
- "나중에 해도 되는 것은 무엇인가요?"
- "절대 하지 않을 것은 무엇인가요?"

### 3. 대안 탐색 (Alternatives Exploration)

요청 복잡도가 4점 이상인 경우, 2-3개의 접근 방식을 제시합니다:

```
┌─────────────────────────────────────────────────────┐
│ 접근 방식 비교                                        │
├──────────┬──────────┬──────────┬───────────────────┤
│          │ 방식 A   │ 방식 B   │ 방식 C           │
├──────────┼──────────┼──────────┼───────────────────┤
│ 장점     │ ...      │ ...      │ ...              │
│ 단점     │ ...      │ ...      │ ...              │
│ 예상공수 │ ...      │ ...      │ ...              │
│ 추천도   │ ⭐⭐⭐    │ ⭐⭐      │ ⭐                │
└──────────┴──────────┴──────────┴───────────────────┘
```

### 4. Gray Areas 식별

요청 유형에 따라 확인이 필요한 영역을 식별합니다:

#### 4.1. Visual Features (UI/UX)
- [ ] 레이아웃: 데스크톱/모바일 대응?
- [ ] 밀도: 정보량 조절?
- [ ] 인터랙션: 애니메이션/전환 효과?
- [ ] 빈 상태: 데이터 없을 때 표시?

#### 4.2. APIs / CLIs
- [ ] 응답 형식: JSON/XML/기타?
- [ ] 에러 처리: HTTP 상태 코드/메시지?
- [ ] 페이지네이션: 방식과 크기?
- [ ] 인증: 방식과 권한?

#### 4.3. Content Systems
- [ ] 구조: 계층/평면?
- [ ] 톤: 공식적/캐주얼?
- [ ] 깊이: 개요/상세?

### 5. 산출물 저장

`docs/templates/clarify.md` 템플릿을 읽고 내용을 채운 뒤,
**`docs/specs/<feature-slug>/clarify.md`** 경로에 저장합니다.
저장 직후 현재 feature context가 유지되는지 확인합니다.

## 자동화 레벨별 동작

| 레벨 | 모호성 0-3 | 모호성 4-6 | 모호성 7-10 |
|------|-----------|-----------|-------------|
| L0-L1 | 기본 질문 | 심층 질문 | 전체 인터뷰 |
| L2-L3 | 최소 확인 | 기본 질문 | 심층 질문 |
| L4 | 자동 진행 | 최소 확인 | 기본 질문 |

## 출력

```
✅ Clarify 완료

📋 요청 분석:
- 유형: [신규 기능/버그 수정/개선/문서/리팩토링]
- 모호성 점수: [0-10]
- Feature Slug: <feature-slug>

💡 핵심 발견:
- [발견한 핵심 내용 1-3개]

📄 산출물: docs/specs/<feature-slug>/clarify.md

➡️ 다음 단계: /plan <feature-slug> 로 요구사항 문서를 작성하세요.
```

## 참고

이 스킬은 다음 프로젝트들의 베스트 프랙티스를 참고했습니다:
- Superpowers: brainstorming 스킬
- gstack: /office-hours (6가지 강제 질문)
- GSD: /gsd:discuss-phase (gray areas 식별)
- bkit: /pdca pm (PM Agent Team)
- Oh My OpenAgent: Prometheus Planner (인터뷰 모드)
