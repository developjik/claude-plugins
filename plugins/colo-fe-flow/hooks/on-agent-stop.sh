#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib/hook-runtime.sh
source "$SCRIPT_DIR/lib/hook-runtime.sh"

PAYLOAD="$(cat || true)"
PROJECT_ROOT="$(cff_hook_project_root "$PAYLOAD")"
AGENT_NAME="$(cff_hook_agent_name "$PAYLOAD")"
ACTIVE_TICKET="$(cff_state_get_active_ticket "$PROJECT_ROOT")"

cff_log_append_runtime "$PROJECT_ROOT" "agents" "AGENT_STOP ${AGENT_NAME:-unknown} active_ticket=${ACTIVE_TICKET:-none}"

if [[ -n "$ACTIVE_TICKET" ]]; then
  cff_log_append "$PROJECT_ROOT" "$ACTIVE_TICKET" "AGENT_STOP ${AGENT_NAME:-unknown}"
fi
