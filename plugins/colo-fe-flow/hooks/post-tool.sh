#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib/hook-runtime.sh
source "$SCRIPT_DIR/lib/hook-runtime.sh"

PAYLOAD="$(cat || true)"
PROJECT_ROOT="$(cff_hook_project_root "$PAYLOAD")"
TOOL_NAME="$(cff_hook_tool_name "$PAYLOAD")"
FILE_PATH="$(cff_hook_tool_file_path "$PAYLOAD")"
COMMAND="$(cff_hook_tool_command "$PAYLOAD")"
ACTIVE_TICKET="$(cff_state_get_active_ticket "$PROJECT_ROOT")"

if [[ "$TOOL_NAME" == "Write" || "$TOOL_NAME" == "Edit" ]]; then
  ABSOLUTE_PATH="$(cff_hook_absolute_path "$PROJECT_ROOT" "$FILE_PATH")"
  INFERRED="$(cff_hook_infer_ticket_and_artifact "$ABSOLUTE_PATH")"
  TARGET_TICKET="${INFERRED%%|*}"
  TARGET_ARTIFACT="${INFERRED#*|}"

  if [[ -n "$TARGET_TICKET" && -n "$TARGET_ARTIFACT" ]]; then
    case "$TARGET_ARTIFACT" in
      tasks)
        cff_state_set_artifact "$PROJECT_ROOT" "$TARGET_TICKET" "tasks" "docs/specs/$TARGET_TICKET/tasks.json" "true"
        ;;
      intake|clarify|plan|design|check|wrapup)
        cff_state_set_artifact "$PROJECT_ROOT" "$TARGET_TICKET" "$TARGET_ARTIFACT" "docs/specs/$TARGET_TICKET/$TARGET_ARTIFACT.md" "true"
        ;;
    esac
  fi
fi

if [[ -n "$ACTIVE_TICKET" ]]; then
  cff_log_append "$PROJECT_ROOT" "$ACTIVE_TICKET" "POST_TOOL tool=${TOOL_NAME:-unknown} file=${FILE_PATH:-} command=${COMMAND:-}"
else
  cff_log_append_runtime "$PROJECT_ROOT" "tooling" "POST_TOOL tool=${TOOL_NAME:-unknown} file=${FILE_PATH:-} command=${COMMAND:-}"
fi
