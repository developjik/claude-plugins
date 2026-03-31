---
name: plan
description: |
  Use when starting a new feature or project. Requirements analysis and goal definition phase.
  Prerequisite: Run /clarify first for new features.
  Triggers on: 'plan', 'requirements', 'spec', 'what to build', 'define scope', 'new feature',
  '프로젝트 시작', '요구사항', '계획', '기획', '무엇을 만들', 'scope 정의', '기능 명세',
  Error: 'unclear requirements', 'missing spec', 'no plan', 'what should this do'
user-invocable: true
argument-hint: <feature-slug>
allowed-tools: Read, Grep, Glob, Bash
requires: clarify
---

# Plan Skill — PDCA 1단계

**"무엇을 만들 것인가?"** 를 명확히 합니다. 코드를 작성하지 않습니다.

## 전제 조건

⚠️ **새로운 기능의 경우, 먼저 `/clarify` 를 실행하세요.**

Plan 스킬은 `docs/specs/<feature-slug>/clarify.md` 가 존재하면 자동으로 참조합니다.
clarify.md가 없으면 경고 후 진행 여부를 확인합니다.
Plan 시작 시 `.harness/engine/state.json`의 `feature_slug`가 현재 `<feature-slug>`와 일치하도록 초기화하거나 복구합니다.

## 프로세스

### 0. Clarify 문서 확인

#### 0.1. clarify.md 존재 확인
`docs/specs/<feature-slug>/clarify.md` 파일이 존재하는지 확인합니다.

- **존재함**: clarify.md를 읽어 구체화된 요청 내용을 파악합니다.
- **없음**: 사용자에게 clarify 실행 여부를 확인합니다.
  ```
  ⚠️ clarify.md가 없습니다. 먼저 /clarify <feature-slug>를 실행하시겠습니까?
  [Y] 예, clarify 먼저 실행
  [N] 아니오, 바로 plan 진행
  ```

#### 0.2. clarify.md 내용 로드 (있는 경우)
clarify.md에서 다음 정보를 추출하여 Plan 작성에 활용합니다:
- 핵심 목표
- 성공 기준
- 제약 조건
- 스코프 경계
- 선택된 접근 방식
- Gray Areas 결정 사항

### 1. Feature Slug 추출 및 초기 분석

#### 1.1. 기존 코드베이스 분석 (Codebase Mapping)
현재 프로젝트의 코드베이스를 분석하여 아키텍처, 주요 모듈, 디자인 패턴, 기술 스택, 그리고 기존 컨벤션 등을 파악합니다. 이 정보는 새로운 기능의 계획 수립 시 기존 시스템과의 조화를 고려하는 데 활용됩니다.

*   **분석 대상**: `/home/ubuntu/harness-engineering` (현재 프로젝트 루트)
*   **분석 방법**: `ls -R`, `grep` 등을 활용하여 파일 구조, 주요 키워드, 설정 파일 등을 탐색합니다.
*   **산출물**: 분석된 코드베이스의 핵심 정보는 `plan.md`의 '코드베이스 분석 요약' 섹션에 요약되어 반영됩니다.

#### 1.2. Strategist 에이전트의 소크라테스식 질문 및 요구사항 정제
`strategist` 에이전트의 인지 모드를 활용하여 `$ARGUMENTS`에서 주어진 기능 설명을 바탕으로 핵심 목표, 성공 기준, 제약 조건, 스코프 등을 심층적으로 분석하고 정제합니다. 이 과정에서 `strategist`는 사용자에게 역질문을 던져 숨겨진 의도를 파악하고, `plan.md`의 '초기 질문 및 답변' 섹션에 그 내용을 기록합니다.

$ARGUMENTS 에서 기능명(Feature Slug)을 추출합니다. (kebab-case, 예: `user-auth`)
이후 이하 항목들을 분석하여 명확히 합니다:

- 이 프로젝트/기능의 **핵심 목표**는 무엇인가?
- **성공 기준**은 무엇인가? (측정 가능하게)
- **제약 조건**: 시간, 기술 스택, 예산, 호환성
- 기존 시스템과의 **통합 지점**
- **스코프**: v1에 포함할 것 vs 제외할 것

### 2. 모호한 부분에 대한 사용자 질문
모호한 부분은 반드시 사용자에게 질문합니다. 가정하지 않습니다.
**clarify.md가 있다면 이미 해결된 내용은 생략합니다.**

### 3. 요구사항 문서 작성
`docs/templates/plan.md` 템플릿을 읽고 내용을 채운 뒤, **`docs/specs/<feature-slug>/plan.md`** 경로에 저장합니다.
(직접 마크다운 포맷을 지어내지 말고 반드시 템플릿 구조를 따르세요)

#### 3.1. clarify.md 내용 통합
clarify.md가 있는 경우, "초기 질문 및 답변" 섹션에 clarify.md의 핵심 내용을 요약하여 통합합니다:
- 소크라테스식 질문의 핵심 답변
- 선택된 접근 방식
- Gray Areas 결정 사항

## 출력

```
✅ Plan 완료

📋 요구사항 요약:
- [핵심 요구사항 목록]
- 📄 산출물: docs/specs/<feature-slug>/plan.md
- 📎 참조: docs/specs/<feature-slug>/clarify.md (있는 경우)

➡️ 다음 단계: /design <feature-slug> 로 코드 변경 계획을 수립하세요.
```
