# Quick Start Guide

5분 안에 Harness Engineering의 핵심 워크플로우를 체험해보세요.

## 🚀 설치 (30초)

```bash
# Claude Code 마켓플레이스에서 설치
/plugin install harness-engineering
```

## ⚡ 첫 번째 기능 개발 (3분)

### 방법 1: 전체 자동 실행

```bash
# 한 줄로 전체 PDCA 사이클 실행
/fullrun 간단한 TODO 앱 만들어줘
```

이 한 줄이 다음을 자동으로 수행합니다:
1. **Clarify** → 요청 구체화
2. **Plan** → 요구사항 정의
3. **Design** → 기술 설계
4. **Implement** → TDD 구현
5. **Check** → 검증
6. **Wrapup** → 문서화

### 방법 2: 단계별 실행

```bash
# 1단계: 요청 구체화
/clarify 사용자 인증 기능 추가

# 2단계: 요구사항 문서화
/plan user-auth

# 3단계: 기술 설계
/design user-auth

# 4단계: TDD 구현
/implement user-auth

# 5단계: 검증
/check user-auth

# 6단계: 문서화
/wrapup user-auth
```

## 📁 생성되는 산출물

모든 단계가 완료되면 `docs/specs/<feature-slug>/` 폴더에 다음 문서가 생성됩니다:

```
docs/specs/user-auth/
├── clarify.md    # 요청 구체화 결과
├── plan.md       # 요구사항 문서
├── design.md     # 기술 설계서
└── wrapup.md     # 완료 보고서
```

## 🎛️ 자동화 레벨 설정

```bash
# .harness/config.yaml 편집
automation:
  level: L2  # L0(수동) ~ L4(완전자동)
```

| 레벨 | 설명 | 추천 대상 |
|:----:|:-----|:----------|
| L0 | 모든 전환에 승인 필요 | 초보자 |
| L1 | 중요 전환만 승인 | 학습 단계 |
| **L2** | 불확실할 때만 승인 | **일반 사용자** |
| L3 | 품질 게이트 통과 시 자동 | 숙련자 |
| L4 | 완전 자동 | 매우 숙련자 |

## 🐛 디버깅

```bash
# 체계적 4단계 디버깅
/debug 로그인이 안돼
```

## 📊 상태 확인

```bash
# 현재 PDCA 상태 확인
/harness status
```

## 📚 다음 단계

- [아키텍처 이해하기](ARCHITECTURE.md)
- [스킬 작성 가이드](SKILL-WRITING-GUIDE.md)
- [에이전트 작성 가이드](AGENT-WRITING-GUIDE.md)

## 💡 팁

1. **클린한 세션 유지**: `reset_context_rot_state`로 컨텍스트 초기화
2. **병렬 작업**: 여러 기능을 동시에 개발할 때는 서로 다른 feature-slug 사용
3. **문서 확인**: 각 단계의 산출물을 확인하며 진행 상황 파악

---

질문이 있으시면 `/harness status` 또는 `/debug`를 사용하세요!
