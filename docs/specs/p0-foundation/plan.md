# P0 Foundation Improvements - Implementation Plan

> Status: Partial
>
> 이 문서는 초기 구현 계획서입니다. 현재 저장소에는 `test-runner.sh`, `verification-classes.sh`, `subagent-spawner.sh`, `state-machine.sh`가 모두 존재하지만, 서브에이전트 실행 계약과 일부 통합 품질은 후속 이슈에서 계속 보강 중입니다.

## Overview

이 문서는 harness-engineering 프로젝트의 P0 (Critical) 개선사항에 대한 상세 구현 계획입니다.

## Current Implementation Snapshot

| Area | Current Status | Notes |
|------|----------------|-------|
| P0-1 테스트 실행 통합 | Implemented | 다중 프레임워크 감지와 테스트 실행 함수 존재 |
| P0-2 서브에이전트 스포닝 | Partial | 상태 파일/컨텍스트 생성은 구현, 실제 실행 브리지 보강 필요 |
| P0-3 상태 머신 엔진 | Implemented | 상태 전이, 스냅샷, 롤백 관련 모듈 존재 |

| ID | 개선사항 | 노력 | 출처 | 우선순위 |
|----|---------|-----|------|---------|
| P0-1 | 테스트 실행 통합 | 3일 | superpowers | Critical |
| P0-2 | 실제 서브에이전트 스포닝 | 5일 | superpowers/gsd-2 | Critical |
| P0-3 | 상태 머신 엔진 | 4일 | gsd-2 | Critical |

**총 예상 노력:** 12일 (약 2.5주)

---

## P0-1: 테스트 실행 통합 (3일)

### 목표
Check 스킬이 실제 테스트를 실행하고 결과를 분석하도록 개선합니다.

### 현재 상태
- `skills/check/SKILL.md`: 검증 클래스와 2단계 리뷰 흐름이 문서화되어 있음
- `hooks/lib/test-runner.sh`: 다중 프레임워크 테스트 실행 함수가 구현되어 있음
- 후속 과제: 패키지 매니저 다양성, 감지 정확도, 통합 판정 품질 보강

### 구현 계획

#### Day 1: 테스트 러너 라이브러리 구현

**파일: `hooks/lib/test-runner.sh`**

```bash
#!/usr/bin/env bash
# test-runner.sh — 테스트 실행 및 결과 분석
# DEPENDENCIES: json-utils.sh, logging.sh

# ============================================================================
# 테스트 프레임워크 감지
# Usage: detect_test_framework <project_root>
# Returns: jest|pytest|go_test|cargo_test|maven|gradle|none
# ============================================================================
detect_test_framework() {
  local project_root="${1:-}"

  # JavaScript/TypeScript
  if [[ -f "${project_root}/package.json" ]]; then
    if grep -q '"jest"' "${project_root}/package.json" 2>/dev/null; then
      echo "jest"
      return 0
    fi
    if grep -q '"vitest"' "${project_root}/package.json" 2>/dev/null; then
      echo "vitest"
      return 0
    fi
  fi

  # Python
  if [[ -f "${project_root}/pytest.ini" ]] || \
     [[ -f "${project_root}/pyproject.toml" ]] || \
     [[ -f "${project_root}/setup.cfg" ]]; then
    echo "pytest"
    return 0
  fi

  # Go
  if [[ -f "${project_root}/go.mod" ]]; then
    echo "go_test"
    return 0
  fi

  # Rust
  if [[ -f "${project_root}/Cargo.toml" ]]; then
    echo "cargo_test"
    return 0
  fi

  # Java/Maven
  if [[ -f "${project_root}/pom.xml" ]]; then
    echo "maven"
    return 0
  fi

  # Java/Gradle
  if [[ -f "${project_root}/build.gradle" ]] || \
     [[ -f "${project_root}/build.gradle.kts" ]]; then
    echo "gradle"
    return 0
  fi

  echo "none"
}

# ============================================================================
# 테스트 실행
# Usage: run_tests <project_root> [test_filter]
# Returns: JSON with pass/fail/skip counts
# ============================================================================
run_tests() {
  local project_root="${1:-}"
  local test_filter="${2:-}"
  local framework
  framework=$(detect_test_framework "$project_root")

  local results_dir="${project_root}/.harness/test-results"
  mkdir -p "$results_dir"

  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)
  local results_file="${results_dir}/${timestamp}.json"

  case "$framework" in
    jest|vitest)
      run_js_tests "$project_root" "$test_filter" "$results_file"
      ;;
    pytest)
      run_pytest_tests "$project_root" "$test_filter" "$results_file"
      ;;
    go_test)
      run_go_tests "$project_root" "$test_filter" "$results_file"
      ;;
    cargo_test)
      run_cargo_tests "$project_root" "$test_filter" "$results_file"
      ;;
    maven|gradle)
      run_java_tests "$project_root" "$framework" "$test_filter" "$results_file"
      ;;
    *)
      echo '{"error": "no_test_framework", "passed": 0, "failed": 0, "skipped": 0}'
      return 1
      ;;
  esac
}

# ============================================================================
# 테스트 결과 분석
# Usage: parse_test_results <results_file>
# Returns: JSON with summary
# ============================================================================
parse_test_results() {
  local results_file="${1:-}"

  if [[ ! -f "$results_file" ]]; then
    echo '{"error": "results_not_found"}'
    return 1
  fi

  cat "$results_file"
}

# ============================================================================
# 커버리지 리포트 생성
# Usage: generate_coverage_report <project_root>
# ============================================================================
generate_coverage_report() {
  local project_root="${1:-}"
  local framework
  framework=$(detect_test_framework "$project_root")

  case "$framework" in
    jest)
      cd "$project_root" && npm run test:coverage -- --reporter=json-summary 2>/dev/null || true
      ;;
    vitest)
      cd "$project_root" && npx vitest run --coverage.reporter=json 2>/dev/null || true
      ;;
    pytest)
      cd "$project_root" && pytest --cov --cov-report=json 2>/dev/null || true
      ;;
    go_test)
      cd "$project_root" && go test -coverprofile=coverage.out ./... 2>/dev/null || true
      ;;
  esac
}
```

#### Day 2: Check 스킬 통합

**수정 파일: `skills/check/SKILL.md`**

```markdown
---
name: check
description: |
  Use after implementation. Execute tests, review code against plan/design,
  verify consistency, auto-fix gaps.
  ...
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, Agent
---

# Check Skill — PDCA 4단계 (Check + Iterate)

## 프로세스

### 1. 테스트 실행 (NEW)
프로젝트의 테스트 프레임워크를 자동 감지하고 실행합니다.

\`\`\`bash
# 테스트 프레임워크 감지
FRAMEWORK=$(detect_test_framework "$PROJECT_ROOT")

# 테스트 실행
RESULTS=$(run_tests "$PROJECT_ROOT" "$FEATURE_SLUG")

# 결과 분석
TOTAL=$(echo "$RESULTS" | jq '.total // 0')
PASSED=$(echo "$RESULTS" | jq '.passed // 0')
FAILED=$(echo "$RESULTS" | jq '.failed // 0')
\`\`\`

### 2. 2단계 리뷰 (NEW from superpowers)

#### Stage 1: 스펙 준수 검증
design.md의 각 항목이 구현되었는지 확인:
- [ ] 모든 파일이 생성되었는가?
- [ ] API 시그니처가 일치하는가?
- [ ] 데이터 모델이 정확한가?

#### Stage 2: 코드 품질 리뷰 (Fresh Subagent)
새로운 서브에이전트를 스폰하여 독립적으로 리뷰:
- [ ] SOLID 원칙 준수
- [ ] 중복 코드 없음
- [ ] 에러 처리 적절

### 3-5. (기존 프로세스 유지)
```

#### Day 3: 검증 클래스 시스템

**파일: `hooks/lib/verification-classes.sh`**

```bash
#!/usr/bin/env bash
# verification-classes.sh — 검증 클래스 정의
# GSD-2의 verification classes 벤치마킹

# ============================================================================
# 검증 클래스 정의
# ============================================================================

# Class A: 정적 분석 (실행 불필요)
run_verification_class_a() {
  local project_root="${1:-}"
  local results=()

  # 린트 검사
  if [[ -f "${project_root}/package.json" ]]; then
    npm run lint --prefix "$project_root" 2>/dev/null && results+=("lint:pass") || results+=("lint:fail")
  fi

  # 타입 체크
  if [[ -f "${project_root}/tsconfig.json" ]]; then
    npx tsc --noEmit --project "$project_root" 2>/dev/null && results+=("typecheck:pass") || results+=("typecheck:fail")
  fi

  printf '%s\n' "${results[@]}"
}

# Class B: 유닛 테스트 (30초 이내)
run_verification_class_b() {
  local project_root="${1:-}"
  run_tests "$project_root" "" "unit"
}

# Class C: 통합 테스트 (5분 이내)
run_verification_class_c() {
  local project_root="${1:-}"
  run_tests "$project_root" "" "integration"
}

# Class D: E2E 테스트 (15분 이내)
run_verification_class_d() {
  local project_root="${1:-}"
  run_tests "$project_root" "" "e2e"
}

# ============================================================================
# 검증 실행
# Usage: run_verification <project_root> <classes> [thorough]
# classes: a, ab, abc, abcd
# ============================================================================
run_verification() {
  local project_root="${1:-}"
  local classes="${2:-ab}"
  local thorough="${3:-false}"

  if [[ "$thorough" == "true" ]]; then
    classes="abcd"
  fi

  local all_results=()

  [[ "$classes" == *a* ]] && all_results+=("Class A: $(run_verification_class_a "$project_root")")
  [[ "$classes" == *b* ]] && all_results+=("Class B: $(run_verification_class_b "$project_root")")
  [[ "$classes" == *c* ]] && all_results+=("Class C: $(run_verification_class_c "$project_root")")
  [[ "$classes" == *d* ]] && all_results+=("Class D: $(run_verification_class_d "$project_root")")

  printf '%s\n' "${all_results[@]}"
}
```

### 산출물
1. `hooks/lib/test-runner.sh` - 테스트 실행 라이브러리
2. `hooks/lib/verification-classes.sh` - 검증 클래스 시스템
3. `skills/check/SKILL.md` - 업데이트된 Check 스킬
4. `.harness/test-results/` - 테스트 결과 저장 디렉토리

---

## P0-2: 실제 서브에이전트 스포닝 (5일)

### 목표
Wave executor가 시뮬레이션이 아닌 실제 서브에이전트를 스폰하여 병렬 실행합니다.

### 현재 상태
- `hooks/lib/subagent-spawner.sh`: 서브에이전트 컨텍스트/상태 파일 생성 로직 구현됨
- `hooks/lib/wave-executor.sh`: 서브에이전트 파라미터 생성과 결과 집계 흐름이 구현됨
- 후속 과제: 실제 실행 어댑터와 라이프사이클 계약을 더 명확히 분리

### 구현 계획

#### Day 1: 서브에이전트 스포너 인터페이스 설계

**파일: `hooks/lib/subagent-spawner.sh`**

```bash
#!/usr/bin/env bash
# subagent-spawner.sh — 서브에이전트 스포닝 시스템
# superpowers/GSD-2 벤치마킹

set -euo pipefail

# ============================================================================
# 설정
# ============================================================================

readonly SUBAGENT_DIR=".harness/subagents"
readonly MAX_SUBAGENTS=4
readonly SUBAGENT_TIMEOUT=600  # 10분

# ============================================================================
# 서브에이전트 스폰
# Usage: spawn_subagent <task_file> <project_root> [model]
# Returns: subagent_id
# ============================================================================
spawn_subagent() {
  local task_file="${1:-}"
  local project_root="${2:-}"
  local model="${3:-sonnet}"  # opus, sonnet, haiku

  local subagent_id="subagent_$(date +%s)_$$"
  local subagent_dir="${project_root}/${SUBAGENT_DIR}/${subagent_id}"

  mkdir -p "$subagent_dir"

  # 태스크 파일 복사
  cp "$task_file" "${subagent_dir}/task.md"

  # 컨텍스트 파일 준비
  prepare_subagent_context "$project_root" "$subagent_dir"

  # 상태 파일 생성
  cat > "${subagent_dir}/state.json" << EOF
{
  "id": "$subagent_id",
  "status": "pending",
  "model": "$model",
  "task_file": "$task_file",
  "created_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "started_at": null,
  "completed_at": null,
  "result": null
}
EOF

  echo "$subagent_id"
}

# ============================================================================
# 서브에이전트 컨텍스트 준비
# ============================================================================
prepare_subagent_context() {
  local project_root="${1:-}"
  local subagent_dir="${2:-}"

  # 최소 컨텍스트만 전달 (Context Engineering)
  local context_files=(
    "PROJECT.md"
    "STATE.md"
    "docs/specs/*/design.md"
  )

  local context_content="# Subagent Context\n\n"

  for pattern in "${context_files[@]}"; do
    while IFS= read -r file; do
      if [[ -f "$file" ]]; then
        context_content+="## File: $file\n\n"
        context_content+="$(cat "$file")\n\n"
      fi
    done < <(find "$project_root" -name "$pattern" -type f 2>/dev/null | head -5)
  done

  echo -e "$context_content" > "${subagent_dir}/context.md"
}

# ============================================================================
# 서브에이전트 실행
# Usage: execute_subagent <subagent_id> <project_root>
# ============================================================================
execute_subagent() {
  local subagent_id="${1:-}"
  local project_root="${2:-}"
  local subagent_dir="${project_root}/${SUBAGENT_DIR}/${subagent_id}"

  if [[ ! -d "$subagent_dir" ]]; then
    echo "ERROR: Subagent not found: $subagent_id" >&2
    return 1
  fi

  # 상태 업데이트: running
  update_subagent_state "$subagent_dir" "running"

  # 실제 구현: Claude Code Agent API 호출
  # 이 부분은 Claude Code의 Agent 툴을 사용하여 구현
  # 현재는 플레이스홀더

  local task_content
  task_content=$(cat "${subagent_dir}/task.md")

  # 결과 저장
  cat > "${subagent_dir}/result.md" << EOF
# Subagent Result

## Task
$task_content

## Status
completed

## Output
[Subagent execution output will be here]
EOF

  # 상태 업데이트: completed
  update_subagent_state "$subagent_dir" "completed"
}

# ============================================================================
# 상태 업데이트
# ============================================================================
update_subagent_state() {
  local subagent_dir="${1:-}"
  local status="${2:-}"

  local state_file="${subagent_dir}/state.json"
  local timestamp
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  if command -v jq &>/dev/null; then
    local tmp_file="${subagent_dir}/state.tmp"
    jq --arg status "$status" --arg ts "$timestamp" \
      '.status = $status | .updated_at = $ts' \
      "$state_file" > "$tmp_file" && mv "$tmp_file" "$state_file"
  fi
}

# ============================================================================
# 서브에이전트 결과 집계
# ============================================================================
aggregate_subagent_results() {
  local project_root="${1:-}"
  local subagent_ids="${2:-}"  # comma-separated

  local results_dir="${project_root}/.harness/results"
  mkdir -p "$results_dir"

  local all_results="[]"

  for subagent_id in $(echo "$subagent_ids" | tr ',' ' '); do
    local result_file="${project_root}/${SUBAGENT_DIR}/${subagent_id}/result.md"
    if [[ -f "$result_file" ]]; then
      all_results=$(echo "$all_results" | jq --arg id "$subagent_id" \
        --arg content "$(cat "$result_file")" \
        '. += [{"id": $id, "content": $content}]')
    fi
  done

  echo "$all_results" > "${results_dir}/aggregated_$(date +%s).json"
  echo "$all_results"
}
```

#### Day 2: Wave Executor 개선

**수정 파일: `hooks/lib/wave-executor.sh`**

```bash
# 기존 execute_task 함수 교체

execute_task() {
  local task_file="${1:-}"
  local project_root="${2:-}"
  local model="${3:-sonnet}"

  local log_dir="${project_root}/.harness/logs"
  mkdir -p "$log_dir"

  local task_name
  task_name=$(basename "$task_file" .md)

  log_event "$project_root" "INFO" "task_start" "Spawning subagent for task" "\"task\":\"$task_name\""

  # 서브에이전트 스폰
  local subagent_id
  subagent_id=$(spawn_subagent "$task_file" "$project_root" "$model")

  log_event "$project_root" "INFO" "subagent_spawned" "Subagent created" "\"subagent_id\":\"$subagent_id\",\"task\":\"$task_name\""

  # 서브에이전트 실행 (실제 Agent 툴 호출은 Claude Code에서 수행)
  execute_subagent "$subagent_id" "$project_root"

  local result=$?

  if [[ $result -eq 0 ]]; then
    log_event "$project_root" "INFO" "task_complete" "Task completed successfully" "\"task\":\"$task_name\",\"subagent_id\":\"$subagent_id\""
    echo "$subagent_id"
  else
    log_event "$project_root" "ERROR" "task_failed" "Task execution failed" "\"task\":\"$task_name\",\"subagent_id\":\"$subagent_id\""
    return 1
  fi
}

# 병렬 Wave 실행 (개선)
execute_wave() {
  local wave_num="${1:-}"
  local tasks_json="${2:-}"
  local project_root="${3:-}"
  local parallel="${4:-true}"

  local state_dir="${project_root}/.harness/state"
  local completed_file="${state_dir}/completed-tasks.txt"

  mkdir -p "$state_dir"

  log_event "$project_root" "INFO" "wave_start" "Starting wave with real subagents" "\"wave\":${wave_num}"

  local subagent_ids=()

  if [[ "$parallel" == "true" ]]; then
    # 병렬 실행: 각 태스크마다 서브에이전트 스폰
    for task_file in $(echo "$tasks_json" | jq -r '.[]?.file // empty'); do
      if [[ -f "${project_root}/${task_file}" ]]; then
        local subagent_id
        subagent_id=$(execute_task "${project_root}/${task_file}" "$project_root" "sonnet") &
        subagent_ids+=("$subagent_id")
      fi
    done

    # 모든 서브에이전트 완료 대기
    wait

    # 결과 집계
    aggregate_subagent_results "$project_root" "$(IFS=,; echo "${subagent_ids[*]}")"
  else
    # 순차 실행
    for task_file in $(echo "$tasks_json" | jq -r '.[]?.file // empty'); do
      if [[ -f "${project_root}/${task_file}" ]]; then
        local subagent_id
        subagent_id=$(execute_task "${project_root}/${task_file}" "$project_root" "sonnet")
        subagent_ids+=("$subagent_id")
      fi
    done
  fi

  # 완료된 태스크 기록
  for subagent_id in "${subagent_ids[@]}"; do
    echo "$subagent_id" >> "$completed_file"
  done

  log_event "$project_root" "INFO" "wave_complete" "Wave completed" "\"wave\":${wave_num},\"subagents\":${#subagent_ids[@]}"
}
```

#### Day 3-4: Agent 툴 연동

**새 파일: `skills/delegate/SKILL.md`**

```markdown
---
name: delegate
description: |
  Spawn a fresh subagent for a single atomic task.
  Use for parallel execution of independent tasks.
user-invocable: true
argument-hint: <task-file> [model]
allowed-tools: Agent, Read, Write, Bash
---

# Delegate Skill — 서브에이전트 태스크 위임

## 용도
독립적인 태스크를 신선한 컨텍스트의 서브에이전트에게 위임합니다.

## 프로세스

### 1. 태스크 분석
태스크 파일을 읽고 필요한 컨텍스트를 식별합니다.

### 2. 서브에이전트 스폰
Agent 툴을 사용하여 새로운 서브에이전트를 생성합니다.

```bash
# 최소 컨텍스트만 전달
CONTEXT_FILES=(
  "PROJECT.md"
  "STATE.md"
  "docs/specs/$FEATURE_SLUG/design.md"
  "$TASK_FILE"
)
```

### 3. 실행 및 결과 수집
서브에이전트가 태스크를 완료하면 결과를 집계합니다.

## 모델 선택
- `opus`: 복잡한 아키텍처 결정, 보안 검토
- `sonnet`: 일반적인 구현 작업
- `haiku`: 간단한 문서화, 포맷팅

## 출력
```
🤖 Subagent: {subagent_id}
📊 Task: {task_name}
⏱️ Duration: {duration}s
✅ Status: completed
📝 Result: {result_summary}
```
```

#### Day 5: 통합 테스트

**파일: `hooks/__tests__/subagent.test.sh`**

```bash
#!/usr/bin/env bash
# subagent.test.sh — 서브에이전트 시스템 테스트

source "$(dirname "$0")/../lib/subagent-spawner.sh"

setup() {
  TEST_DIR=$(mktemp -d)
  mkdir -p "${TEST_DIR}/.harness"
}

teardown() {
  rm -rf "$TEST_DIR"
}

test_spawn_subagent() {
  local task_file="${TEST_DIR}/task.md"
  echo "# Test Task" > "$task_file"

  local subagent_id
  subagent_id=$(spawn_subagent "$task_file" "$TEST_DIR" "sonnet")

  assert_match "subagent_[0-9]+_[0-9]+" "$subagent_id"
  assert_file_exists "${TEST_DIR}/.harness/subagents/${subagent_id}/state.json"
}

test_prepare_subagent_context() {
  # ... 테스트 코드
}

# 테스트 실행
run_tests
```

### 산출물
1. `hooks/lib/subagent-spawner.sh` - 서브에이전트 스포닝 라이브러리
2. `skills/delegate/SKILL.md` - Delegate 스킬
3. `hooks/lib/wave-executor.sh` - 개선된 Wave Executor
4. `hooks/__tests__/subagent.test.sh` - 통합 테스트

---

## P0-3: 상태 머신 엔진 (4일)

### 목표
파일 기반 상태를 상태 머신으로 전환하여 롤백, 크래시 복구, 감사 가능하게 합니다.

### 현재 상태
- `hooks/lib/state-machine.sh`: 상태 전이, 스냅샷, 롤백 로직이 구현됨
- `.harness/engine/` 하위에 상태 파일과 전환 기록을 저장함
- 후속 과제: 다른 모듈과의 인터페이스 정리 및 문서 정확도 보강

### 구현 계획

#### Day 1: 상태 머신 설계

**파일: `hooks/lib/state-machine.sh`**

```bash
#!/usr/bin/env bash
# state-machine.sh — PDCA 상태 머신 엔진
# GSD-2 벤치마킹: Single-writer state engine

set -euo pipefail

# ============================================================================
# 상태 머신 정의
# ============================================================================

# PDCA 단계
readonly PDCA_PHASES=("clarify" "plan" "design" "implement" "check" "wrapup")

# 유효한 전환 (from -> to)
declare -A VALID_TRANSITIONS=(
  ["clarify:plan"]="true"
  ["plan:design"]="true"
  ["design:implement"]="true"
  ["implement:check"]="true"
  ["check:wrapup"]="true"
  ["check:implement"]="true"  # iterate
  ["wrapup:clarify"]="true"   # new feature
)

# 전환 가드 (조건)
declare -A TRANSITION_GUARDS=(
  ["clarify:plan"]="design_doc_exists"
  ["plan:design"]="design_doc_complete"
  ["design:implement"]="atomic_tasks_defined"
  ["implement:check"]="code_written"
  ["check:wrapup"]="match_rate_90_percent"
  ["check:implement"]="match_rate_below_90"
)

# ============================================================================
# 상태 파일 경로
# ============================================================================
state_file() {
  local project_root="${1:-}"
  echo "${project_root}/.harness/engine/state.json"
}

transitions_file() {
  local project_root="${1:-}"
  echo "${project_root}/.harness/engine/transitions.jsonl"
}

snapshots_dir() {
  local project_root="${1:-}"
  echo "${project_root}/.harness/engine/snapshots"
}

# ============================================================================
# 상태 초기화
# ============================================================================
init_state_machine() {
  local project_root="${1:-}"
  local feature_slug="${2:-}"

  local engine_dir="${project_root}/.harness/engine"
  mkdir -p "$engine_dir" "$(snapshots_dir "$project_root")"

  local state_file
  state_file=$(state_file "$project_root")

  if [[ ! -f "$state_file" ]]; then
    cat > "$state_file" << EOF
{
  "version": "1.0",
  "feature_slug": "$feature_slug",
  "phase": "clarify",
  "previous_phase": null,
  "entered_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "agent": null,
  "iteration_count": 0,
  "check_results": null,
  "snapshots": [],
  "metadata": {}
}
EOF
    log_transition "$project_root" "init" "null" "clarify" "State machine initialized"
  fi
}

# ============================================================================
# 상태 조회
# ============================================================================
get_state() {
  local project_root="${1:-}"
  local state_file
  state_file=$(state_file "$project_root")

  if [[ -f "$state_file" ]]; then
    cat "$state_file"
  else
    echo '{"error": "state_not_initialized"}'
  fi
}

get_current_phase() {
  local project_root="${1:-}"
  get_state "$project_root" | jq -r '.phase // "unknown"'
}

# ============================================================================
# 전환 검증
# ============================================================================
can_transition() {
  local project_root="${1:-}"
  local from_phase="${2:-}"
  local to_phase="${3:-}"

  local transition_key="${from_phase}:${to_phase}"

  # 유효한 전환인지 확인
  if [[ -z "${VALID_TRANSITIONS[$transition_key]:-}" ]]; then
    echo "false:invalid_transition"
    return 1
  fi

  # 가드 조건 확인
  local guard="${TRANSITION_GUARDS[$transition_key]}"
  if [[ -n "$guard" ]]; then
    if ! check_guard "$project_root" "$guard"; then
      echo "false:guard_failed:$guard"
      return 1
    fi
  fi

  echo "true"
}

check_guard() {
  local project_root="${1:-}"
  local guard="${2:-}"

  case "$guard" in
    design_doc_exists)
      [[ -f "${project_root}/docs/specs/*/design.md" ]]
      ;;
    design_doc_complete)
      # design.md의 필수 섹션 확인
      local design_file
      design_file=$(find "${project_root}/docs/specs" -name "design.md" | head -1)
      [[ -f "$design_file" ]] && grep -q "## 구현 순서" "$design_file"
      ;;
    atomic_tasks_defined)
      # waves.yaml 존재 확인
      [[ -f "${project_root}/docs/specs/*/waves.yaml" ]]
      ;;
    code_written)
      # 소스 파일 변경사항 존재 확인
      git -C "$project_root" diff --quiet HEAD 2>/dev/null; [[ $? -ne 0 ]]
      ;;
    match_rate_90_percent)
      # check 결과에서 90% 이상인지 확인
      local state
      state=$(get_state "$project_root")
      local match_rate
      match_rate=$(echo "$state" | jq -r '.check_results.match_rate // 0')
      [[ $(echo "$match_rate >= 0.9" | bc -l) -eq 1 ]]
      ;;
    match_rate_below_90)
      local state
      state=$(get_state "$project_root")
      local match_rate
      match_rate=$(echo "$state" | jq -r '.check_results.match_rate // 0')
      [[ $(echo "$match_rate < 0.9" | bc -l) -eq 1 ]]
      ;;
    *)
      true
      ;;
  esac
}

# ============================================================================
# 상태 전환
# ============================================================================
transition_state() {
  local project_root="${1:-}"
  local to_phase="${2:-}"
  local reason="${3:-manual}"
  local actor="${4:-claude}"

  local state_file
  state_file=$(state_file "$project_root")

  local current_state
  current_state=$(get_state "$project_root")

  local from_phase
  from_phase=$(echo "$current_state" | jq -r '.phase')

  # 전환 가능 여부 확인
  local can_trans
  can_trans=$(can_transition "$project_root" "$from_phase" "$to_phase")

  if [[ "$can_trans" != true* ]]; then
    echo "ERROR: Cannot transition from $from_phase to $to_phase: $can_trans" >&2
    return 1
  fi

  # 스냅샷 생성 (롤백용)
  local snapshot_id
  snapshot_id=$(create_snapshot "$project_root" "$from_phase")

  # 상태 업데이트
  local timestamp
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  local new_state
  new_state=$(echo "$current_state" | jq \
    --arg to "$to_phase" \
    --arg from "$from_phase" \
    --arg ts "$timestamp" \
    --arg actor "$actor" \
    --arg snapshot "$snapshot_id" \
    '.previous_phase = $from |
     .phase = $to |
     .entered_at = $ts |
     .actor = $actor |
     .snapshots += [$snapshot] |
     .metadata.last_transition_reason = $reason')

  echo "$new_state" > "$state_file"

  # 전환 로그 기록
  log_transition "$project_root" "transition" "$from_phase" "$to_phase" "$reason"

  echo "SUCCESS: Transitioned from $from_phase to $to_phase"
}

# ============================================================================
# 스냅샷 시스템
# ============================================================================
create_snapshot() {
  local project_root="${1:-}"
  local phase="${2:-}"

  local snapshot_id="snap_${phase}_$(date +%s)"
  local snapshot_file
  snapshot_file="$(snapshots_dir "$project_root")/${snapshot_id}.json"

  # 현재 상태와 관련 파일들을 스냅샷
  local state
  state=$(get_state "$project_root")

  cat > "$snapshot_file" << EOF
{
  "id": "$snapshot_id",
  "phase": "$phase",
  "created_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "state": $state,
  "files": {}
}
EOF

  echo "$snapshot_id"
}

rollback_to_snapshot() {
  local project_root="${1:-}"
  local snapshot_id="${2:-}"

  local snapshot_file
  snapshot_file="$(snapshots_dir "$project_root")/${snapshot_id}.json"

  if [[ ! -f "$snapshot_file" ]]; then
    echo "ERROR: Snapshot not found: $snapshot_id" >&2
    return 1
  fi

  # 스냅샷에서 상태 복원
  local snapshot_state
  snapshot_state=$(jq '.state' "$snapshot_file")

  local state_file
  state_file=$(state_file "$project_root")
  echo "$snapshot_state" > "$state_file"

  log_transition "$project_root" "rollback" "unknown" \
    "$(echo "$snapshot_state" | jq -r '.phase')" \
    "Rolled back to $snapshot_id"

  echo "SUCCESS: Rolled back to $snapshot_id"
}

# ============================================================================
# 전환 로그
# ============================================================================
log_transition() {
  local project_root="${1:-}"
  local event="${2:-}"
  local from="${3:-}"
  local to="${4:-}"
  local reason="${5:-}"

  local transitions_file
  transitions_file=$(transitions_file "$project_root")

  local entry
  entry=$(jq -n \
    --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    --arg event "$event" \
    --arg from "$from" \
    --arg to "$to" \
    --arg reason "$reason" \
    '{timestamp: $ts, event: $event, from: $from, to: $to, reason: $reason}')

  echo "$entry" >> "$transitions_file"
}

# ============================================================================
# 크래시 복구
# ============================================================================
recover_state() {
  local project_root="${1:-}"

  local state_file
  state_file=$(state_file "$project_root")

  if [[ ! -f "$state_file" ]]; then
    echo "No state to recover"
    return 0
  fi

  # 마지막 전환 확인
  local transitions_file
  transitions_file=$(transitions_file "$project_root")

  if [[ -f "$transitions_file" ]]; then
    local last_transition
    last_transition=$(tail -1 "$transitions_file")

    echo "Last transition: $last_transition"
    echo "Current phase: $(get_current_phase "$project_root")"
  fi

  # 복구 가능한 스냅샷 목록
  echo "Available snapshots:"
  ls -la "$(snapshots_dir "$project_root")"/*.json 2>/dev/null || echo "No snapshots"
}
```

#### Day 2: 기존 코드 통합

**수정 파일: `hooks/lib/automation-level.sh`**

```bash
# should_approve_transition 함수 개선
# 상태 머신의 전환 가드와 연동

should_approve_transition() {
  local level="${1:-$DEFAULT_AUTOMATION_LEVEL}"
  local transition="${2:-}"
  local project_root="${3:-}"

  # 상태 머신에서 전환 가능 여부 확인
  local from_phase
  local to_phase
  from_phase=$(get_current_phase "$project_root")

  case "$transition" in
    clarify_to_plan) to_phase="plan" ;;
    plan_to_design) to_phase="design" ;;
    design_to_do) to_phase="implement" ;;
    do_to_check) to_phase="check" ;;
    check_to_wrapup) to_phase="wrapup" ;;
    *) return 0 ;;
  esac

  local can_trans
  can_trans=$(can_transition "$project_root" "$from_phase" "$to_phase")

  if [[ "$can_trans" != true* ]]; then
    echo "blocked:$can_trans"
    return 1
  fi

  # 자동화 레벨에 따른 승인 정책
  case "$level" in
    L0) echo "true" ;;
    L1)
      case "$transition" in
        check_to_wrapup) echo "false" ;;
        *) echo "true" ;;
      esac
      ;;
    L2)
      case "$transition" in
        clarify_to_plan|plan_to_design) echo "if_uncertain" ;;
        *) echo "false" ;;
      esac
      ;;
    L3|L4) echo "false" ;;
    *) echo "false" ;;
  esac
}
```

#### Day 3: 롤백 및 복구 UI

**새 파일: `skills/recover/SKILL.md`**

```markdown
---
name: recover
description: |
  Recover from crashed or stuck state. Analyze last transitions,
  offer rollback options.
user-invocable: true
argument-hint: [--rollback <snapshot-id>]
allowed-tools: Read, Bash
---

# Recover Skill — 상태 복구

## 용도
크래시, stuck 상태, 또는 잘못된 전환에서 복구합니다.

## 프로세스

### 1. 상태 진단
\`\`\`bash
recover_state "$PROJECT_ROOT"
\`\`\`

### 2. 전환 히스토리 분석
마지막 10개 전환을 분석하여 문제 원인 식별.

### 3. 복구 옵션 제시
- 스냅샷으로 롤백
- 현재 상태에서 재개
- 수동 개입

## 출력
\`\`\`
🔧 State Recovery

📊 Current State:
  Phase: implement
  Iteration: 3
  Last Updated: 2026-03-28T12:00:00Z

📜 Recent Transitions:
  1. design → implement (10:30)
  2. implement → check (11:00) [FAILED: match_rate 75%]
  3. check → implement (11:05) [ITERATE]

📸 Available Snapshots:
  1. snap_design_1234567890
  2. snap_implement_1234567900

➡️ Options:
  /recover --rollback snap_design_1234567890
  /implement --resume
\`\`\`
```

#### Day 4: 통합 테스트 및 문서화

**파일: `hooks/__tests__/state-machine.test.sh`**

```bash
#!/usr/bin/env bash
# state-machine.test.sh — 상태 머신 테스트

source "$(dirname "$0")/../lib/state-machine.sh"

setup() {
  TEST_DIR=$(mktemp -d)
  mkdir -p "${TEST_DIR}/.harness"
}

teardown() {
  rm -rf "$TEST_DIR"
}

test_init_state_machine() {
  init_state_machine "$TEST_DIR" "test-feature"

  assert_file_exists "$(state_file "$TEST_DIR")"
  assert_equals "clarify" "$(get_current_phase "$TEST_DIR")"
}

test_valid_transition() {
  init_state_machine "$TEST_DIR" "test-feature"

  # clarify → plan은 유효하지 않음 (가드: design_doc_exists)
  local result
  result=$(can_transition "$TEST_DIR" "clarify" "plan")
  assert_contains "false" "$result"
}

test_snapshot_and_rollback() {
  init_state_machine "$TEST_DIR" "test-feature"

  local snapshot_id
  snapshot_id=$(create_snapshot "$TEST_DIR" "clarify")

  assert_file_exists "$(snapshots_dir "$TEST_DIR")/${snapshot_id}.json"
}

# 테스트 실행
run_tests
```

### 산출물
1. `hooks/lib/state-machine.sh` - 상태 머신 엔진
2. `skills/recover/SKILL.md` - 복구 스킬
3. `.harness/engine/` - 상태 머신 데이터 디렉토리
4. `hooks/__tests__/state-machine.test.sh` - 테스트

---

## 구현 일정

```
Week 1:
├── Day 1: P0-1 테스트 러너 라이브러리
├── Day 2: P0-1 Check 스킬 통합
├── Day 3: P0-1 검증 클래스 시스템
├── Day 4: P0-2 서브에이전트 인터페이스 설계
└── Day 5: P0-2 Wave Executor 개선

Week 2:
├── Day 6-7: P0-2 Agent 툴 연동
├── Day 8: P0-2 통합 테스트
├── Day 9: P0-3 상태 머신 설계
└── Day 10: P0-3 기존 코드 통합

Week 3:
├── Day 11: P0-3 롤백 및 복구 UI
└── Day 12: P0-3 통합 테스트 및 문서화
```

---

## 의존성

### P0-1 (테스트 실행)
- `jq` (JSON 파싱)
- 테스트 프레임워크별 CLI (npm, pytest, go test 등)

### P0-2 (서브에이전트)
- Claude Code Agent API
- `jq` (상태 관리)

### P0-3 (상태 머신)
- `jq` (JSON 파싱)
- `bc` (부동소수점 비교)

---

## 성공 기준

| P0 항목 | 성공 기준 |
|--------|----------|
| P0-1 | Check 스킬이 실제 테스트 실행 후 90%+ 통과 시 Wrap-up 진행 |
| P0-2 | Wave Executor가 4개 서브에이전트 병렬 실행, 결과 집계 |
| P0-3 | 모든 전환이 가드 통과, 스냅샷 롤백 100% 복구 |

---

## 위험 및 완화

| 위험 | 영향 | 완화 방안 |
|-----|-----|----------|
| Claude Code Agent API 변경 | P0-2 지연 | 인터페이스 추상화, 버전 고정 |
| 테스트 프레임워크 호환성 | P0-1 제한 | 주요 6개 프레임워크만 지원 |
| 상태 머신 복잡도 | P0-3 버그 | TDD로 구현, 100% 테스트 커버리지 |
