---
name: harness
description: |
  PDCA workflow orchestrator. Run any phase: clarify, plan, design, do, check, wrapup, status, or doctor.
  Triggers on: 'harness', 'workflow', 'pdca', 'pipeline', 'run phase', 'next step',
  '워크플로우', '단계 실행', '다음 단계', '진행', 'status', 'doctor', '진단',
  Error: 'which phase', 'run pdca', 'continue workflow', 'next stage', 'diagnose'
user-invocable: true
argument-hint: <clarify|plan|design|do|check|wrapup|status|doctor> [기능명]
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, AskUserQuestion
---

# Harness Skill — PDCA 오케스트레이터

확장 PDCA 워크플로우의 **통합 진입점**입니다.

## 사용법

```
/harness doctor                       → 설치 진단 (의존성, 권한, 구성 확인)
/harness clarify <기능 설명>         → Clarify 단계 실행 (요청 구체화)
/harness plan <기능 설명>            → Plan 단계 실행 (slug 추출 및 문서 생성)
/harness design <feature-slug>       → Design 단계 실행
/harness do <feature-slug>           → Implement(Do) 단계 실행
/harness check <feature-slug>        → Check + auto-Iterate 실행
/harness wrapup <feature-slug>       → Wrap-up 단계 실행
/harness status                      → 현재 PDCA 상태 확인
```

## PDCA 흐름

```
Clarify → Plan → Design → Do → Check(+Iterate) → Wrap-up
```

### $ARGUMENTS 파싱

첫 번째 인자를 액션으로 파싱합니다:

**doctor**: 설치 후 진단을 실행합니다.
- 플러그인 로드 상태 확인
- 필수 의존성 확인 (jq, git, sed, tr)
- 훅 스크립트 권한 확인
- .harness/ 디렉토리 생성 테스트
- 샘플 워크플로우 dry-run

**clarify**: `/clarify <기능 설명>` 스킬을 호출합니다.
- 사용자 요청 분석 및 구체화
- 소크라테스식 질문, 대안 탐색
- `docs/specs/<feature-slug>/clarify.md` 생성

**plan**: `/plan <기능 설명>` 스킬을 호출합니다.
- clarify.md 참조 (있는 경우)
- 기능명(`feature-slug`) 추출, 요구사항 분석
- `docs/specs/<feature-slug>/plan.md` 생성
- 실행 전 현재 feature context를 `<feature-slug>`로 맞춥니다.

**design**: `/design <feature-slug>` 스킬을 호출합니다.
- Plan 기반 코드 변경 계획 수립
- `docs/specs/<feature-slug>/design.md` 생성
- 실행 전 현재 feature context가 비어 있지 않은지 확인합니다.

**do**: `/implement <feature-slug>` 스킬을 호출합니다.
- RED-GREEN-REFACTOR TDD 구현
- 구현 중 문서/코드 편집은 동일 feature context를 유지해야 합니다.

**check**: `/check <feature-slug>` 스킬을 호출합니다.
- 코드 리뷰 + 계획 일치 검증
- 불일치 시 자동 Iterate (최대 10회)

**wrapup**: `/wrapup <feature-slug>` 스킬을 호출합니다.
- 정리, 문서화, 변경 로그
- `docs/specs/<feature-slug>/wrapup.md` 생성

**status**: 현재 PDCA 진행 상태를 표시합니다.

## 권장 워크플로우

### 새로운 기능 개발
```
1. /harness clarify "사용자 인증 기능"  # 요청 구체화
2. /harness plan user-auth             # 요구사항 문서화
3. /harness design user-auth           # 기술 설계
4. /harness do user-auth               # TDD 구현
5. /harness check user-auth            # 검증
6. /harness wrapup user-auth           # 문서화
```

### 전체 자동 실행
```
/fullrun "사용자 인증 기능"  # Clarify부터 Wrapup까지 자동 실행
```

## 주의사항

- 각 단계는 개별 스킬로도 직접 호출 가능합니다
  (`/clarify`, `/plan`, `/design`, `/implement`, `/check`, `/wrapup`)
- **새로운 기능은 반드시 clarify 먼저 실행을 권장합니다**
- 단계를 건너뛰지 마세요 — 각 단계의 출력이 다음 단계의 입력입니다
- 전체 자동 실행이 필요하면 `/fullrun` 을 사용하세요
