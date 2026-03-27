# Wave Execution System

독립적인 태스크들을 병렬로 실행하여 개발 속도를 2-3배 향상시키는 시스템입니다.

## 개요

Wave Execution은 태스크 간 의존성을 분석하여 독립적인 작업들을 동시에 실행합니다.

```
Wave 1 (병렬)         Wave 2 (병렬)         Wave 3 (순차)
┌─────────┐ ┌─────────┐    ┌─────────┐ ┌─────────┐    ┌─────────┐
│ Task A  │ │ Task B  │ →  │ Task C  │ │ Task D  │ →  │ Task E  │
│ (User)  │ │ (Product)│    │ (Orders)│ │ (Cart)  │    │(Checkout)│
└─────────┘ └─────────┘    └─────────┘ └─────────┘    └─────────┘
     │           │              ↑           ↑              ↑
     └───────────┴──────────────┴───────────┘              │
              Dependencies: Task C, D need A or B          │
                                  Task E needs C + D ──────┘
```

## 디렉토리 구조

```
docs/specs/<feature-slug>/
├── waves.yaml              # Wave 정의 파일
├── tasks/
│   ├── 001-user-model.md
│   ├── 002-product-model.md
│   ├── 003-user-api.md
│   └── ...
└── plan.md
```

## waves.yaml 형식

```yaml
# docs/specs/user-auth/waves.yaml
feature: user-auth
total_waves: 3

waves:
  - wave: 1
    parallel: true
    tasks:
      - id: "001"
        name: "User Model"
        file: "tasks/001-user-model.md"
        dependencies: []

      - id: "002"
        name: "Product Model"
        file: "tasks/002-product-model.md"
        dependencies: []

  - wave: 2
    parallel: true
    tasks:
      - id: "003"
        name: "User API"
        file: "tasks/003-user-api.md"
        dependencies: ["001"]

      - id: "004"
        name: "Product API"
        file: "tasks/004-product-api.md"
        dependencies: ["002"]

  - wave: 3
    parallel: false  # 순차 실행
    tasks:
      - id: "005"
        name: "Integration Tests"
        file: "tasks/005-integration.md"
        dependencies: ["003", "004"]
```

## 태스크 파일 형식

```markdown
---
task_id: "001"
wave: 1
name: "User Model"
dependencies: []
estimated_time: "5min"
---

# User Model Implementation

## 목표
사용자 데이터 모델을 정의하고 구현합니다.

## 작업 내용
1. `src/models/User.ts` 생성
2. 인터페이스 정의
3. 유효성 검사 로직

## 검증
- [ ] User 인터페이스 정의 완료
- [ ] 단위 테스트 통과
```

## 실행 방법

```bash
# 전체 Wave 실행
/implement user-auth --waves

# 특정 Wave만 실행
/implement user-auth --wave 2

# 드라이런 (계획만 확인)
/implement user-auth --waves --dry-run
```

## 의존성 규칙

1. **같은 Wave**: 독립적이어야 함 (의존성 없음)
2. **다음 Wave**: 이전 Wave의 태스크에만 의존 가능
3. **순차 Wave**: `parallel: false` 시 순차 실행

## 성능 비교

| 시나리오 | 순차 실행 | Wave 실행 | 향상률 |
|:--------|:--------:|:--------:|:-----:|
| 10개 독립 태스크 | 50분 | 20분 | **60%** |
| 5개 + 5개 의존 | 50분 | 30분 | **40%** |
| 모두 의존성 있음 | 50분 | 50분 | 0% |

## 주의사항

1. **파일 충돌**: 같은 파일을 수정하는 태스크는 같은 Wave에 두지 마세요
2. **리소스 제한**: 너무 많은 병렬 태스크는 컨텍스트를 소모합니다
3. **에러 전파**: Wave 내 하나라도 실패하면 전체 Wave가 중단됩니다
