#!/usr/bin/env bash

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./state.sh
source "$LIB_DIR/state.sh"

cff_approval_is_approved() {
  local project_root="$1"
  local ticket_key="$2"
  local approval_key="$3"
  local ticket_path

  ticket_path="$(cff_ticket_state_path "$project_root" "$ticket_key")"
  [[ "$(cff_json_get "$ticket_path" "approvals.${approval_key}.approved" "false")" == "true" ]]
}

cff_approval_set() {
  local project_root="$1"
  local ticket_key="$2"
  local approval_key="$3"
  local approved="$4"
  local approved_at="${5:-$(cff_now_iso8601)}"
  local ticket_path
  local now

  ticket_path="$(cff_ticket_state_path "$project_root" "$ticket_key")"
  now="$(cff_now_iso8601)"

  python3 - "$ticket_path" "$approval_key" "$approved" "$approved_at" "$now" <<'PY'
import json
import sys

ticket_path, approval_key, approved, approved_at, now = sys.argv[1:6]

with open(ticket_path, "r", encoding="utf-8") as handle:
    data = json.load(handle)

approval = data["approvals"].setdefault(approval_key, {})
approved_bool = approved.lower() == "true"
approval["approved"] = approved_bool
approval["approved_at"] = approved_at if approved_bool else None
data["updated_at"] = now

with open(ticket_path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=True, indent=2)
    handle.write("\n")
PY
}

cff_approval_reset_from() {
  local project_root="$1"
  local ticket_key="$2"
  local approval_key="$3"
  local ticket_path
  local now

  ticket_path="$(cff_ticket_state_path "$project_root" "$ticket_key")"
  now="$(cff_now_iso8601)"

  python3 - "$ticket_path" "$approval_key" "$now" <<'PY'
import json
import sys

ticket_path, approval_key, now = sys.argv[1:4]
order = ["clarify", "plan", "design"]

with open(ticket_path, "r", encoding="utf-8") as handle:
    data = json.load(handle)

start = order.index(approval_key)
for key in order[start:]:
    approval = data["approvals"].setdefault(key, {})
    approval["approved"] = False
    approval["approved_at"] = None

data["updated_at"] = now

with open(ticket_path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=True, indent=2)
    handle.write("\n")
PY
}

