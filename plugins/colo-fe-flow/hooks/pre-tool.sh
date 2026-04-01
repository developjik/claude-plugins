#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib/hook-runtime.sh
source "$SCRIPT_DIR/lib/hook-runtime.sh"
# shellcheck source=./lib/dependency-check.sh
source "$SCRIPT_DIR/lib/dependency-check.sh"
# shellcheck source=./lib/planning.sh
source "$SCRIPT_DIR/lib/planning.sh"

PAYLOAD="$(cat || true)"
PROJECT_ROOT="$(cff_hook_project_root "$PAYLOAD")"
TOOL_NAME="$(cff_hook_tool_name "$PAYLOAD")"
FILE_PATH="$(cff_hook_tool_file_path "$PAYLOAD")"
COMMAND="$(cff_hook_tool_command "$PAYLOAD")"
ACTIVE_TICKET="$(cff_state_get_active_ticket "$PROJECT_ROOT")"

if ! require_declared_mcp_servers "$PROJECT_ROOT" >/dev/null 2>&1; then
  cff_hook_emit_block "missing required mcp servers"
  exit 0
fi

if [[ -n "$ACTIVE_TICKET" && ! -f "$(cff_ticket_state_path "$PROJECT_ROOT" "$ACTIVE_TICKET")" ]]; then
  cff_hook_emit_block "active ticket state is missing"
  exit 0
fi

if [[ "$TOOL_NAME" == "Write" || "$TOOL_NAME" == "Edit" ]]; then
  ABSOLUTE_PATH="$(cff_hook_absolute_path "$PROJECT_ROOT" "$FILE_PATH")"
  INFERRED="$(cff_hook_infer_ticket_and_artifact "$ABSOLUTE_PATH")"
  TARGET_TICKET="${INFERRED%%|*}"
  TARGET_ARTIFACT="${INFERRED#*|}"

  case "$TARGET_ARTIFACT" in
    clarify|plan|design)
      if [[ -n "$TARGET_TICKET" ]]; then
        cff_approval_reset_from "$PROJECT_ROOT" "$TARGET_TICKET" "$TARGET_ARTIFACT"
        cff_state_set_phase "$PROJECT_ROOT" "$TARGET_TICKET" "${TARGET_ARTIFACT}-draft"
        cff_log_append "$PROJECT_ROOT" "$TARGET_TICKET" "PRE_TOOL stale_artifact_reset artifact=$TARGET_ARTIFACT tool=$TOOL_NAME"
      fi
      ;;
  esac
fi

if [[ -n "$ACTIVE_TICKET" ]]; then
  cff_log_append "$PROJECT_ROOT" "$ACTIVE_TICKET" "PRE_TOOL tool=${TOOL_NAME:-unknown} file=${FILE_PATH:-} command=${COMMAND:-}"
else
  cff_log_append_runtime "$PROJECT_ROOT" "tooling" "PRE_TOOL tool=${TOOL_NAME:-unknown} file=${FILE_PATH:-} command=${COMMAND:-}"
fi
