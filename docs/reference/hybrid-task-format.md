# 하이브리드 태스크 포맷 (Hybrid Task Format)

태스크 정의를 위한 두 가지 포맷을 지원합니다:

- **Markdown** (기본, 사람 친화적)
- **XML** (Claude 최적화, 구조화)

---

## 1. Markdown 포맷 (기본)

### 장점
- 사람이 읽고 쓰기 쉬움
- Git에서 diff 보기 좋음
- 빠른 편집 가능

### 예시

```markdown
# Task 001: Create login endpoint

**Wave:** 1
**Type:** implementation
**Priority:** high
**Depends:**

## Description

Implement the authentication login endpoint with JWT support.

## Files

- `src/auth/login.ts`
- `src/auth/types.ts`

## Requirements

- Use jose for JWT (not jsonwebtoken)
- Validate credentials against users table
- Return httpOnly cookie on success
- Rate limit: 5 requests per minute per IP

## Action

```bash
# Implementation steps
1. Install jose package
2. Create LoginRequest and LoginResponse types
3. Implement POST /auth/login endpoint
4. Add rate limiting middleware
```

## Acceptance Criteria

- Valid registration returns 201 with user ID
- Duplicate email returns 409
- Verification email sent successfully

## Verify

```bash
npm run test -- auth.test.ts
npm run lint
```

## Done

- Login endpoint working
- Tests passing
- Lint clean
```

---

## 2. XML 포맷 (Claude 최적화)

### 장점
- 구조화된 파싱 (기계 읽기 최적)
- 스키마 검증 가능
- Claude 토큰 효율 향상 (GSD 벤치마킹)
- 속성 기반 메타데이터

### 예시

```xml
<?xml version="1.0" encoding="UTF-8"?>
<task id="001" wave="1" depends="" type="implementation" priority="high">
  <title>Create login endpoint</title>
  <description>
    Implement the authentication login endpoint with JWT support.
  </description>
  <files>
    <file>src/auth/login.ts</file>
    <file>src/auth/types.ts</file>
  </files>
  <requirements>
    - Use jose for JWT (not jsonwebtoken)
    - Validate credentials against users table
    - Return httpOnly cookie on success
    - Rate limit: 5 requests per minute per IP
  </requirements>
  <action>
    1. Install jose package
    2. Create LoginRequest and LoginResponse types
    3. Implement POST /auth/login endpoint
    4. Add rate limiting middleware
  </action>
  <acceptance_criteria>
    - curl POST /auth/login returns 200 + Set-Cookie with valid credentials
    - curl POST /auth/login returns 401 with invalid credentials
    - Rate limiting blocks after 5 requests
  </acceptance_criteria>
  <verify>
    npm run test -- auth.test.ts
    npm run lint
  </verify>
  <done>
    - Login endpoint working
    - Tests passing
    - Lint clean
  </done>
</task>
```

---

## 3. 포맷 비교

| 특성 | Markdown | XML |
|------|:--------:|:---:|
| **사람 편집성** | ⭐⭐⭐⭐⭐ | ⭐⭐ |
| **기계 파싱** | ⭐⭐ | ⭐⭐⭐⭐⭐ |
| **스키마 검증** | ❌ | ✅ |
| **Git Diff** | ⭐⭐⭐⭐⭐ | ⭐⭐ |
| **Claude 효율** | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **중첩 구조** | ⭐⭐ | ⭐⭐⭐⭐⭐ |

---

## 4. 사용 가이드

### 태스크 작성

```
# Markdown으로 작성 (권장)
docs/specs/<slug>/tasks/001-create-login.md

# XML로 변환 필요 시
xml_to_md tasks/001.xml tasks/001.md
```

### 태스크 로드 (자동 감지)

```bash
# 자동으로 포맷 감지
load_task docs/specs/user-auth/tasks/001-create-login.md

# 모든 태스크 로드
load_all_tasks docs/specs/user-auth/tasks/
```

### 포맷 변환

```bash
# MD → XML
md_to_xml tasks/001.md tasks/001.xml

# XML → MD
xml_to_md tasks/001.xml tasks/001.md

# XML 검증
validate_task_xml tasks/001.xml
```

---

## 5. 파일 위치

```
docs/
├── schemas/
│   └── task.xsd           # XML 스키마 정의
└── specs/
    └── <feature-slug>/
        └── tasks/
            ├── 001-*.md   # Markdown 태스크 (기본)
            ├── 002-*.md
            └── ...         # 또는 .xml
```

---

## 6. XML 스키마 (task.xsd)

주요 속성:
- `id` (필수): 태스크 고유 ID
- `wave` (선택, 기본=1): Wave 번호
- `depends` (선택): 의존 태스크 ID (쉼표 구분)
- `type` (선택): implementation | testing | documentation | refactoring | research | review
- `priority` (선택): critical | high | medium | low

주요 요소:
- `title` (필수)
- `description`
- `files` (파일 목록)
- `requirements`
- `action`
- `acceptance_criteria`
- `verify`
- `done`
- `notes`

---

## 7. Wave Executor 통합

Wave Executor는 자동으로 포맷을 감지합니다:

```bash
# waves.yaml에서 태스크 파일 참조
waves:
  - wave: 1
    tasks:
      - file: tasks/001-create-login.md    # MD 또는 XML
      - file: tasks/002-create-register.xml  # 혼용 가능
```

---

## 8. 권장 워크플로우

1. **개발 중**: Markdown으로 작성 (편의성)
2. **실행 전**: XML로 변환 (선택, 검증 필요 시)
3. **CI/CD**: XML로 저장 (일관성)

또는:

1. **처음부터 XML**: 대규모 프로젝트, 팀 작업
2. **검증**: 스키마로 자동 검증

---

## 참고

- GSD XML Prompt Format (벤치마킹)
- task.xsd 스키마 정의
- hooks/lib/task-format.sh (변환 라이브러리)
