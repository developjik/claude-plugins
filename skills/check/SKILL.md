---
name: check
description: |
  Use after implementation. Execute tests, review code against plan/design,
  verify consistency with 2-stage review, auto-fix gaps.
  Triggers on: 'review', 'verify', 'check', 'validate', 'code review', 'quality check',
  '리뷰', '검증', '확인', '체크', '코드 리뷰', '품질 검사', '일치 확인',
  Error: 'verify implementation', 'check against spec', 'review needed', 'does this match plan'
user-invocable: true
argument-hint: <기능명 또는 Design 문서 경로> [--thorough]
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, Agent
---

# Check Skill — PDCA 4단계 (Check + Iterate)

구현 코드를 **계획 대비 검증**하고, **실제 테스트를 실행**하며, **2단계 리뷰**를 수행합니다.
불일치 시 **자동 반복 수정**합니다.

## 프로세스

### 0. 검증 준비

```bash
# 훅 라이브러리 로드
PLUGIN_DIR="${PLUGIN_DIR:-$(dirname "$0")/..}"
source "${PLUGIN_DIR}/hooks/lib/test-runner.sh"
source "${PLUGIN_DIR}/hooks/lib/verification-classes.sh"
source "${PLUGIN_DIR}/hooks/lib/state-machine.sh"

# 기능 슬러그 추출
FEATURE_SLUG=$(echo "$ARGUMENTS" | awk '{print $1}')
THOROUGH_MODE=$(echo "$ARGUMENTS" | grep -o '\-\-thorough' || echo "")

# 상태 확인
CURRENT_PHASE=$(get_current_phase "$PROJECT_ROOT")
if [[ "$CURRENT_PHASE" != "implement" && "$CURRENT_PHASE" != "check" ]]; then
  echo "⚠️  Check는 implement 단계 이후에 실행해야 합니다."
  echo "   현재 단계: $CURRENT_PHASE"
  exit 1
fi
```

### 1. Plan/Design 문서 로드

`$ARGUMENTS`에서 `<feature-slug>`를 식별하고, 다음 파일에서 기대 결과를 읽습니다:
- `docs/specs/<feature-slug>/plan.md` — 요구사항 및 기능 정의
- `docs/specs/<feature-slug>/design.md` — 구현 설계 및 파일 변경 계획

### 2. 검증 클래스 실행 (NEW)

#### 2.1. 기본 검증 (Class A + B)

```bash
# 정적 분석 + 유닛 테스트
VERIFICATION_RESULT=$(run_verification "$PROJECT_ROOT" "ab")

# 결과 분석
PASSED=$(echo "$VERIFICATION_RESULT" | jq -r '.summary.passed')
FAILED=$(echo "$VERIFICATION_RESULT" | jq -r '.summary.failed')
```

#### 2.2. 심층 검증 (`--thorough` 플래그)

```bash
# Class A + B + C + D (정적 + 유닛 + 통합 + E2E)
VERIFICATION_RESULT=$(run_verification "$PROJECT_ROOT" "abcd" "--thorough")
```

#### 검증 클래스 설명

| 클래스 | 내용 | 시간 | 실행 조건 |
|--------|------|------|----------|
| **A** | 정적 분석 (린트, 타입체크) | <30초 | 항상 |
| **B** | 유닛 테스트 | <1분 | 항상 |
| **C** | 통합 테스트 | <5분 | `--thorough` |
| **D** | E2E 테스트 | <15분 | `--thorough` |

### 3. 2단계 리뷰 시스템 (NEW from superpowers)

#### Stage 1: 스펙 준수 검증

design.md의 각 항목이 구현되었는지 확인합니다.

**검증 항목:**
- [ ] 모든 파일이 생성되었는가?
- [ ] API 시그니처가 일치하는가?
- [ ] 데이터 모델이 정확한가?
- [ ] 의존성이 올바르게 연결되었는가?

```bash
# 스펙 준수 검증
SPEC_COMPLIANCE=$(verify_spec_compliance "$PROJECT_ROOT" "$FEATURE_SLUG")
```

#### Stage 2: 코드 품질 리뷰 (Fresh Subagent)

**새로운 서브에이전트를 스폰하여 독립적으로 리뷰합니다.**
(superpowers의 "two-stage review" 패턴)

```bash
# 서브에이전트로 코드 품질 리뷰
CODE_QUALITY=$(spawn_subagent_for_review "$PROJECT_ROOT" "$FEATURE_SLUG")
```

**검증 항목:**
- [ ] SOLID 원칙 준수
- [ ] 중복 코드 없음 (DRY)
- [ ] 함수 길이 적절 (<20줄)
- [ ] 복잡도 낮음 (<10)
- [ ] 에러 처리 적절

### 4. 검증 체크리스트

#### 기능 완전성
- [ ] 모든 기능 요구사항(FR)이 구현되었는가?
- [ ] 엣지 케이스가 처리되었는가?
- [ ] 에러 처리가 적절한가?

#### 코드 품질
- [ ] TDD 사이클을 따랐는가? (RED-GREEN-REFACTOR)
- [ ] SOLID 원칙을 준수하는가?
- [ ] 중복 코드가 없는가?

#### 보안
- [ ] 입력 검증이 있는가?
- [ ] 민감 정보가 노출되지 않는가?
- [ ] 인증/인가가 올바른가?

#### 테스트
- [ ] 모든 테스트가 통과하는가? (실제 실행)
- [ ] 핵심 경로에 테스트가 있는가?
- [ ] 커버리지가 충분한가? (>80%)

#### 계획 일치도
- [ ] Design 문서의 파일 변경 계획과 실제 변경이 일치하는가?
- [ ] 누락된 구현이 없는가?

### 5. 판정

**일치도 90% 이상 + 모든 테스트 통과** → ✅ 통과 → Wrap-up으로 진행

**일치도 90% 미만 또는 테스트 실패** → ❌ Iterate 발동

### 6. 자동 Iterate (최대 10회)

불일치 시 자동으로 수정 루프를 실행합니다:

```
반복 N/10:
1. 미충족 항목 식별
2. 테스트 실패 원인 분석
3. 수정 코드 작성
4. 테스트 재실행 (run_tests_with_retry)
5. 재검증
→ 90% 이상이면 종료, 미만이면 다음 반복
```

⚠️ 10회 반복 후에도 미충족이면 사용자에게 보고하고 중단합니다.

### 7. 상태 업데이트

```bash
# 상태 머신 업데이트
if [[ "$OVERALL_PASSED" == "true" ]]; then
  transition_state "$PROJECT_ROOT" "wrapup" "check_passed"
else
  # iterate 모드로 전환
  transition_state "$PROJECT_ROOT" "implement" "check_failed_iterate"
fi

# check 결과 저장
jq -n \
  --argjson spec "$SPEC_COMPLIANCE" \
  --argjson quality "$CODE_QUALITY" \
  --argjson tests "$VERIFICATION_RESULT" \
  --argjson match_rate "$MATCH_RATE" \
  '{
    "spec_compliance": $spec,
    "code_quality": $quality,
    "test_results": $tests,
    "match_rate": $match_rate,
    "timestamp": "'"$(date -u '+%Y-%m-%dT%H:%M:%SZ')"'"
  }' > "${PROJECT_ROOT}/.harness/state/check-results.json"
```

## 출력

```
🔍 Check 결과

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 검증 클래스 결과
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Class A (Static Analysis):  ✅ Passed
  - ESLint: ✅
  - TypeScript: ✅

Class B (Unit Tests):       ✅ Passed
  - Total: 24, Passed: 24, Failed: 0

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 2단계 리뷰
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Stage 1 - 스펙 준수:        ✅ 95%
Stage 2 - 코드 품질:        ✅ 92%

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📈 종합 결과
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📊 계획 일치도: 94%
🔄 Iterate 횟수: 2/10

✅ 충족:
- 모든 FR 구현 완료
- 테스트 커버리지 87%
- 보안 검사 통과

❌ 미충족 (수정됨):
- 엣지 케이스 누락 → 수정됨: 입력값 검증 추가

📋 판정: ✅ 통과

➡️ 다음 단계: /wrapup <feature-slug> 으로 정리 및 문서화를 시작하세요.
```

## 플래그

| 플래그 | 설명 |
|--------|------|
| `--thorough` | Class A~D 모든 검증 실행 (통합, E2E 포함) |
| `--skip-tests` | 테스트 실행 건너뛰기 (스펙 검증만) |
| `--fix` | 자동 수정 활성화 (기본값) |
| `--no-fix` | 자동 수정 비활성화, 리포트만 |

## 의존성

```bash
# 필수
source hooks/lib/test-runner.sh
source hooks/lib/verification-classes.sh
source hooks/lib/state-machine.sh

# 선택적 (테스트 프레임워크별)
- jest/vitest (JavaScript)
- pytest (Python)
- go test (Go)
- cargo test (Rust)
```
