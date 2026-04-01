#!/usr/bin/env bash

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$LIB_DIR/common.sh"

CFF_TICKET_PHASES=(
  intake
  branch-ready
  clarify-draft
  clarify-approved
  plan-draft
  plan-approved
  design-draft
  design-approved
  implementing
  checking
  iterating
  syncing-docs
  done
  blocked
)

CFF_TICKET_STATUSES=(
  active
  blocked
  done
  archived
)

CFF_ARTIFACT_KEYS=(
  intake
  clarify
  plan
  design
  tasks
  check
  wrapup
)

CFF_APPROVAL_KEYS=(
  clarify
  plan
  design
)

cff_runtime_dir() {
  local project_root="$1"
  printf '%s/.colo-fe-flow\n' "$project_root"
}

cff_state_dir() {
  local project_root="$1"
  printf '%s/.state\n' "$(cff_runtime_dir "$project_root")"
}

cff_index_path() {
  local project_root="$1"
  printf '%s/index.json\n' "$(cff_state_dir "$project_root")"
}

cff_ticket_state_path() {
  local project_root="$1"
  local ticket_key="$2"
  printf '%s/tickets/%s.json\n' "$(cff_state_dir "$project_root")" "$ticket_key"
}

cff_state_ensure_runtime_layout() {
  local project_root="$1"
  local runtime_dir

  runtime_dir="$(cff_runtime_dir "$project_root")"

  mkdir -p \
    "$runtime_dir/.state/tickets" \
    "$runtime_dir/.cache/jira" \
    "$runtime_dir/.cache/confluence" \
    "$runtime_dir/.cache/figma" \
    "$runtime_dir/.log"
}

cff_state_init_index() {
  local project_root="$1"
  local index_path
  local now

  cff_state_ensure_runtime_layout "$project_root"

  index_path="$(cff_index_path "$project_root")"
  if [[ -f "$index_path" ]]; then
    return 0
  fi

  now="$(cff_now_iso8601)"
  cff_json_write_pretty "$index_path" "$(cat <<JSON
{"schema_version":1,"active_ticket":null,"open_tickets":[],"ticket_worktrees":{},"last_ticket":null,"updated_at":"$now"}
JSON
)"
}

cff_state_get_active_ticket() {
  local project_root="$1"
  local index_path

  index_path="$(cff_index_path "$project_root")"
  if [[ ! -f "$index_path" ]]; then
    return 0
  fi

  local value
  value="$(cff_json_get "$index_path" "active_ticket" "null")"
  if [[ "$value" == "null" ]]; then
    return 0
  fi
  printf '%s\n' "$value"
}

cff_state_set_active_ticket() {
  local project_root="$1"
  local ticket_key="$2"
  local index_path
  local now

  cff_assert_ticket_key "$ticket_key"
  cff_state_init_index "$project_root"
  index_path="$(cff_index_path "$project_root")"
  now="$(cff_now_iso8601)"

  python3 - "$index_path" "$ticket_key" "$now" <<'PY'
import json
import sys

index_path, ticket_key, now = sys.argv[1:4]

with open(index_path, "r", encoding="utf-8") as handle:
    data = json.load(handle)

previous = data.get("active_ticket")
if previous and previous != ticket_key:
    data["last_ticket"] = previous

data["active_ticket"] = ticket_key
open_tickets = data.setdefault("open_tickets", [])
if ticket_key not in open_tickets:
    open_tickets.append(ticket_key)
data["updated_at"] = now

with open(index_path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=True, indent=2)
    handle.write("\n")
PY
}

cff_state_init_ticket() {
  local project_root="$1"
  local ticket_key="$2"
  local project_root_value="${3:-$project_root}"
  local worktree_path="${4:-$project_root/.worktrees/$ticket_key}"
  local branch_name="${5:-feat/$ticket_key}"
  local base_branch="${6:-main}"
  local ticket_path
  local index_path
  local now

  cff_assert_ticket_key "$ticket_key"
  cff_state_init_index "$project_root"

  ticket_path="$(cff_ticket_state_path "$project_root" "$ticket_key")"
  index_path="$(cff_index_path "$project_root")"
  now="$(cff_now_iso8601)"

  python3 - "$ticket_path" "$ticket_key" "$project_root_value" "$worktree_path" "$branch_name" "$base_branch" "$now" <<'PY'
import json
import sys

ticket_path, ticket_key, project_root, worktree_path, branch_name, base_branch, now = sys.argv[1:8]

artifact_names = ("intake", "clarify", "plan", "design", "tasks", "check", "wrapup")
artifact_state = {
    name: {
        "path": f"docs/specs/{ticket_key}/{name}.md" if name != "tasks" else f"docs/specs/{ticket_key}/tasks.json",
        "exists": False,
        "updated_at": None,
    }
    for name in artifact_names
}

data = {
    "schema_version": 1,
    "ticket_key": ticket_key,
    "status": "active",
    "phase": "intake",
    "created_at": now,
    "updated_at": now,
    "sources": {
        "jira": {
            "issue_id": None,
            "summary": None,
            "url": None,
            "last_synced_at": None,
        },
        "confluence": [],
        "figma": [],
    },
    "workspace": {
        "project_root": project_root,
        "worktree_path": worktree_path,
        "branch_name": branch_name,
        "base_branch": base_branch,
    },
    "artifacts": artifact_state,
    "approvals": {
        "clarify": {"approved": False, "approved_at": None},
        "plan": {"approved": False, "approved_at": None},
        "design": {"approved": False, "approved_at": None},
    },
    "implementation": {
        "started": False,
        "started_at": None,
        "finished": False,
        "finished_at": None,
        "task_summary": {
            "total": 0,
            "completed": 0,
            "parallel_groups": 0,
        },
    },
    "verification": {
        "last_check_status": "not_run",
        "last_check_at": None,
        "open_gaps": 0,
        "plan_compliance_score": None,
        "classes": {
            "A": "not_run",
            "B": "not_run",
            "C": "not_run",
            "D": "not_run",
        },
    },
    "doc_sync": {
        "required": True,
        "completed": False,
        "last_synced_at": None,
        "affected_docs": [],
    },
    "iteration": {
        "count": 0,
        "last_reason": None,
    },
}

with open(ticket_path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=True, indent=2)
    handle.write("\n")
PY

  python3 - "$index_path" "$ticket_key" "$worktree_path" "$now" <<'PY'
import json
import sys

index_path, ticket_key, worktree_path, now = sys.argv[1:5]

with open(index_path, "r", encoding="utf-8") as handle:
    data = json.load(handle)

open_tickets = data.setdefault("open_tickets", [])
if ticket_key not in open_tickets:
    open_tickets.append(ticket_key)

ticket_worktrees = data.setdefault("ticket_worktrees", {})
ticket_worktrees[ticket_key] = worktree_path
data["updated_at"] = now

with open(index_path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=True, indent=2)
    handle.write("\n")
PY
}

cff_state_set_phase() {
  local project_root="$1"
  local ticket_key="$2"
  local phase="$3"
  local ticket_path
  local now

  ticket_path="$(cff_ticket_state_path "$project_root" "$ticket_key")"
  now="$(cff_now_iso8601)"

  python3 - "$ticket_path" "$phase" "$now" <<'PY'
import json
import sys

ticket_path, phase, now = sys.argv[1:4]

with open(ticket_path, "r", encoding="utf-8") as handle:
    data = json.load(handle)

data["phase"] = phase
data["updated_at"] = now

with open(ticket_path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=True, indent=2)
    handle.write("\n")
PY
}

cff_state_set_status() {
  local project_root="$1"
  local ticket_key="$2"
  local status="$3"
  local ticket_path
  local now

  ticket_path="$(cff_ticket_state_path "$project_root" "$ticket_key")"
  now="$(cff_now_iso8601)"

  python3 - "$ticket_path" "$status" "$now" <<'PY'
import json
import sys

ticket_path, status, now = sys.argv[1:4]

with open(ticket_path, "r", encoding="utf-8") as handle:
    data = json.load(handle)

data["status"] = status
data["updated_at"] = now

with open(ticket_path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=True, indent=2)
    handle.write("\n")
PY
}

cff_state_set_artifact() {
  local project_root="$1"
  local ticket_key="$2"
  local artifact_key="$3"
  local artifact_path="$4"
  local exists="$5"
  local artifact_updated_at="${6:-$(cff_now_iso8601)}"
  local ticket_path
  local now

  ticket_path="$(cff_ticket_state_path "$project_root" "$ticket_key")"
  now="$(cff_now_iso8601)"

  python3 - "$ticket_path" "$artifact_key" "$artifact_path" "$exists" "$artifact_updated_at" "$now" <<'PY'
import json
import sys

ticket_path, artifact_key, artifact_path, exists, artifact_updated_at, now = sys.argv[1:7]

with open(ticket_path, "r", encoding="utf-8") as handle:
    data = json.load(handle)

artifact = data["artifacts"].setdefault(artifact_key, {})
artifact["path"] = artifact_path
artifact["exists"] = exists.lower() == "true"
artifact["updated_at"] = artifact_updated_at if artifact["exists"] else None
data["updated_at"] = now

with open(ticket_path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=True, indent=2)
    handle.write("\n")
PY
}

cff_state_set_doc_sync() {
  local project_root="$1"
  local ticket_key="$2"
  local completed="$3"
  local last_synced_at="${4:-null}"
  local affected_docs_json="${5:-[]}"
  local ticket_path
  local now

  ticket_path="$(cff_ticket_state_path "$project_root" "$ticket_key")"
  now="$(cff_now_iso8601)"

  python3 - "$ticket_path" "$completed" "$last_synced_at" "$affected_docs_json" "$now" <<'PY'
import json
import sys

ticket_path, completed, last_synced_at, affected_docs_json, now = sys.argv[1:6]

with open(ticket_path, "r", encoding="utf-8") as handle:
    data = json.load(handle)

doc_sync = data.setdefault("doc_sync", {})
doc_sync["required"] = True
doc_sync["completed"] = completed.lower() == "true"
doc_sync["last_synced_at"] = None if last_synced_at == "null" else last_synced_at
doc_sync["affected_docs"] = json.loads(affected_docs_json)
data["updated_at"] = now

with open(ticket_path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=True, indent=2)
    handle.write("\n")
PY
}

cff_state_set_jira_source() {
  local project_root="$1"
  local ticket_key="$2"
  local issue_id="${3:-null}"
  local summary="${4:-null}"
  local url="${5:-null}"
  local last_synced_at="${6:-$(cff_now_iso8601)}"
  local ticket_path
  local now

  ticket_path="$(cff_ticket_state_path "$project_root" "$ticket_key")"
  now="$(cff_now_iso8601)"

  python3 - "$ticket_path" "$issue_id" "$summary" "$url" "$last_synced_at" "$now" <<'PY'
import json
import sys

ticket_path, issue_id, summary, url, last_synced_at, now = sys.argv[1:7]

def to_optional(value: str):
    return None if value == "null" else value

with open(ticket_path, "r", encoding="utf-8") as handle:
    data = json.load(handle)

jira = data.setdefault("sources", {}).setdefault("jira", {})
jira["issue_id"] = to_optional(issue_id)
jira["summary"] = to_optional(summary)
jira["url"] = to_optional(url)
jira["last_synced_at"] = to_optional(last_synced_at)
data["updated_at"] = now

with open(ticket_path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=True, indent=2)
    handle.write("\n")
PY
}
