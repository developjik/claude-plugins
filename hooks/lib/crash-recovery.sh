#!/usr/bin/env bash
# crash-recovery.sh — Crash Recovery and Forensics System
# P1-3: State machine based recovery and root cause analysis
#
# DEPENDENCIES: json-utils.sh, logging.sh, state-machine.sh

set -euo pipefail

# ============================================================================
# Constants
# ============================================================================

readonly RECOVERY_DIR=".harness/recovery"
readonly FORENSICS_DIR=".harness/forensics"
readonly MAX_ITERATIONS=10
readonly MAX_PHASE_DURATION_MINUTES=30
readonly RECOVERY_LOG="recovery.log"

# ============================================================================
# Stuck State Detection
# ============================================================================

# Detect stuck state
# Usage: detect_stuck_state <project_root> [max_iterations] [max_minutes]
detect_stuck_state() {
  local project_root="${1:-}"
  local max_iterations="${2:-$MAX_ITERATIONS}"
  local max_minutes="${3:-$MAX_PHASE_DURATION_MINUTES}"

  local lib_dir
  lib_dir="$(cd "$(dirname "${BASH_SOURCE:-0}")" && pwd)"

  if ! declare -f get_state &>/dev/null; then
    if [[ -f "${lib_dir}/state-machine.sh" ]]; then
      source "${lib_dir}/state-machine.sh"
    fi
  fi

  local state_file="${project_root}/.harness/engine/state.json"

  if [[ ! -f "$state_file" ]]; then
    echo '{"stuck": false, "reason": "no_state_file"}'
    return 0
  fi

  local state iteration_count current_phase last_transition
  state=$(cat "$state_file")
  iteration_count=$(echo "$state" | jq -r '.iteration_count // 0')
  current_phase=$(echo "$state" | jq -r '.phase // "unknown"')
  # last_transition_at이 없으면 entered_at 사용, 둘 다 없으면 현재 시간
  last_transition=$(echo "$state" | jq -r '.last_transition_at // .entered_at // ""')
  if [[ -z "$last_transition" ]]; then
    last_transition=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  fi

  local now
  now=$(date +%s)

  # Check 1: Max iterations exceeded
  if [[ "$iteration_count" -ge "$max_iterations" ]]; then
    echo "{\"stuck\": true, \"reason\": \"max_iterations\", \"count\": $iteration_count, \"threshold\": $max_iterations, \"phase\": \"$current_phase\"}"
    return 0
  fi

  # Check 2: Timeout in current phase
  local last_ts last_epoch elapsed
  last_ts=$(echo "$last_transition" | sed 's/Z$//')

  # macOS와 Linux 모두 지원하는 날짜 파싱 (UTC 기준)
  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS: TZ=UTC로 설정하여 UTC로 파싱
    last_epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$last_ts" +%s 2>/dev/null || echo 0)
  else
    last_epoch=$(date -d "$last_ts" +%s 2>/dev/null || echo 0)
  fi

  if [[ "$last_epoch" -gt 0 ]]; then
    elapsed=$(( (now - last_epoch) / 60 ))

    if [[ "$elapsed" -ge "$max_minutes" ]]; then
      echo "{\"stuck\": true, \"reason\": \"timeout\", \"elapsed_minutes\": $elapsed, \"threshold_minutes\": $max_minutes, \"phase\": \"$current_phase\"}"
      return 0
    fi
  fi

  # Check 3: Loop pattern detection
  local loop_result
  loop_result=$(detect_loop_pattern "$project_root")

  if echo "$loop_result" | jq -e '.loop_detected == true' > /dev/null 2>&1; then
    echo "$loop_result"
    return 0
  fi

  echo "{\"stuck\": false, \"iteration_count\": $iteration_count, \"phase\": \"$current_phase\"}"
}

# Detect loop pattern in transitions
# Usage: detect_loop_pattern <project_root>
detect_loop_pattern() {
  local project_root="${1:-}"
  local transitions_file="${project_root}/.harness/engine/transitions.jsonl"

  if [[ ! -f "$transitions_file" ]]; then
    echo '{"loop_detected": false, "reason": "no_transitions"}'
    return 0
  fi

  local recent
  recent=$(tail -10 "$transitions_file" 2>/dev/null)

  if [[ -z "$recent" ]]; then
    echo '{"loop_detected": false, "reason": "no_recent_transitions"}'
    return 0
  fi

  # Extract transition patterns
  local patterns='[]'
  while IFS= read -r line; do
    local from to
    from=$(echo "$line" | jq -r '.from // ""' 2>/dev/null || echo "")
    to=$(echo "$line" | jq -r '.to // ""' 2>/dev/null || echo "")

    if [[ -n "$from" ]] && [[ -n "$to" ]]; then
      patterns=$(echo "$patterns" | jq ". + [\"$from:$to\"]")
    fi
  done <<< "$recent"

  # Count cycle patterns
  local check_impl_count impl_check_count
  check_impl_count=$(echo "$patterns" | jq '[.[] | select(. == "check:implement")] | length')
  impl_check_count=$(echo "$patterns" | jq '[.[] | select(. == "implement:check")] | length')

  if [[ "$check_impl_count" -ge 3 ]] && [[ "$impl_check_count" -ge 3 ]]; then
    echo "{\"loop_detected\": true, \"reason\": \"check_implement_cycle\", \"cycle_count\": $check_impl_count, \"pattern\": \"check<->implement\"}"
    return 0
  fi

  echo "{\"loop_detected\": false, \"check_implement_cycles\": $check_impl_count}"
}

# ============================================================================
# Crash Analysis
# ============================================================================

# Analyze crash
# Usage: analyze_crash <project_root> [crash_id]
analyze_crash() {
  local project_root="${1:-}"
  local crash_id="${2:-}"

  local recovery_dir="${project_root}/${RECOVERY_DIR}"
  local forensics_dir="${project_root}/${FORENSICS_DIR}"
  mkdir -p "$recovery_dir" "$forensics_dir"

  local timestamp
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  local analysis_id
  if [[ -n "$crash_id" ]]; then
    analysis_id="$crash_id"
  else
    analysis_id="crash_$(date +%s)"
  fi

  # Collect state info
  local state_file="${project_root}/.harness/engine/state.json"
  local transitions_file="${project_root}/.harness/engine/transitions.jsonl"

  local current_state='{}'
  if [[ -f "$state_file" ]]; then
    current_state=$(cat "$state_file")
  fi

  local recent_transitions='[]'
  if [[ -f "$transitions_file" ]]; then
    recent_transitions=$(tail -20 "$transitions_file" | jq -s '.' 2>/dev/null || echo '[]')
  fi

  # Check stuck status
  local stuck_status
  stuck_status=$(detect_stuck_state "$project_root")

  # Get snapshots
  local snapshots='[]'
  local snapshots_dir="${project_root}/.harness/engine/snapshots"
  if [[ -d "$snapshots_dir" ]]; then
    snapshots=$(find "$snapshots_dir" -name "*.json" -type f 2>/dev/null | head -5 | while read -r f; do
      jq -c '{id: .id, phase: .phase, timestamp: .timestamp}' "$f" 2>/dev/null || echo '{}'
    done | jq -s '.' 2>/dev/null || echo '[]')
  fi

  # Diagnose
  local diagnosis
  diagnosis=$(diagnose_issue "$project_root" "$stuck_status" "$current_state")

  # Generate recovery options
  local recovery_options
  recovery_options=$(generate_recovery_options "$project_root" "$stuck_status" "$diagnosis")

  # Build analysis report
  local analysis
  analysis=$(jq -c -n \
    --arg id "$analysis_id" \
    --arg ts "$timestamp" \
    --argjson stuck "$stuck_status" \
    --argjson state "$current_state" \
    --argjson transitions "$recent_transitions" \
    --argjson snapshots "$snapshots" \
    --argjson diagnosis "$diagnosis" \
    --argjson options "$recovery_options" \
    '{
      id: $id,
      timestamp: $ts,
      stuck_status: $stuck,
      current_state: $state,
      recent_transitions: $transitions,
      available_snapshots: $snapshots,
      diagnosis: $diagnosis,
      recovery_options: $options
    }')

  # Save analysis
  echo "$analysis" > "${forensics_dir}/analysis_${analysis_id}.json"

  echo "$analysis"
}

# Diagnose issue
# Usage: diagnose_issue <project_root> <stuck_status> <current_state>
diagnose_issue() {
  local project_root="${1:-}"
  local stuck_status="${2:-}"
  local current_state="${3:-}"

  local stuck_reason phase iteration_count
  stuck_reason=$(echo "$stuck_status" | jq -r '.reason // "unknown"')
  phase=$(echo "$current_state" | jq -r '.phase // "unknown"')
  iteration_count=$(echo "$current_state" | jq -r '.iteration_count // 0')

  local issue="unknown"
  local severity="low"
  local root_cause="Unknown"
  local recommendations='[]'

  case "$stuck_reason" in
    max_iterations)
      issue="iteration_limit_exceeded"
      severity="high"
      root_cause="Implementation does not meet acceptance criteria after maximum iterations"
      recommendations='["Review design.md for missing requirements", "Check if acceptance criteria are achievable", "Consider manual intervention"]'
      ;;
    timeout)
      issue="phase_timeout"
      severity="medium"
      root_cause="Process stuck in current phase for too long"
      recommendations='["Check for blocking dependencies", "Review logs for errors", "Consider rollback"]'
      ;;
    check_implement_cycle)
      issue="check_implement_loop"
      severity="high"
      root_cause="Implementation and verification in infinite loop"
      recommendations='["Review test failures", "Check if tests are flaky", "Rollback to design phase"]'
      ;;
    *)
      if [[ "$iteration_count" -gt 5 ]]; then
        issue="high_iteration_count"
        severity="medium"
        root_cause="Multiple retry attempts"
        recommendations='["Review recent test results", "Check edge cases"]'
      fi
      ;;
  esac

  jq -c -n \
    --arg issue "$issue" \
    --arg severity "$severity" \
    --arg root_cause "$root_cause" \
    --argjson recommendations "$recommendations" \
    '{
      issue: $issue,
      severity: $severity,
      root_cause: $root_cause,
      recommendations: $recommendations
    }'
}

# Generate recovery options
# Usage: generate_recovery_options <project_root> <stuck_status> <diagnosis>
generate_recovery_options() {
  local project_root="${1:-}"
  local stuck_status="${2:-}"
  local diagnosis="${3:-}"

  local options='[]'

  # Option 1: Resume
  options=$(echo "$options" | jq '. + [{"id": "resume", "action": "Resume from current state", "risk": "low", "description": "Continue from where you left off"}]')

  # Option 2: Rollback to snapshot
  local snapshots_dir="${project_root}/.harness/engine/snapshots"
  if [[ -d "$snapshots_dir" ]]; then
    local latest
    latest=$(ls -t "$snapshots_dir"/*.json 2>/dev/null | head -1)
    if [[ -n "$latest" ]] && [[ -f "$latest" ]]; then
      local snap_id
      snap_id=$(jq -r '.id // "unknown"' "$latest" 2>/dev/null)
      options=$(echo "$options" | jq ". + [{\"id\": \"rollback\", \"snapshot_id\": \"$snap_id\", \"action\": \"Rollback to checkpoint\", \"risk\": \"medium\", \"description\": \"Restore from last checkpoint\"}]")
    fi
  fi

  # Option 3: Reset to design (high severity)
  local severity
  severity=$(echo "$diagnosis" | jq -r '.severity // "low"')
  if [[ "$severity" == "high" ]]; then
    options=$(echo "$options" | jq '. + [{"id": "reset_to_design", "action": "Reset to design phase", "risk": "high", "description": "Go back to design and revise"}]')
  fi

  # Option 4: Manual
  options=$(echo "$options" | jq '. + [{"id": "manual", "action": "Manual intervention", "risk": "none", "description": "Human review required"}]')

  echo "$options"
}

# ============================================================================
# State Recovery
# ============================================================================

# Recover state
# Usage: recover_state <project_root> <option_id> [snapshot_id]
recover_state() {
  local project_root="${1:-}"
  local option_id="${2:-}"
  local snapshot_id="${3:-}"

  local lib_dir
  lib_dir="$(cd "$(dirname "${BASH_SOURCE:-0}")" && pwd)"

  if ! declare -f transition_state &>/dev/null; then
    if [[ -f "${lib_dir}/state-machine.sh" ]]; then
      source "${lib_dir}/state-machine.sh"
    fi
  fi

  local recovery_dir="${project_root}/${RECOVERY_DIR}"
  mkdir -p "$recovery_dir"

  local timestamp
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  local success=false
  local message=""

  case "$option_id" in
    resume)
      success=true
      message="Ready to resume from current state"
      ;;
    rollback)
      if [[ -n "$snapshot_id" ]] && declare -f rollback_to_snapshot &>/dev/null; then
        if rollback_to_snapshot "$project_root" "$snapshot_id" 2>/dev/null; then
          success=true
          message="Rolled back to snapshot: $snapshot_id"
        else
          message="Failed to rollback"
        fi
      else
        message="No snapshot ID or function unavailable"
      fi
      ;;
    reset_to_design)
      local state_file="${project_root}/.harness/engine/state.json"
      if [[ -f "$state_file" ]]; then
        local tmp="${state_file}.tmp"
        jq ".phase = \"design\" | .iteration_count = 0 | .last_transition_at = \"$timestamp\"" "$state_file" > "$tmp" && \
          mv "$tmp" "$state_file"
        success=true
        message="Reset to design phase"
      fi
      ;;
    manual)
      success=true
      message="Manual intervention mode"
      ;;
    *)
      message="Unknown recovery option"
      ;;
  esac

  # Log recovery
  local log_file="${recovery_dir}/${RECOVERY_LOG}"
  echo "[${timestamp}] Recovery: ${option_id} - Success: ${success}" >> "$log_file"

  jq -c -n \
    --argjson success "$success" \
    --arg option "$option_id" \
    --arg ts "$timestamp" \
    --arg message "$message" \
    '{success: $success, option: $option, timestamp: $ts, message: $message}'
}

# ============================================================================
# Forensics Report
# ============================================================================

# Generate forensics report
# Usage: generate_forensics_report <project_root> [analysis_id]
generate_forensics_report() {
  local project_root="${1:-}"
  local analysis_id="${2:-}"

  local forensics_dir="${project_root}/${FORENSICS_DIR}"
  mkdir -p "$forensics_dir"

  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)

  local report_file="${forensics_dir}/forensics_report_${timestamp}.md"

  # Run analysis
  local analysis
  if [[ -n "$analysis_id" ]] && [[ -f "${forensics_dir}/analysis_${analysis_id}.json" ]]; then
    analysis=$(cat "${forensics_dir}/analysis_${analysis_id}.json")
  else
    analysis=$(analyze_crash "$project_root" "$analysis_id")
  fi

  # Generate report
  {
    echo "# Forensics Report"
    echo ""
    echo "**Generated:** $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo "**Analysis ID:** $(echo "$analysis" | jq -r '.id')"
    echo ""

    echo "## Stuck Status"
    echo ""
    local stuck stuck_reason phase
    stuck=$(echo "$analysis" | jq -r '.stuck_status.stuck')
    stuck_reason=$(echo "$analysis" | jq -r '.stuck_status.reason')
    phase=$(echo "$analysis" | jq -r '.current_state.phase')

    if [[ "$stuck" == "true" ]]; then
      echo "- **Status:** STUCK"
      echo "- **Reason:** $stuck_reason"
    else
      echo "- **Status:** Not stuck"
    fi
    echo "- **Current Phase:** $phase"
    echo ""

    echo "## Diagnosis"
    echo ""
    local issue severity root_cause
    issue=$(echo "$analysis" | jq -r '.diagnosis.issue')
    severity=$(echo "$analysis" | jq -r '.diagnosis.severity')
    root_cause=$(echo "$analysis" | jq -r '.diagnosis.root_cause')

    echo "- **Issue:** $issue"
    echo "- **Severity:** $severity"
    echo "- **Root Cause:** $root_cause"
    echo ""

    echo "## Recovery Options"
    echo ""
    echo "| Option | Action | Risk |"
    echo "|--------|--------|------|"
    echo "$analysis" | jq -r '.recovery_options[] | "| \(.id) | \(.action) | \(.risk) |"'
    echo ""

    echo "---"
    echo "*Auto-generated by crash-recovery.sh*"
  } > "$report_file"

  echo "$report_file"
}

# ============================================================================
# Checkpoint Management
# ============================================================================

# Create recovery checkpoint
# Usage: create_recovery_checkpoint <project_root> <phase> [description]
create_recovery_checkpoint() {
  local project_root="${1:-}"
  local phase="${2:-}"
  local description="${3:-Manual checkpoint}"

  local lib_dir
  lib_dir="$(cd "$(dirname "${BASH_SOURCE:-0}")" && pwd)"

  if ! declare -f create_snapshot &>/dev/null; then
    if [[ -f "${lib_dir}/state-machine.sh" ]]; then
      source "${lib_dir}/state-machine.sh"
    fi
  fi

  if declare -f create_snapshot &>/dev/null; then
    create_snapshot "$project_root" "$phase" 2>/dev/null
  else
    local snapshots_dir="${project_root}/.harness/engine/snapshots"
    mkdir -p "$snapshots_dir"

    local timestamp checkpoint_id
    timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    checkpoint_id="checkpoint_${phase}_$(date +%s)"

    jq -c -n \
      --arg id "$checkpoint_id" \
      --arg phase "$phase" \
      --arg ts "$timestamp" \
      --arg desc "$description" \
      '{id: $id, phase: $phase, timestamp: $ts, description: $desc, type: "recovery_checkpoint"}' \
      > "${snapshots_dir}/${checkpoint_id}.json"

    echo "$checkpoint_id"
  fi
}

# List recovery options
# Usage: list_recovery_options <project_root>
list_recovery_options() {
  local project_root="${1:-}"

  local analysis
  analysis=$(analyze_crash "$project_root")

  echo "========================================"
  echo "Recovery Options"
  echo "========================================"
  echo ""

  local stuck stuck_reason phase
  stuck=$(echo "$analysis" | jq -r '.stuck_status.stuck')
  stuck_reason=$(echo "$analysis" | jq -r '.stuck_status.reason')
  phase=$(echo "$analysis" | jq -r '.current_state.phase // "unknown"')

  echo "Current Status:"
  if [[ "$stuck" == "true" ]]; then
    echo "  Stuck: $stuck_reason"
  else
    echo "  Not stuck"
  fi
  echo "  Phase: $phase"
  echo ""

  echo "Available Options:"
  echo ""

  local i=1
  echo "$analysis" | jq -r '.recovery_options[] | "\(.id)|\(.action)|\(.risk)|\(.description)"' | while IFS='|' read -r id action risk desc; do
    echo "  $i. [$id] $action"
    echo "     Risk: $risk"
    echo "     $desc"
    echo ""
    i=$((i + 1))
  done
}

# ============================================================================
# Full Recovery Process
# ============================================================================

# Run recovery process
# Usage: run_recovery_process <project_root> [--auto]
run_recovery_process() {
  local project_root="${1:-}"
  local auto_mode="${2:-}"

  echo "Analyzing system state..."
  echo ""

  local analysis
  analysis=$(analyze_crash "$project_root")

  local stuck
  stuck=$(echo "$analysis" | jq -r '.stuck_status.stuck')

  if [[ "$stuck" != "true" ]]; then
    echo "System is not stuck. No recovery needed."
    echo ""
    echo "Current phase: $(echo "$analysis" | jq -r '.current_state.phase')"

    local report_file
    report_file=$(generate_forensics_report "$project_root")
    echo ""
    echo "Health report saved to: $report_file"
    return 0
  fi

  local stuck_reason
  stuck_reason=$(echo "$analysis" | jq -r '.stuck_status.reason')
  echo "Stuck detected: $stuck_reason"
  echo ""

  local report_file
  report_file=$(generate_forensics_report "$project_root")
  echo "Forensics report generated: $report_file"
  echo ""

  if [[ "$auto_mode" == "--auto" ]]; then
    local first_option
    first_option=$(echo "$analysis" | jq -r '.recovery_options[0].id // "resume"')
    echo "Auto-recovery: Selecting '$first_option'"
    recover_state "$project_root" "$first_option"
  else
    list_recovery_options "$project_root"
    echo "Run: /recover --<option-id> to execute"
  fi
}
