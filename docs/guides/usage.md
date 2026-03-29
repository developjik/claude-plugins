# Harness Engineering - 사용 가이드

이 문서는 Harness Engineering 플러그인의 상세 사용법을 설명합니다.

## 목차

1. [빠른 시작](#빠른-시작)
2. [PDCA 워크플로우](#pdca-워크플로우)
3. [스킬 사용법](#스킬-사용법)
4. [고급 기능](#고급-기능)
5. [문제 해결](#문제-해결)

---

## 빠른 시작

### 5분 튜토리얼

```bash
# 1. 새 기능 개발 시작
/clarify 사용자 인증 기능을 추가하고 싶습니다

# 2. 요구사항 확인 및 계획 수립
/plan user-auth

# 3. 기술 설계
/design user-auth

# 4. TDD 구현
/implement user-auth

# 5. 검증 및 리뷰
/check user-auth

# 6. 마무리
/wrapup user-auth
```

### 한 번에 실행

```bash
# 전체 워크플로우 자동 실행
/fullrun 사용자 인증 기능을 추가하고 싶습니다
```

---

## PDCA 워크플로우

### Phase 0: Clarify (요청 구체화)

요청을 분석하고 명확한 기능 명세로 변환합니다.

```bash
/clarify <기능 설명>
```

**입력:**
- 자연어로 된 기능 설명
- 비즈니스 요구사항
- 사용자 스토리

**출력:**
- `docs/specs/<feature-slug>/clarify.md`
- 기능 슬러그 (kebab-case)
- 핵심 요구사항 목록

**예시:**
```bash
/clarify 로그인한 사용자가 대시보드에서 자신의 활동 내역을 볼 수 있는 기능
# → feature-slug: user-activity-dashboard
# → docs/specs/user-activity-dashboard/clarify.md 생성
```

### Phase 1: Plan (계획 수립)

구체화된 요구사항을 바탕으로 상세 계획을 수립합니다.

```bash
/plan <feature-slug>
```

**입력:**
- clarify.md (자동 로드)

**출력:**
- `docs/specs/<feature-slug>/plan.md`
  - 기능 요구사항 (FR-1, FR-2, ...)
  - 비기능 요구사항 (NFR-1, ...)
  - 수용 기준 (AC-1, ...)

### Phase 2: Design (기술 설계)

계획을 바탕으로 기술 설계를 작성합니다.

```bash
/design <feature-slug>
```

**입력:**
- plan.md (자동 로드)

**출력:**
- `docs/specs/<feature-slug>/design.md`
  - 아키텍처 다이어그램
  - 데이터 모델
  - API 설계
  - 구현 순서
  - 파일 변경 계획

### Phase 3: Implement (TDD 구현)

설계를 바탕으로 TDD 방식으로 구현합니다.

```bash
/implement <feature-slug>
```

**프로세스:**
1. 설계 검증
2. RED: 실패하는 테스트 작성
3. GREEN: 최소 구현
4. REFACTOR: 코드 정리
5. 검증 클래스 실행

**검증 클래스:**
| 클래스 | 내용 | 시간 |
|--------|------|------|
| A | 정적 분석 (린트) | <30초 |
| B | 유닛 테스트 | <1분 |

### Phase 4: Check (2단계 리뷰)

구현된 코드를 2단계로 검증합니다.

```bash
/check <feature-slug>
```

**Stage 1: 스펙 준수 검증**
- 파일 생성 확인
- API 시그니처 일치
- 데이터 모델 정확성
- 의존성 연결

**Stage 2: 코드 품질 리뷰**
- SOLID 원칙
- DRY 원칙
- 함수 복잡도
- 에러 처리

**판정:**
- 90% 이상: PASS → Wrap-up
- 90% 미만: ITERATE → 자동 수정

### Phase 5: Wrap-up (마무리)

완성된 기능을 정리하고 문서화합니다.

```bash
/wrapup <feature-slug>
```

**출력:**
- `docs/specs/<feature-slug>/wrapup.md`
  - 구현 요약
  - 변경된 파일 목록
  - 테스트 커버리지
  - 알려진 제약사항
  - 향후 개선 방향

---

## 스킬 사용법

### /harness (통합 커맨드)

```bash
/harness status                    # 현재 상태 확인
/harness plan <설명>               # clarify + plan
/harness design <feature-slug>     # design 실행
/harness do <feature-slug>         # implement 실행
/harness check <feature-slug>      # check 실행
/harness wrapup <feature-slug>     # wrapup 실행
```

### /debug (디버깅)

체계적인 4단계 디버깅 프로세스:

```bash
/debug 로그인이 안 되는 버그
```

**프로세스:**
1. **Reproduce**: 버그 재현
2. **Isolate**: 원인 격리
3. **Root Cause**: 근본 원인 분석
4. **Fix**: 수정 및 검증

### /delegate (작업 위임)

서브에이전트로 독립적인 작업을 위임합니다.

```bash
/delegate --task="코드 리뷰" --skill=check
```

### /recover (상태 복구)

크래시나 stuck 상태에서 복구합니다.

```bash
/recover                           # 상태 진단
/recover --history                 # 전환 히스토리
/recover --rollback <snapshot-id>  # 스냅샷 복원
```

### /grill-me (자기 검토)

구현된 내용을 스스로 검토합니다.

```bash
/grill-me user-auth
```

---

## 고급 기능

### 다중 프레임워크 테스트

프로젝트의 테스트 프레임워크를 자동 감지합니다:

```bash
# 자동 감지 및 실행
run_tests "$PROJECT_ROOT"

# 특정 테스트만 실행
run_tests "$PROJECT_ROOT" "auth"

# 상세 모드
run_tests "$PROJECT_ROOT" "" "--verbose"
```

**지원 프레임워크:**
- JavaScript: Jest, Vitest, Mocha
- Python: pytest, unittest
- Go: go test
- Rust: cargo test
- Java: Maven, Gradle

### 검증 클래스 시스템

```bash
# Class A+B 실행 (기본)
run_verification "$PROJECT_ROOT" "ab"

# Class A+B+C 실행 (--thorough)
run_verification "$PROJECT_ROOT" "abc" "--thorough"

# 전체 검증
run_verification "$PROJECT_ROOT" "abcd" "--thorough"
```

### 상태 머신

PDCA 상태를 추적하고 관리합니다:

```bash
# 상태 확인
get_current_phase "$PROJECT_ROOT"

# 상태 전환
transition_state "$PROJECT_ROOT" "design" "design_complete"

# 스냅샷 생성
create_snapshot "$PROJECT_ROOT" "implement"

# 롤백
rollback_to_snapshot "$PROJECT_ROOT" "$SNAPSHOT_ID"
```

### 스킬 평가

스킬 실행 품질을 추적합니다:

```bash
# 실행 기록
record_skill_execution "$PROJECT_ROOT" "implement" "success" "5000"

# 통계 조회
get_skill_statistics "$PROJECT_ROOT" "implement" "30"

# 대시보드 생성
generate_skill_dashboard "$PROJECT_ROOT" "30"
```

### 브라우저 테스트

Playwright/Cypress E2E 테스트를 실행합니다:

```bash
# 설정
setup_playwright "$PROJECT_ROOT"

# 테스트 실행
run_browser_tests "$PROJECT_ROOT" --browser=chromium

# 필터링
run_browser_tests "$PROJECT_ROOT" --filter="login"

# Headed 모드
run_browser_tests "$PROJECT_ROOT" --headed
```

---

## 문제 해결

### Stuck 상태 감지

시스템이 자동으로 stuck 상태를 감지합니다:

1. **반복 횟수 초과**: 10회 이상 iterate
2. **타임아웃**: 30분 이상 동일 단계
3. **루프 패턴**: check → implement 무한 루프

### 복구 옵션

```bash
/recover
```

**사용 가능한 옵션:**
1. `resume`: 현재 상태에서 재개
2. `rollback`: 마지막 스냅샷으로 복원
3. `reset_to_design`: 설계 단계로 리셋
4. `manual`: 수동 개입

### 일반적인 문제

#### 테스트 실행 실패

```bash
# jq 설치 확인
command -v jq || brew install jq

# 프레임워크 감지 확인
detect_test_framework "$PROJECT_ROOT"
```

#### 상태 파일 손상

```bash
# 상태 재초기화
init_state_machine "$PROJECT_ROOT" "$FEATURE_SLUG"

# 또는 백업에서 복원
rollback_to_snapshot "$PROJECT_ROOT" "<snapshot-id>"
```

#### Context Rot

```bash
# 점수 확인
cat .harness/state/context-rot-score

# 서브에이전트로 작업 위임
/delegate --task="<작업 내용>"
```

---

## 고급 기능 (P2)

### 해시 앵커 에디트

파일 수정 시 해시 기반 충돌 방지를 제공합니다:

```bash
# 파일 등록
register_file_hash "$PROJECT_ROOT" "src/app.js"

# 무결성 검증
verify_file_integrity "$PROJECT_ROOT" "src/app.js"

# 편집 준비 (충돌 감지)
prepare_edit "$PROJECT_ROOT" "src/app.js" "Add feature X"

# 편집 완료
finalize_edit "$PROJECT_ROOT" "$TXN_ID" "src/app.js"
```

**특징:**
- SHA-256 해시 기반 무결성 검증
- 외부 변경 감지 및 충돌 방지
- 트랜잭션 기반 편집 추적
- 자동 롤백 지원

### 웨이브 실행

의존성 기반 병렬 태스크 실행을 지원합니다:

```bash
# 태스크 위상 정렬
topological_sort '[{"id":"A"},{"id":"B","dependencies":["A"]}]'
# → ["A", "B"]

# 웨이브 그룹화
group_tasks_into_waves '[...]'
# → [["A","B"], ["C"], ["D"]]

# 순환 의존성 감지
detect_circular_dependencies '[...]'
# → {"has_cycle": false}
```

**특징:**
- Kahn 알고리즘 기반 위상 정렬
- 병렬 실행 가능한 태스크 그룹화
- 순환 의존성 자동 감지
- 최대 병렬도 계산

---

## 플래그 참조

### /check 플래그

| 플래그 | 설명 |
|--------|------|
| `--thorough` | Class A~D 모든 검증 실행 |
| `--skip-tests` | 테스트 실행 건너뛰기 |
| `--fix` | 자동 수정 활성화 (기본값) |
| `--no-fix` | 리포트만 생성 |

### /implement 플래그

| 플래그 | 설명 |
|--------|------|
| `--continue` | 이전 구현 계속 |
| `--task=N` | 특정 태스크만 실행 |

### /recover 플래그

| 플래그 | 설명 |
|--------|------|
| `--status` | 현재 상태 표시 (기본값) |
| `--rollback <id>` | 스냅샷 복원 |
| `--resume` | 현재 상태에서 재개 |
| `--history` | 전환 히스토리 표시 |

### /run_browser_tests 플래그

| 플래그 | 설명 |
|--------|------|
| `--browser=<name>` | 브라우저 지정 |
| `--filter=<pattern>` | 테스트 필터링 |
| `--headed` | 헤드리드 모드 |
| `--debug` | 디버그 모드 |

---

## 베스트 프랙티스

### 1. Feature Slug 규칙

- 항상 `kebab-case` 사용
- 기능을 잘 설명하는 이름
- 예: `user-auth`, `payment-integration`, `dashboard-widgets`

### 2. 문서 동기화

각 단계 산출물은 `docs/specs/<feature-slug>/`에 저장됩니다:

```
docs/specs/user-auth/
├── clarify.md
├── plan.md
├── design.md
└── wrapup.md
```

### 3. 정기적 검증

```bash
# 전체 검증
bash scripts/validate.sh

# 훅 테스트
./hooks/__tests__/*.test.sh
```

### 4. 자동화 레벨 조절

```yaml
# .harness/config.yaml
automation:
  level: L2  # 상황에 맞게 조절
```

---

## 참조

- [아키텍처 문서](ARCHITECTURE.md)
- [산출물 규약](ARTIFACT-CONVENTION.md)
- [스킬 작성 가이드](SKILL-WRITING-GUIDE.md)
