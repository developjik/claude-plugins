# P1 Enhancement — High Priority 구현 계획

## 개요

P0 Foundation이 완료된 후, P1은 실무에서 즉시 활용 가능한 고급 기능들을 추가합니다.

---

## P1-1: 2단계 리뷰 시스템 (Two-Stage Review)

### 목표
superpowers의 "two-stage review" 패턴을 완전히 구현합니다.

### 현재 상태
- `check/SKILL.md`에 개념 정의됨
- 실제 구현 함수 누락:
  - `verify_spec_compliance()` — Stage 1
  - `spawn_subagent_for_review()` — Stage 2

### 구현 내용

#### 1.1 Stage 1: 스펙 준수 검증 (`verify_spec_compliance`)

```bash
# lib/review-engine.sh

verify_spec_compliance() {
  local project_root="${1:-}"
  local feature_slug="${2:-}"

  # design.md 파싱
  local design_file="${project_root}/docs/specs/${feature_slug}/design.md"

  # 검증 항목
  local checks='{
    "files_created": [],
    "files_missing": [],
    "api_signatures": [],
    "data_models": [],
    "dependencies": []
  }'

  # 1. 파일 생성 확인
  # design.md의 "파일 변경" 섹션에서 예상 파일 목록 추출
  # 실제 파일 존재 여부 확인

  # 2. API 시그니처 확인
  # design.md의 "API 설계" 섹션과 실제 코드 비교

  # 3. 일치도 계산
  local match_rate=$(calculate_match_rate "$checks")

  echo "{\"match_rate\": $match_rate, \"checks\": $checks}"
}
```

#### 1.2 Stage 2: 코드 품질 리뷰 (`spawn_subagent_for_review`)

```bash
# lib/review-engine.sh

spawn_subagent_for_review() {
  local project_root="${1:-}"
  local feature_slug="${2:-}"

  # 새 서브에이전트 스폰 (신선한 컨텍스트)
  local task_file=$(mktemp)
  cat > "$task_file" << 'EOF'
  # Code Quality Review Task

  Review the implementation for:
  - SOLID principles compliance
  - DRY (Don't Repeat Yourself)
  - Function length (<20 lines)
  - Cyclomatic complexity (<10)
  - Error handling quality
  - Security best practices

  Output: JSON report with scores and issues
  EOF

  local subagent_id=$(spawn_subagent "$task_file" "$project_root" "sonnet" "code_review")

  # Agent 툴로 실행
  # 결과 집계
}
```

#### 1.3 구현 파일

| 파일 | 내용 | 라인 수 |
|------|------|---------|
| `hooks/lib/review-engine.sh` | 2단계 리뷰 엔진 | ~350 |
| `hooks/__tests__/review-engine.test.sh` | 테스트 | ~200 |

---

## P1-2: Skill 평가 프레임워크 (Skill Evaluation)

### 목표
각 스킬의 실행 품질을 추적하고 개선점을 식별합니다.

### 구현 내용

#### 2.1 메트릭 수집

```bash
# lib/skill-evaluation.sh

# 수집 항목
readonly METRICS=(
  "success_rate"      # 성공률
  "execution_time"    # 실행 시간
  "error_count"       # 에러 횟수
  "retry_count"       # 재시도 횟수
  "user_satisfaction" # 사용자 만족도 (명시적 피드백)
)

record_skill_execution() {
  local skill_name="${1:-}"
  local status="${2:-}"  # success|failure|partial
  local duration_ms="${3:-}"
  local error_msg="${4:-}"

  local record_file="${PROJECT_ROOT}/.harness/metrics/${skill_name}.jsonl"

  jq -c -n \
    --arg skill "$skill_name" \
    --arg status "$status" \
    --argjson duration "$duration_ms" \
    --arg error "$error_msg" \
    --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    '{
      skill: $skill,
      status: $status,
      duration_ms: $duration,
      error: $error,
      timestamp: $ts
    }' >> "$record_file"
}
```

#### 2.2 대시보드 생성

```bash
generate_skill_dashboard() {
  local project_root="${1:-}"
  local output_file="${project_root}/.harness/metrics/dashboard.md"

  # 각 스킬별 통계 집계
  # Markdown 리포트 생성
}
```

#### 2.3 구현 파일

| 파일 | 내용 | 라인 수 |
|------|------|---------|
| `hooks/lib/skill-evaluation.sh` | 평가 프레임워크 | ~300 |
| `hooks/__tests__/skill-evaluation.test.sh` | 테스트 | ~150 |

---

## P1-3: 크래시 복구 & 포렌식 (Crash Recovery & Forensics)

### 목표
크래시, stuck 상태에서 복구하고 원인을 분석합니다.

### 현재 상태
- `skills/recover/SKILL.md` 정의됨
- `lib/state-machine.sh`에 스냅샷/롤백 기능 구현됨
- 실제 복구 로직 미구현

### 구현 내용

#### 3.1 Stuck 상태 감지

```bash
# lib/crash-recovery.sh

detect_stuck_state() {
  local project_root="${1:-}"
  local max_iterations="${2:-10}"
  local max_time_minutes="${3:-30}"

  local state=$(get_state "$project_root")
  local iteration_count=$(echo "$state" | jq -r '.iteration_count // 0')
  local last_transition=$(echo "$state" | jq -r '.last_transition_at')

  # 1. 반복 횟수 초과
  if [[ "$iteration_count" -ge "$max_iterations" ]]; then
    echo "{\"stuck\": true, \"reason\": \"max_iterations\", \"count\": $iteration_count}"
    return 0
  fi

  # 2. 동일 페이즈에서 장시간 대기
  local now=$(date +%s)
  local last_ts=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$last_transition" +%s 2>/dev/null || echo 0)
  local elapsed=$(( (now - last_ts) / 60 ))

  if [[ "$elapsed" -ge "$max_time_minutes" ]]; then
    echo "{\"stuck\": true, \"reason\": \"timeout\", \"elapsed_minutes\": $elapsed}"
    return 0
  fi

  # 3. 루프 패턴 감지 (check → implement → check → ...)
  local history=$(get_transition_history "$project_root" 10)
  local loop_pattern=$(detect_loop_pattern "$history")

  if [[ -n "$loop_pattern" ]]; then
    echo "{\"stuck\": true, \"reason\": \"loop\", \"pattern\": \"$loop_pattern\"}"
    return 0
  fi

  echo "{\"stuck\": false}"
  return 1
}
```

#### 3.2 크래시 분석

```bash
analyze_crash() {
  local project_root="${1:-}"

  local report='{
    "timestamp": "'$(date -u '+%Y-%m-%dT%H:%M:%SZ')'",
    "current_state": {},
    "last_transitions": [],
    "snapshots": [],
    "diagnosis": "",
    "recommendations": []
  }'

  # 1. 현재 상태 분석
  # 2. 전환 히스토리 분석
  # 3. 근본 원인 추정
  # 4. 복구 옵션 제안

  echo "$report"
}
```

#### 3.3 구현 파일

| 파일 | 내용 | 라인 수 |
|------|------|---------|
| `hooks/lib/crash-recovery.sh` | 크래시 복구 | ~400 |
| `hooks/__tests__/crash-recovery.test.sh` | 테스트 | ~200 |

---

## P1-4: 브라우저 테스트 통합 (Browser Testing)

### 목표
Playwright를 활용한 E2E 테스트를 자동 설정 및 실행합니다.

### 현재 상태
- `lib/verification-classes.sh`에 Class D (E2E) 기본 구현됨
- 자동 설정 및 리포팅 미흡

### 구현 내용

#### 4.1 Playwright 자동 설정

```bash
# lib/browser-testing.sh

setup_playwright() {
  local project_root="${1:-}"
  local browser="${2:-chromium}"  # chromium|firefox|webkit

  # 1. Playwright 설치 확인
  if ! grep -q '"@playwright/test"' "${project_root}/package.json" 2>/dev/null; then
    echo '{"error": "playwright_not_installed", "suggestion": "npm install -D @playwright/test"}'
    return 1
  fi

  # 2. 브라우저 설치 확인
  if ! npx playwright --version &>/dev/null; then
    npx playwright install "$browser"
  fi

  # 3. 설정 파일 생성 (없으면)
  if [[ ! -f "${project_root}/playwright.config.ts" ]]; then
    generate_playwright_config "$project_root"
  fi
}
```

#### 4.2 테스트 실행 및 리포트

```bash
run_browser_tests() {
  local project_root="${1:-}"
  local test_filter="${2:-}"
  local browser="${3:-chromium}"

  setup_playwright "$project_root" "$browser"

  # 테스트 실행
  local result=$(npx playwright test \
    --project="$browser" \
    --reporter=json \
    ${test_filter:+--grep="$test_filter"} \
    2>&1)

  # 결과 파싱 및 정규화
  parse_playwright_results "$result"
}
```

#### 4.3 구현 파일

| 파일 | 내용 | 라인 수 |
|------|------|---------|
| `hooks/lib/browser-testing.sh` | 브라우저 테스트 | ~350 |
| `hooks/__tests__/browser-testing.test.sh` | 테스트 | ~150 |

---

## 구현 순서

```
Week 1:
├── P1-1: 2단계 리뷰 시스템 (2일)
│   ├── review-engine.sh
│   └── 테스트
│
├── P1-2: Skill 평가 프레임워크 (1일)
│   ├── skill-evaluation.sh
│   └── 테스트
│
Week 2:
├── P1-3: 크래시 복구 & 포렌식 (2일)
│   ├── crash-recovery.sh
│   └── 테스트
│
└── P1-4: 브라우저 테스트 통합 (1일)
    ├── browser-testing.sh
    └── 테스트
```

---

## 의존성

```
P1-1 (2단계 리뷰)
  └── P0-2 (subagent-spawner.sh) ✅
  └── P0-3 (state-machine.sh) ✅

P1-2 (Skill 평가)
  └── P0-3 (state-machine.sh) ✅

P1-3 (크래시 복구)
  └── P0-3 (state-machine.sh) ✅

P1-4 (브라우저 테스트)
  └── P0-1 (test-runner.sh) ✅
  └── P0-1 (verification-classes.sh) ✅
```

---

## 완료 기준

### P1-1
- [ ] `verify_spec_compliance()` 구현
- [ ] `spawn_subagent_for_review()` 구현
- [ ] 일치도 90% 이상 시 통과 판정
- [ ] 테스트 커버리지 > 80%

### P1-2
- [ ] 메트릭 수집 기능
- [ ] 대시보드 생성
- [ ] 테스트 커버리지 > 80%

### P1-3
- [ ] Stuck 감지 (반복, 타임아웃, 루프)
- [ ] 크래시 분석 리포트
- [ ] 복구 옵션 제안
- [ ] 테스트 커버리지 > 80%

### P1-4
- [ ] Playwright 자동 설정
- [ ] 테스트 실행 및 결과 파싱
- [ ] HTML 리포트 생성
- [ ] 테스트 커버리지 > 80%
