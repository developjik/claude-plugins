---
name: recover
description: |
  Recover from crashed or stuck state. Analyze last transitions,
  offer rollback options, resume from checkpoint.
  Triggers on: 'recover', 'rollback', 'crash', 'stuck', 'resume',
  '복구', '롤백', '재개', '멈춤',
  Error: 'state corrupted', 'cannot continue', 'stuck in loop'
user-invocable: true
argument-hint: [--rollback <snapshot-id>] [--resume] [--history]
allowed-tools: Read, Bash, Agent
---

# Recover Skill — 상태 복구

크래시, stuck 상태, 또는 잘못된 전환에서 복구합니다.

## 용도

- 세션 크래시 후 상태 복구
- 잘못된 방향으로 진행 시 롤백
- 무한 루프 감지 및 해결
- 전환 히스토리 분석

## 프로세스

### 1. 상태 진단

```bash
# 라이브러리 로드
PLUGIN_DIR="${PLUGIN_DIR:-$(dirname "$0")/..}"
source "${PLUGIN_DIR}/hooks/lib/state-machine.sh"

# 인자 파싱
MODE="status"
SNAPSHOT_ID=""

for arg in "$@"; do
  case "$arg" in
    --rollback=*) SNAPSHOT_ID="${arg#*=}"; MODE="rollback" ;;
    --rollback) MODE="rollback_pending" ;;
    --resume) MODE="resume" ;;
    --history) MODE="history" ;;
  esac
done

# 상태 진단
recover_state "$PROJECT_ROOT"
```

### 2. 모드별 실행

#### --status (기본)
현재 상태와 사용 가능한 옵션 표시:

```
🔧 State Recovery
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📊 Current State:
  Feature: user-auth
  Phase: implement
  Iteration: 3
  Entered: 2026-03-28T10:30:00Z

📜 Recent Transitions:
  1. design → implement (10:30)
  2. implement → check (11:00) [FAILED: 75%]
  3. check → implement (11:05) [ITERATE]

📸 Available Snapshots:
  1. snap_design_1234567890 (design)
  2. snap_implement_1234567900 (implement)
  3. snap_check_1234567910 (check)

➡️ Options:
  /recover --resume              # Resume from current state
  /recover --rollback snap_design_1234567890  # Rollback
  /implement --continue          # Continue implementation
```

#### --rollback \<snapshot-id\>
지정된 스냅샷으로 롤백:

```bash
if [[ -n "$SNAPSHOT_ID" ]]; then
  rollback_to_snapshot "$PROJECT_ROOT" "$SNAPSHOT_ID"
  echo ""
  echo "➡️ Next: Continue from $(get_current_phase "$PROJECT_ROOT") phase"
fi
```

#### --resume
현재 상태에서 재개:

```bash
if [[ "$MODE" == "resume" ]]; then
  local current_phase
  current_phase=$(get_current_phase "$PROJECT_ROOT")

  echo "✅ Resuming from: $current_phase"

  # 다음 단계 제안
  case "$current_phase" in
    clarify) echo "➡️ Run: /plan <feature-slug>" ;;
    plan) echo "➡️ Run: /design <feature-slug>" ;;
    design) echo "➡️ Run: /implement <feature-slug>" ;;
    implement) echo "➡️ Run: /check <feature-slug>" ;;
    check) echo "➡️ Run: /check <feature-slug> (iterate) or /wrapup" ;;
    wrapup) echo "➡️ Feature complete! Start new: /clarify <new-feature>" ;;
  esac
fi
```

#### --history
전환 히스토리 표시:

```bash
if [[ "$MODE" == "history" ]]; then
  echo "📜 Transition History"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  get_transition_history "$PROJECT_ROOT" 20 | jq -r '.[] |
    "[\(.timestamp)] \(.event): \(.from // "start") → \(.to) (\(.reason))"
  '
fi
```

### 3. Stuck 감지

```bash
# 무한 루프 감지
detect_stuck_state() {
  local project_root="${1:-}"
  local max_iterations=10

  local iteration_count
  iteration_count=$(get_state "$project_root" | jq -r '.iteration_count // 0')

  if [[ "$iteration_count" -ge "$max_iterations" ]]; then
    echo "⚠️  Stuck detected: $iteration_count iterations"
    echo ""
    echo "Options:"
    echo "  1. /recover --rollback <latest_design_snapshot>"
    echo "  2. Manual review: Read design.md and check results"
    echo "  3. /clarify <feature-slug>  # Restart with clarified requirements"

    return 1
  fi

  return 0
}
```

## 출력 예시

### 정상 복구

```
🔧 State Recovery
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📊 Analyzing current state...

Phase: implement
Status: active
Feature: user-authentication
Last Activity: 5 minutes ago

🔍 Last 5 Transitions:
  1. [10:00] init → clarify (initialized)
  2. [10:05] clarify → plan (user_approved)
  3. [10:15] plan → design (plan_complete)
  4. [10:30] design → implement (atomic_tasks_defined)
  5. [10:35] SNAPSHOT: snap_implement_xxx

📸 Available Snapshots:
  snap_design_xxx    (10:15) - design phase
  snap_implement_xxx (10:35) - implement phase

✅ State is healthy. Ready to resume.

➡️ Run: /implement user-authentication --continue
```

### 롤백

```
🔧 Rolling Back
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Snapshot: snap_design_1234567890
Phase: design
Created: 2026-03-28T10:15:00Z

Restoring state...
✅ State restored to: design

Files at snapshot:
  plan.md: abc123...
  design.md: def456...

➡️ Next: /design user-authentication
```

### Stuck 감지

```
⚠️  Stuck State Detected
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Iteration Count: 12 (max: 10)
Phase: check → implement loop

📜 Loop Pattern:
  implement → check (75% match)
  check → implement (iterate)
  implement → check (78% match)
  check → implement (iterate)
  ...

🔍 Root Cause Analysis:
  - Match rate not improving (75-78%)
  - Same issues recurring

➡️ Recommendations:
  1. Review design.md for missing requirements
  2. Run: /recover --rollback snap_design_xxx
  3. Manual intervention: Check implementation approach
```

## 플래그

| 플래그 | 설명 |
|--------|------|
| `--status` | 현재 상태 표시 (기본값) |
| `--rollback <id>` | 지정된 스냅샷으로 롤백 |
| `--resume` | 현재 상태에서 재개 |
| `--history` | 전환 히스토리 표시 |
| `--list-snapshots` | 스냅샷 목록만 표시 |
| `--clean` | 오래된 스냅샷 정리 |

## 의존성

```bash
source hooks/lib/state-machine.sh
source hooks/lib/logging.sh
```
