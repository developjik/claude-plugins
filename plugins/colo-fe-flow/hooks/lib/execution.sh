#!/usr/bin/env bash

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$LIB_DIR/../.." && pwd)"
# shellcheck source=./bootstrap.sh
source "$LIB_DIR/bootstrap.sh"
# shellcheck source=./state.sh
source "$LIB_DIR/state.sh"
# shellcheck source=./verification.sh
source "$LIB_DIR/verification.sh"

cff_execution_render_template() {
  local template_name="$1"
  local output_path="$2"
  local ticket_key="$3"
  local summary="$4"
  local body="$5"
  local extra="$6"

  python3 - "$PLUGIN_ROOT/templates/$template_name" "$output_path" "$ticket_key" "$summary" "$body" "$extra" <<'PY'
import pathlib
import sys

template_path, output_path, ticket_key, summary, body, extra = sys.argv[1:7]
template = pathlib.Path(template_path).read_text(encoding="utf-8")
rendered = (
    template.replace("{{TICKET_KEY}}", ticket_key)
    .replace("{{TICKET_SUMMARY}}", summary)
    .replace("{{BODY}}", body)
    .replace("{{EXTRA}}", extra)
)

path = pathlib.Path(output_path)
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(rendered, encoding="utf-8")
PY
}

cff_execution_update_implementation() {
  local project_root="$1"
  local ticket_key="$2"
  local started="$3"
  local finished="$4"
  local total="$5"
  local completed="$6"
  local parallel_groups="$7"
  local ticket_path
  local now

  ticket_path="$(cff_ticket_state_path "$project_root" "$ticket_key")"
  now="$(cff_now_iso8601)"

  python3 - "$ticket_path" "$started" "$finished" "$total" "$completed" "$parallel_groups" "$now" <<'PY'
import json
import sys

ticket_path, started, finished, total, completed, parallel_groups, now = sys.argv[1:8]
started_bool = started.lower() == "true"
finished_bool = finished.lower() == "true"

with open(ticket_path, "r", encoding="utf-8") as handle:
    data = json.load(handle)

implementation = data.setdefault("implementation", {})
if started_bool and not implementation.get("started_at"):
    implementation["started_at"] = now

implementation["started"] = started_bool
implementation["finished"] = finished_bool
implementation["finished_at"] = now if finished_bool else None
summary = implementation.setdefault("task_summary", {})
summary["total"] = int(total)
summary["completed"] = int(completed)
summary["parallel_groups"] = int(parallel_groups)
data["updated_at"] = now

with open(ticket_path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=True, indent=2)
    handle.write("\n")
PY
}

cff_execution_start_implementation() {
  local project_root="$1"
  local ticket_key="$2"
  local total="${3:-0}"
  local parallel_groups="${4:-0}"

  cff_execution_update_implementation "$project_root" "$ticket_key" "true" "false" "$total" "0" "$parallel_groups"
  cff_state_set_phase "$project_root" "$ticket_key" "implementing"
}

cff_execution_finish_implementation() {
  local project_root="$1"
  local ticket_key="$2"
  local total="${3:-0}"
  local completed="${4:-$total}"
  local parallel_groups="${5:-0}"

  cff_execution_update_implementation "$project_root" "$ticket_key" "true" "true" "$total" "$completed" "$parallel_groups"
}

cff_execution_write_check() {
  local project_root="$1"
  local ticket_key="$2"
  local check_status="$3"
  local open_gaps="$4"
  local plan_compliance_score="$5"
  local summary_text="$6"
  local output_path
  local ticket_summary
  local classes_a="passed"
  local classes_b="passed"
  local classes_c="not_run"
  local classes_d="passed"

  ticket_summary="$(cff_json_get "$(cff_ticket_state_path "$project_root" "$ticket_key")" "sources.jira.summary" "$ticket_key")"
  output_path="$(cff_planning_artifact_path "$project_root" "$ticket_key" "check")"

  if [[ "$check_status" != "passed" ]]; then
    classes_d="failed"
  fi

  cff_execution_render_template "check.md" "$output_path" "$ticket_key" "$ticket_summary" "$summary_text" "open_gaps=$open_gaps, plan_compliance_score=$plan_compliance_score"
  cff_state_set_artifact "$project_root" "$ticket_key" "check" "docs/specs/$ticket_key/check.md" "true"
  cff_verification_record_check "$project_root" "$ticket_key" "$check_status" "$open_gaps" "$plan_compliance_score" "$classes_a" "$classes_b" "$classes_c" "$classes_d"
  cff_state_set_phase "$project_root" "$ticket_key" "checking"
}

cff_execution_iterate() {
  local project_root="$1"
  local ticket_key="$2"
  local reason="$3"
  local ticket_path
  local now

  ticket_path="$(cff_ticket_state_path "$project_root" "$ticket_key")"
  now="$(cff_now_iso8601)"

  python3 - "$ticket_path" "$reason" "$now" <<'PY'
import json
import sys

ticket_path, reason, now = sys.argv[1:4]

with open(ticket_path, "r", encoding="utf-8") as handle:
    data = json.load(handle)

iteration = data.setdefault("iteration", {})
iteration["count"] = int(iteration.get("count", 0)) + 1
iteration["last_reason"] = reason

implementation = data.setdefault("implementation", {})
implementation["finished"] = False
implementation["finished_at"] = None

data["updated_at"] = now

with open(ticket_path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=True, indent=2)
    handle.write("\n")
PY

  cff_state_set_phase "$project_root" "$ticket_key" "iterating"
}

cff_execution_sync_docs() {
  local project_root="$1"
  local ticket_key="$2"
  local affected_docs_json="$3"
  local summary_text="${4:-Finalize wrap-up and sync affected docs.}"
  local output_path
  local ticket_summary
  local affected_docs_pretty

  ticket_summary="$(cff_json_get "$(cff_ticket_state_path "$project_root" "$ticket_key")" "sources.jira.summary" "$ticket_key")"
  output_path="$(cff_planning_artifact_path "$project_root" "$ticket_key" "wrapup")"
  affected_docs_pretty="$(python3 - "$affected_docs_json" <<'PY'
import json
import sys
docs = json.loads(sys.argv[1])
print(", ".join(docs) if docs else "없음")
PY
)"

  cff_execution_render_template "wrapup.md" "$output_path" "$ticket_key" "$ticket_summary" "$summary_text" "$affected_docs_pretty"
  cff_state_set_artifact "$project_root" "$ticket_key" "wrapup" "docs/specs/$ticket_key/wrapup.md" "true"
  cff_state_set_doc_sync "$project_root" "$ticket_key" "true" "$(cff_now_iso8601)" "$affected_docs_json"
  cff_state_set_phase "$project_root" "$ticket_key" "syncing-docs"
}

cff_execution_complete_ticket() {
  local project_root="$1"
  local ticket_key="$2"

  cff_state_set_status "$project_root" "$ticket_key" "done"
  cff_state_set_phase "$project_root" "$ticket_key" "done"
}
