---
name: design
description: |
  Use after plan.md exists. Technical design and file-level change planning from requirements.
  Triggers on: 'design', 'architecture', 'technical spec', 'how to implement', 'file changes',
  '설계', '아키텍처', '기술 명세', '구현 방법', '파일 변경', '구조 설계', 'API 설계',
  Error: 'no design', 'missing architecture', 'how should this work', 'implementation plan needed'
user-invocable: true
argument-hint: <기능명 또는 Plan 문서 경로>
allowed-tools: Read, Grep, Glob, Bash
requires: plan
---

# Design Skill — PDCA 2단계

Plan 문서를 기반으로 **"코드를 어떻게 바꿀 것인가?"** 를 구체화합니다.

## 프로세스

### 1. Plan 문서 로드
$ARGUMENTS 에서 `<feature-slug>`를 식별하고, **`docs/specs/<feature-slug>/plan.md`** 파일(기존 산출물)을 읽습니다.

### 2. 현재 코드베이스 분석
- 관련 파일 구조 파악
- 기존 패턴과 컨벤션 확인
- 의존성 관계 분석

### 3. Architect 에이전트의 비판적 검토 (Adversarial Review)
`architect` 에이전트의 인지 모드를 활용하여 설계의 잠재적인 문제점과 엣지 케이스를 사전에 도출합니다.
- **요구사항 불일치**: Plan 문서의 요구사항과 현재 구상 중인 설계가 일치하는지 확인합니다.
- **기술적 타당성**: 제안된 기술 스택이나 아키텍처가 현실적으로 구현 가능한지, 성능/보안/확장성 측면에서 문제는 없는지 검토합니다.
- **실패 시나리오 및 예외 처리**: 각 컴포넌트의 실패가 전체 시스템에 미치는 영향을 분석하고, 모든 엣지 케이스에 대한 예외 처리가 명확한지 확인합니다.
- **보안 취약점**: 잠재적인 보안 취약점(인증/인가 문제, 데이터 노출 등)을 점검합니다.
- 도출된 문제점과 해결 방안은 `design.md`의 '비판적 검토 (Adversarial Review)' 섹션에 기록합니다.

### 4. 변경 계획 문서 작성
`docs/templates/design.md` 템플릿을 읽고 내용을 채운 뒤, **`docs/specs/<feature-slug>/design.md`** 경로에 설계 문서를 저장합니다.
(별도 포맷을 지어내지 않고 템플릿의 항목을 모두 채워야 합니다)

## 출력

```
✅ Design 완료

📐 변경 요약:
- 생성: X개 파일
- 수정: Y개 파일
- 삭제: Z개 파일
- 📄 산출물: docs/specs/<feature-slug>/design.md

➡️ 다음 단계: /implement <feature-slug> 로 TDD 구현을 시작하세요.
```
