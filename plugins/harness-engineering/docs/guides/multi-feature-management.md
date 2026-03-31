# 복합 기능 관리 및 의존성 추적 가이드

본 문서는 Harness Engineering 프레임워크에서 여러 기능이 동시에 진행될 때, **슬러그 충돌 방지**, **기능 간 의존성 관리**, **파일 변경 충돌 감지**를 위한 가이드라인을 제공합니다.

---

## 개요

Harness Engineering은 단일 기능의 PDCA 워크플로우를 체계적으로 관리하도록 설계되었습니다. 그러나 실제 프로젝트에서는 여러 기능이 병렬로 진행되는 경우가 많습니다. 이 가이드는 그러한 복잡한 상황에서도 프레임워크의 안정성과 추적 가능성을 유지하기 위한 메커니즘을 제공합니다.

---

## 1. 기능 레지스트리 (Feature Registry)

### 목적
모든 기능의 상태, 의존성, 영향 범위를 **중앙 집중식**으로 관리합니다.

### 위치
기본 레지스트리 문서는 `docs/analysis/features.md` 입니다. 런타임은 레거시 호환을 위해 `docs/features.md`가 존재하면 그 경로도 읽습니다.

### 관리 책임
- **초기 생성**: `strategist` 에이전트 (또는 `librarian`)
- **상태 업데이트**: 각 PDCA 단계 진입 시 `librarian` 에이전트
- **의존성 검증**: `guardian` 에이전트 (check 단계)

### 필수 정보

| 필드 | 설명 | 예시 |
|:-----|:-----|:-----|
| `feature-slug` | 고유 식별자 (kebab-case) | `user-auth` |
| 제목 | 기능의 간략한 설명 | `사용자 인증 시스템` |
| 상태 | 현재 PDCA 단계 | `Implementing` |
| 담당 | 현재 작업을 주도하는 에이전트 | `engineer` |
| 의존성 | 선행되어야 할 기능 목록 | `database-setup` |
| 영향 범위 | 수정될 주요 파일/모듈 | `src/auth/`, `db/schema.sql` |

---

## 2. 의존성 선언 및 검증

### 2.1. Plan 단계에서 의존성 선언

`/plan` 스킬 실행 시, `docs/specs/<feature-slug>/plan.md`에 다음 섹션을 포함합니다:

```markdown
## 6. 의존성 (Dependencies)

### 선행 기능 (Prerequisite Features)
- [ ] `database-setup`: 데이터베이스 스키마 생성 필요
- [ ] `api-framework`: REST API 프레임워크 구축 필요

### 외부 의존성 (External Dependencies)
- Node.js 18.0 이상
- PostgreSQL 13.0 이상
```

### 2.2. Design 단계에서 영향 범위 명시

`/design` 스킬 실행 시, `docs/specs/<feature-slug>/design.md`에 다음 섹션을 포함합니다:

```markdown
## 1.5. 영향 범위 (Impact Analysis)

### 수정될 주요 모듈/파일
| 모듈/파일 | 영향도 | 설명 |
|:---------|:------|:-----|
| `src/auth/` | High | JWT 토큰 생성 및 검증 로직 추가 |
| `db/schema.sql` | High | users, tokens 테이블 생성 |
| `src/middleware/` | Medium | 인증 미들웨어 추가 |

### 다른 기능과의 충돌 가능성
- **`payment-gateway`와의 충돌**: 사용자 인증 정보 사용 (순차 진행 권장)
- **`user-profile`과의 충돌**: 없음 (독립적으로 진행 가능)
```

### 2.3. Check 단계에서 의존성 검증

`/check` 스킬 실행 시, `guardian` 에이전트는 다음을 검증합니다:

1. 현재 기능의 모든 선행 기능이 `Completed` 상태인지 확인
2. 외부 의존성이 충족되었는지 확인
3. 불일치 시 `/implement` 단계로 자동 반복 (최대 10회)

---

## 3. 파일 변경 충돌 감지

### 3.1. 자동 감지 메커니즘

`implement` 단계에서 파일 수정(`Write`, `Edit`)이 발생할 때, `pre-tool.sh` 훅이 다음을 자동으로 확인합니다:

1. 현재 수정하려는 파일이 다른 `Implementing` 또는 `Checking` 상태의 기능의 `영향 범위`에 포함되어 있는지 확인
2. 충돌 가능성이 감지되면 경고 메시지 출력
3. 필요 시 수동 개입 요청

### 3.2. 충돌 해결 전략

충돌이 감지된 경우, 다음 중 하나를 선택합니다:

**옵션 1: 순차 진행**
- 먼저 진행 중인 기능을 완료한 후, 다른 기능을 시작
- 가장 안전하지만 시간이 오래 걸림

**옵션 2: 파일 분리**
- 공통 파일을 수정하는 대신, 기능별 독립적인 파일 생성
- 예: `src/auth/jwt-handler.js` vs `src/auth/oauth-handler.js`

**옵션 3: 코드 리뷰 강화**
- 병렬 진행을 허용하되, `check` 단계에서 병합 충돌을 명시적으로 검증
- Git의 conflict resolution 메커니즘 활용

---

## 4. 에이전트 역할 강화

### Strategist
- 기능의 우선순위와 의존성 파악
- `docs/analysis/features.md` 초기화 및 기능 추가
- `plan.md`에 의존성 명시

### Architect
- 다른 기능과의 잠재적 충돌 최소화
- `design.md`에 `Impact Analysis` 섹션 작성
- 파일 변경 계획 수립 시 충돌 고려

### Engineer
- `design.md`의 `Affected Files/Modules`를 엄격히 준수
- 계획되지 않은 파일 수정 금지
- 충돌 경고 메시지에 주의

### Guardian
- `check` 단계에서 의존성 검증
- 다른 기능과의 영향 범위 겹침 확인
- 파일 병합 충돌 검증

### Librarian
- `docs/analysis/features.md` 최신 상태 유지
- 각 PDCA 단계 완료 후 상태 업데이트
- 의존성 및 영향 범위 변경 사항 반영

---

## 5. 실전 예시

### 시나리오: 동시 진행 기능

프로젝트에서 다음 3개 기능이 동시에 진행되는 상황:

1. **`user-auth`** (Implementing): 사용자 인증 시스템
2. **`payment-gateway`** (Planning): 결제 시스템 (user-auth에 의존)
3. **`product-search`** (Designing): 상품 검색 기능 (독립적)

### docs/analysis/features.md 상태

```markdown
| `feature-slug` | 제목 | 상태 | 담당 | 의존성 | 영향 범위 |
|:---|:---|:---|:---|:---|:---|
| `user-auth` | 사용자 인증 | `Implementing` | engineer | - | `src/auth/`, `db/schema.sql` |
| `payment-gateway` | 결제 시스템 | `Planning` | strategist | `user-auth` | `src/payment/`, `db/schema.sql` |
| `product-search` | 상품 검색 | `Designing` | architect | - | `src/search/`, `index.html` |
```

### 훅 동작

1. **`user-auth` engineer 진입** → `db/schema.sql` 수정 시작
2. **`product-search` architect 진입** → `index.html` 수정 (충돌 없음)
3. **`payment-gateway` strategist 진입** → `/plan` 실행, `user-auth` 의존성 명시
4. **`user-auth` guardian 진입** (check) → 완료
5. **`payment-gateway` engineer 진입** → `db/schema.sql` 수정 시도
   - **경고**: `user-auth`가 이미 `db/schema.sql` 수정했음
   - **해결**: 병합 전략 선택 (순차 진행 또는 파일 분리)

---

## 6. 모범 사례 (Best Practices)

1. **의존성을 명시적으로 선언**: 암묵적 의존성은 피하고, `plan.md`에 명확히 기록
2. **영향 범위를 정확히 파악**: `design.md`의 `Affected Files/Modules`을 가능한 한 구체적으로 작성
3. **정기적으로 레지스트리 업데이트**: `librarian`은 매 단계 완료 후 `docs/analysis/features.md` 갱신
4. **충돌 감지 경고에 주의**: 훅이 경고를 출력하면 즉시 대응
5. **테스트 강화**: 병렬 진행 시 통합 테스트 및 E2E 테스트 비중 증가

---

## 7. 문제 해결 (Troubleshooting)

### Q: 의존성이 충족되지 않았는데도 기능을 진행하고 싶어요.
**A**: `docs/analysis/features.md`에서 해당 기능의 상태를 `Blocked`로 변경하고, 사유를 기록합니다. 이후 의존성이 충족되면 상태를 다시 변경합니다.

### Q: 파일 충돌이 감지되었지만 병렬 진행이 필수입니다.
**A**: 파일 분리 전략을 적용합니다. 예를 들어, `src/auth/` 디렉토리를 기능별로 세분화하여 각 기능이 독립적인 파일을 수정하도록 합니다.

### Q: 레지스트리 파일이 손상되었습니다.
**A**: Git 히스토리에서 이전 버전을 복구하거나, 현재 상태를 바탕으로 수동으로 재작성합니다.

---

## 참고

- [기능 레지스트리 (Feature Registry)](../analysis/features.md)
- [산출물 규약 (Artifact Convention)](../reference/artifact-convention.md)
- [아키텍처 (Architecture)](../reference/architecture.md)
