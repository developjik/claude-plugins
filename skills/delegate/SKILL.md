---
name: delegate
description: |
  Spawn a fresh subagent for a single atomic task.
  Use for parallel execution of independent tasks.
  Triggers on: 'delegate', 'spawn agent', 'subagent', 'parallel task',
  '위임', '서브에이전트', '병렬',
  Error: 'need another agent', 'spawn worker', 'parallel execution'
user-invocable: true
argument-hint: <task-file> [model] [--purpose <purpose>]
allowed-tools: Agent, Read, Write, Bash
---

# Delegate Skill — 서브에이전트 태스크 위임

독립적인 태스크를 **신선한 컨텍스트의 서브에이전트**에게 위임합니다.
Context Engineering 원칙에 따라 **최소 필수 컨텍스트만** 전달합니다.

## 용도

- Wave 실행에서 병렬 태스크 처리
- 독립적인 코드 리뷰 (fresh perspective)
- 연구 및 조사 작업
- 테스트 실행 및 검증

## 프로세스

### 1. 서브에이전트 스폰

```bash
# 라이브러리 로드
PLUGIN_DIR="${PLUGIN_DIR:-$(dirname "$0")/..}"
source "${PLUGIN_DIR}/hooks/lib/subagent-spawner.sh"

# 인자 파싱
TASK_FILE=$(echo "$ARGUMENTS" | awk '{print $1}')
MODEL=$(echo "$ARGUMENTS" | awk '{print $2}')
PURPOSE=$(echo "$ARGUMENTS" | grep -oP '(?<=--purpose )[^ ]+' || echo "task_execution")

# 기본값 설정
MODEL=${MODEL:-sonnet}  # opus, sonnet, haiku

# 서브에이전트 스폰
SUBAGENT_ID=$(spawn_subagent "$TASK_FILE" "$PROJECT_ROOT" "$MODEL" "$PURPOSE")

echo "🤖 Subagent spawned: $SUBAGENT_ID"
```

### 2. 컨텍스트 준비

**Context Engineering 원칙:**
- PROJECT.md (프로젝트 개요)
- STATE.md (현재 상태)
- design.md 관련 섹션 (구현 계획)
- 태스크 파일

**크기 제한:** 50k 토큰 이내

```bash
# 컨텍스트는 자동으로 준비됨
# prepare_subagent_context가 purpose에 따라 최적화
```

### 3. Agent 툴 실행

```bash
# Agent 실행 파라미터 생성
AGENT_PARAMS=$(prepare_for_agent_execution "$SUBAGENT_ID" "$PROJECT_ROOT")

# Agent 툴 호출 (Claude Code에서 실행)
# {
#   "subagent_type": "general-purpose",
#   "description": "subagent_xxx",
#   "prompt": "<context + task>"
# }
```

### 4. 결과 수집

```bash
# 서브에이전트 완료 후
finalize_agent_execution "$SUBAGENT_ID" "$PROJECT_ROOT" "$RESULT_CONTENT"

# 결과 확인
RESULT_FILE="${PROJECT_ROOT}/.harness/subagents/${SUBAGENT_ID}/result.md"
```

## 모델 선택 가이드

| 모델 | 용도 | 비용 | 예상 속도 |
|------|------|------|----------|
| **opus** | 복잡한 아키텍처 결정, 보안 검토, 전체 리팩토링 | 높음 | 느림 |
| **sonnet** | 일반적인 구현 작업, 코드 리뷰, 테스트 작성 | 중간 | 보통 |
| **haiku** | 간단한 문서화, 포맷팅, 빠른 검증 | 낮음 | 빠름 |

## Purpose별 컨텍스트

| Purpose | 추가 컨텍스트 | 사용 시나리오 |
|---------|--------------|--------------|
| `task_execution` | design.md 구현 순서 | 일반 구현 작업 |
| `code_review` | CLAUDE.md, 코딩 컨벤션 | 코드 품질 리뷰 |
| `research` | 프로젝트 구조 | 기술 조사 |
| `testing` | 테스트 설정 | 테스트 작성/실행 |
| `documentation` | API 스펙 | 문서화 |

## 출력

```
🤖 Subagent: subagent_1743123456_abc123
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📋 Task: implement-user-auth
🎯 Model: sonnet
📌 Purpose: task_execution

⏱️ Status: running...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 Execution Complete
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ Status: completed
⏱️ Duration: 45.2s
📝 Result: result.md

📄 Summary:
- Implemented user authentication
- Added login/logout endpoints
- Created session management
- Tests passing: 12/12

➡️ Full result: .harness/subagents/subagent_1743123456_abc123/result.md
```

## 병렬 실행

여러 서브에이전트를 동시에 실행할 수 있습니다:

```bash
# 4개 서브에이전트 병렬 스폰
ID1=$(spawn_subagent "task1.md" "$PROJECT_ROOT" "sonnet")
ID2=$(spawn_subagent "task2.md" "$PROJECT_ROOT" "sonnet")
ID3=$(spawn_subagent "task3.md" "$PROJECT_ROOT" "sonnet")
ID4=$(spawn_subagent "task4.md" "$PROJECT_ROOT" "sonnet")

# Agent 툴로 각각 실행 (병렬)

# 결과 집계
RESULTS=$(aggregate_subagent_results "$PROJECT_ROOT" "$ID1,$ID2,$ID3,$ID4")
```

## 제약사항

- 최대 병렬 서브에이전트: **4개**
- 타임아웃: **10분** (600초)
- 컨텍스트 크기: **50k 토큰** 이내
- 파일 수정: 태스크 범위 내로 제한

## 에러 처리

```bash
# 서브에이전트 실패 시
if [[ "$STATUS" == "failed" ]]; then
  echo "❌ Subagent failed: $SUBAGENT_ID"
  echo "📄 Error log: .harness/subagents/${SUBAGENT_ID}/result.md"

  # 재시도 또는 사용자 개입 요청
fi

# 타임아웃 시
if [[ "$STATUS" == "timeout" ]]; then
  echo "⏱️ Subagent timed out: $SUBAGENT_ID"
  # 결과 부분 확인
fi
```

## 관련 함수

```bash
# 서브에이전트 상태 조회
get_subagent_status "$SUBAGENT_ID" "$PROJECT_ROOT"

# 활성 서브에이전트 목록
list_active_subagents "$PROJECT_ROOT"

# 완료된 서브에이전트 정리 (24시간 후)
cleanup_completed_subagents "$PROJECT_ROOT" 24

# 병렬 실행 대기
wait_for_subagents "$PROJECT_ROOT" "$ID1,$ID2" 300
```
