#!/usr/bin/env bash
# crash-detection.sh — crash-recovery detection and diagnosis helpers

set -euo pipefail

crash_recovery_state_file() {
  local project_root="${1:-}"
  echo "${project_root}/.harness/engine/state.json"
}

crash_recovery_transitions_file() {
  local project_root="${1:-}"
  echo "${project_root}/.harness/engine/transitions.jsonl"
}

crash_recovery_snapshots_dir() {
  local project_root="${1:-}"
  echo "${project_root}/.harness/engine/snapshots"
}

crash_recovery_now_epoch() {
  date +%s
}

crash_recovery_iso_to_epoch() {
  local iso_ts="${1:-}"
  local normalized
  normalized="${iso_ts%Z}"

  if [[ "$OSTYPE" == "darwin"* ]]; then
    TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$normalized" +%s 2> /dev/null || echo 0
  else
    date -d "$normalized" +%s 2> /dev/null || echo 0
  fi
}

crash_latest_snapshot_file() {
  local snapshots_dir="${1:-}"

  find "$snapshots_dir" -maxdepth 1 -type f -name '*.json' -print 2> /dev/null | while IFS= read -r file; do
    local file_ts
    file_ts=$(stat -f %m "$file" 2> /dev/null || stat -c %Y "$file" 2> /dev/null || echo 0)
    printf '%s\t%s\n' "$file_ts" "$file"
  done | sort -rn | head -1 | cut -f2-
}

# Detect stuck state
# Usage: detect_stuck_state <project_root> [max_iterations] [max_minutes]
detect_stuck_state() {
  local project_root="${1:-}"
  local max_iterations="${2:-$MAX_ITERATIONS}"
  local max_minutes="${3:-$MAX_PHASE_DURATION_MINUTES}"
  local state_file

  state_file=$(crash_recovery_state_file "$project_root")

  if [[ ! -f "$state_file" ]]; then
    echo '{"stuck": false, "reason": "no_state_file"}'
    return 0
  fi

  local state iteration_count current_phase last_transition
  state=$(cat "$state_file")
  iteration_count=$(echo "$state" | jq -r '.iteration_count // 0')
  current_phase=$(echo "$state" | jq -r '.phase // "unknown"')
  last_transition=$(echo "$state" | jq -r '.last_transition_at // .entered_at // ""')
  if [[ -z "$last_transition" ]]; then
    last_transition=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  fi

  if [[ "$iteration_count" -ge "$max_iterations" ]]; then
    echo "{\"stuck\": true, \"reason\": \"max_iterations\", \"count\": $iteration_count, \"threshold\": $max_iterations, \"phase\": \"$current_phase\"}"
    return 0
  fi

  local now last_epoch elapsed
  now=$(crash_recovery_now_epoch)
  last_epoch=$(crash_recovery_iso_to_epoch "$last_transition")

  if [[ "$last_epoch" -gt 0 ]]; then
    elapsed=$(((now - last_epoch) / 60))

    if [[ "$elapsed" -ge "$max_minutes" ]]; then
      echo "{\"stuck\": true, \"reason\": \"timeout\", \"elapsed_minutes\": $elapsed, \"threshold_minutes\": $max_minutes, \"phase\": \"$current_phase\"}"
      return 0
    fi
  fi

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
  local transitions_file
  transitions_file=$(crash_recovery_transitions_file "$project_root")

  if [[ ! -f "$transitions_file" ]]; then
    echo '{"loop_detected": false, "reason": "no_transitions"}'
    return 0
  fi

  local recent
  recent=$(tail -10 "$transitions_file" 2> /dev/null)

  if [[ -z "$recent" ]]; then
    echo '{"loop_detected": false, "reason": "no_recent_transitions"}'
    return 0
  fi

  local patterns='[]'
  while IFS= read -r line; do
    local from to
    from=$(echo "$line" | jq -r '.from // ""' 2> /dev/null || echo "")
    to=$(echo "$line" | jq -r '.to // ""' 2> /dev/null || echo "")

    if [[ -n "$from" ]] && [[ -n "$to" ]]; then
      patterns=$(echo "$patterns" | jq ". + [\"$from:$to\"]")
    fi
  done <<< "$recent"

  local check_impl_count impl_check_count
  check_impl_count=$(echo "$patterns" | jq '[.[] | select(. == "check:implement")] | length')
  impl_check_count=$(echo "$patterns" | jq '[.[] | select(. == "implement:check")] | length')

  if [[ "$check_impl_count" -ge 3 ]] && [[ "$impl_check_count" -ge 3 ]]; then
    echo "{\"loop_detected\": true, \"reason\": \"check_implement_cycle\", \"cycle_count\": $check_impl_count, \"pattern\": \"check<->implement\"}"
    return 0
  fi

  echo "{\"loop_detected\": false, \"check_implement_cycles\": $check_impl_count}"
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

  options=$(echo "$options" | jq '. + [{"id": "resume", "action": "Resume from current state", "risk": "low", "description": "Continue from where you left off"}]')

  local snapshots_dir
  snapshots_dir=$(crash_recovery_snapshots_dir "$project_root")
  if [[ -d "$snapshots_dir" ]]; then
    local latest
    latest=$(crash_latest_snapshot_file "$snapshots_dir")
    if [[ -n "$latest" ]] && [[ -f "$latest" ]]; then
      local snap_id
      snap_id=$(jq -r '.id // "unknown"' "$latest" 2> /dev/null)
      options=$(echo "$options" | jq ". + [{\"id\": \"rollback\", \"snapshot_id\": \"$snap_id\", \"action\": \"Rollback to checkpoint\", \"risk\": \"medium\", \"description\": \"Restore from last checkpoint\"}]")
    fi
  fi

  local severity
  severity=$(echo "$diagnosis" | jq -r '.severity // "low"')
  if [[ "$severity" == "high" ]]; then
    options=$(echo "$options" | jq '. + [{"id": "reset_to_design", "action": "Reset to design phase", "risk": "high", "description": "Go back to design and revise"}]')
  fi

  options=$(echo "$options" | jq '. + [{"id": "manual", "action": "Manual intervention", "risk": "none", "description": "Human review required"}]')

  echo "$options"
}
