#!/usr/bin/env bash

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./state.sh
source "$LIB_DIR/state.sh"

cff_utility_ticket_known() {
  local project_root="$1"
  local ticket_key="$2"

  [[ -f "$(cff_ticket_state_path "$project_root" "$ticket_key")" ]]
}

cff_utility_list_tickets_json() {
  local project_root="$1"
  local index_path
  local state_dir

  index_path="$(cff_index_path "$project_root")"
  state_dir="$(cff_state_dir "$project_root")/tickets"

  python3 - "$index_path" "$state_dir" <<'PY'
import json
import pathlib
import sys

index_path = pathlib.Path(sys.argv[1])
state_dir = pathlib.Path(sys.argv[2])

if index_path.exists():
    index_data = json.loads(index_path.read_text(encoding="utf-8"))
else:
    index_data = {
        "active_ticket": None,
        "last_ticket": None,
        "open_tickets": [],
    }

tickets = []
for ticket_key in index_data.get("open_tickets", []):
    ticket_path = state_dir / f"{ticket_key}.json"
    ticket_data = {}
    if ticket_path.exists():
        ticket_data = json.loads(ticket_path.read_text(encoding="utf-8"))
    tickets.append({
        "ticket_key": ticket_key,
        "is_active": ticket_key == index_data.get("active_ticket"),
        "status": ticket_data.get("status"),
        "phase": ticket_data.get("phase"),
    })

payload = {
    "active_ticket": index_data.get("active_ticket"),
    "last_ticket": index_data.get("last_ticket"),
    "tickets": tickets,
}

json.dump(payload, sys.stdout, ensure_ascii=True, indent=2)
sys.stdout.write("\n")
PY
}

cff_utility_show_ticket_status_json() {
  local project_root="$1"
  local requested_ticket="${2:-}"
  local ticket_key
  local ticket_path

  ticket_key="${requested_ticket:-$(cff_state_get_active_ticket "$project_root")}"
  if [[ -z "$ticket_key" ]]; then
    echo "no active ticket" >&2
    return 1
  fi

  ticket_path="$(cff_ticket_state_path "$project_root" "$ticket_key")"
  if [[ ! -f "$ticket_path" ]]; then
    echo "unknown ticket: $ticket_key" >&2
    return 1
  fi

  python3 - "$ticket_path" "$ticket_key" "$(cff_state_get_active_ticket "$project_root")" <<'PY'
import json
import sys

ticket_path, ticket_key, active_ticket = sys.argv[1:4]
data = json.loads(open(ticket_path, "r", encoding="utf-8").read())

payload = {
    "ticket_key": ticket_key,
    "is_active": ticket_key == active_ticket,
    "status": data.get("status"),
    "phase": data.get("phase"),
    "summary": data.get("sources", {}).get("jira", {}).get("summary"),
    "last_check_status": data.get("verification", {}).get("last_check_status"),
    "open_gaps": data.get("verification", {}).get("open_gaps"),
    "doc_sync_completed": data.get("doc_sync", {}).get("completed"),
}

json.dump(payload, sys.stdout, ensure_ascii=True, indent=2)
sys.stdout.write("\n")
PY
}

cff_utility_switch_ticket() {
  local project_root="$1"
  local ticket_key="$2"

  cff_assert_ticket_key "$ticket_key"
  if ! cff_utility_ticket_known "$project_root" "$ticket_key"; then
    echo "unknown ticket: $ticket_key" >&2
    return 1
  fi

  cff_state_set_active_ticket "$project_root" "$ticket_key"
}
