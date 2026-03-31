#!/usr/bin/env bash
# snapshot-store.sh — state-machine snapshot persistence helpers

set -euo pipefail

snapshot_store_file_hash() {
  local file_path="${1:-}"

  md5 -q "$file_path" 2> /dev/null \
    || md5sum "$file_path" 2> /dev/null | cut -d' ' -f1
}

snapshot_store_capture_files_json() {
  local project_root="${1:-}"
  local feature_slug="${2:-}"
  local files_snapshot="{}"

  if [[ -z "$feature_slug" ]]; then
    echo "$files_snapshot"
    return 0
  fi

  local spec_dir="${project_root}/docs/specs/${feature_slug}"
  local file content_hash
  for file in "plan.md" "design.md" "STATE.md"; do
    if [[ -f "${spec_dir}/${file}" ]]; then
      content_hash=$(snapshot_store_file_hash "${spec_dir}/${file}")
      files_snapshot=$(echo "$files_snapshot" | jq \
        --arg file "$file" \
        --arg hash "$content_hash" \
        '.[$file] = $hash')
    fi
  done

  echo "$files_snapshot"
}

snapshot_store_append_snapshot_reference() {
  local project_root="${1:-}"
  local snapshot_id="${2:-}"

  state_store_jq_update "$project_root" \
    --arg snap "$snapshot_id" \
    '.snapshots += [$snap]'
}

snapshot_store_snapshot_mtime() {
  local file_path="${1:-}"

  if stat -f '%m' "$file_path" > /dev/null 2>&1; then
    stat -f '%m' "$file_path"
    return 0
  fi

  stat -c '%Y' "$file_path"
}

snapshot_store_list_files_newest_first() {
  local snapshots_path="${1:-}"
  local file_path mtime

  for file_path in "${snapshots_path}"/*.json; do
    [[ -f "$file_path" ]] || continue
    mtime=$(snapshot_store_snapshot_mtime "$file_path")
    printf '%s\t%s\n' "$mtime" "$file_path"
  done | sort -rn | cut -f2-
}

snapshot_store_write_snapshot() {
  local project_root="${1:-}"
  local snapshot_id="${2:-}"
  local phase="${3:-}"
  local state_json="${4:-}"
  local files_json="${5:-}"

  if [[ -z "$state_json" ]]; then
    state_json='{}'
  fi

  if [[ -z "$files_json" ]]; then
    files_json='{}'
  fi

  local snapshot_file
  snapshot_file="$(snapshots_dir "$project_root")/${snapshot_id}.json"

  jq -n \
    --arg id "$snapshot_id" \
    --arg phase "$phase" \
    --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    --argjson state "$state_json" \
    --argjson files "$files_json" \
    '{
      id: $id,
      phase: $phase,
      created_at: $ts,
      state: $state,
      files: $files
    }' > "$snapshot_file"
}

snapshot_store_create_snapshot_internal() {
  local project_root="${1:-}"
  local phase="${2:-$(state_store_get_current_phase "$project_root")}"

  local snapshots_path
  snapshots_path=$(snapshots_dir "$project_root")
  mkdir -p "$snapshots_path"

  local timestamp entropy
  timestamp=$(date +%Y%m%d_%H%M%S)
  entropy="${RANDOM}"

  local snapshot_id="snap_${phase}_${timestamp}_${entropy}"
  local state feature_slug files_snapshot
  state=$(state_store_get_state "$project_root")
  feature_slug=$(echo "$state" | jq -r '.feature_slug // empty')
  files_snapshot=$(snapshot_store_capture_files_json "$project_root" "$feature_slug")

  snapshot_store_write_snapshot "$project_root" "$snapshot_id" "$phase" "$state" "$files_snapshot"
  snapshot_store_append_snapshot_reference "$project_root" "$snapshot_id" > /dev/null 2>&1 || true

  echo "$snapshot_id"
}

snapshot_store_create_snapshot() {
  local project_root="${1:-}"
  local phase="${2:-$(state_store_get_current_phase "$project_root")}"

  if ! acquire_lock "$project_root"; then
    echo "ERROR: Failed to acquire lock for snapshot creation" >&2
    return 1
  fi

  trap 'release_lock "$project_root"' EXIT

  local snapshot_id
  snapshot_id=$(snapshot_store_create_snapshot_internal "$project_root" "$phase")

  snapshot_store_cleanup_old_snapshots "$project_root"

  release_lock "$project_root"
  trap - EXIT

  echo "$snapshot_id"
}

snapshot_store_cleanup_old_snapshots() {
  local project_root="${1:-}"
  local snapshots_path
  snapshots_path=$(snapshots_dir "$project_root")

  local snapshot_files=("${snapshots_path}"/*.json)
  if [[ ! -e "${snapshot_files[0]:-}" ]]; then
    return 0
  fi

  local snapshot_count
  snapshot_count=${#snapshot_files[@]}

  if [[ "$snapshot_count" -gt "$MAX_SNAPSHOTS" ]]; then
    local to_delete=$((snapshot_count - MAX_SNAPSHOTS))
    snapshot_store_list_files_newest_first "$snapshots_path" | tail -n "$to_delete" | while read -r file; do
      rm -f "$file"
    done
  fi
}

snapshot_store_rollback_to_snapshot() {
  local project_root="${1:-}"
  local snapshot_id="${2:-}"

  local snapshot_file
  snapshot_file="$(snapshots_dir "$project_root")/${snapshot_id}.json"

  if [[ ! -f "$snapshot_file" ]]; then
    echo "ERROR: Snapshot not found: $snapshot_id" >&2
    return 1
  fi

  local snapshot_state
  snapshot_state=$(jq '.state' "$snapshot_file")
  echo "$snapshot_state" > "$(state_file "$project_root")"

  local to_phase
  to_phase=$(echo "$snapshot_state" | jq -r '.phase')
  state_store_log_transition "$project_root" "rollback" "unknown" "$to_phase" \
    "Rolled back to $snapshot_id"

  echo "✅ Rolled back to snapshot: $snapshot_id"
  echo "   Phase: $to_phase"
}

snapshot_store_list_snapshots() {
  local project_root="${1:-}"
  local snapshots_path
  snapshots_path=$(snapshots_dir "$project_root")

  if [[ ! -d "$snapshots_path" ]]; then
    echo "[]"
    return 0
  fi

  local result="[]"
  local snapshot_file entry
  for snapshot_file in "${snapshots_path}"/snap_*.json; do
    if [[ -f "$snapshot_file" ]]; then
      entry=$(jq '{id: .id, phase: .phase, created_at: .created_at}' "$snapshot_file")
      result=$(echo "$result" | jq '. + ['"$entry"']')
    fi
  done

  echo "$result" | jq 'sort_by(.created_at) | reverse'
}

snapshot_store_create_snapshot_without_lock() {
  snapshot_store_create_snapshot_internal "$@"
}
