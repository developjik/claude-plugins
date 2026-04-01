#!/usr/bin/env bash

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$LIB_DIR/../.." && pwd)"
# shellcheck source=./approval.sh
source "$LIB_DIR/approval.sh"
# shellcheck source=./bootstrap.sh
source "$LIB_DIR/bootstrap.sh"

cff_planning_summary() {
  local project_root="$1"
  local ticket_key="$2"
  local ticket_path

  ticket_path="$(cff_ticket_state_path "$project_root" "$ticket_key")"
  cff_json_get "$ticket_path" "sources.jira.summary" "$ticket_key"
}

cff_planning_artifact_path() {
  local project_root="$1"
  local ticket_key="$2"
  local artifact_key="$3"

  case "$artifact_key" in
    tasks)
      printf '%s/tasks.json\n' "$(cff_bootstrap_ticket_specs_dir "$project_root" "$ticket_key")"
      ;;
    *)
      printf '%s/%s.md\n' "$(cff_bootstrap_ticket_specs_dir "$project_root" "$ticket_key")" "$artifact_key"
      ;;
  esac
}

cff_planning_render_markdown_template() {
  local template_name="$1"
  local output_path="$2"
  local ticket_key="$3"
  local summary="$4"
  local upstream_ref="$5"
  local notes="$6"

  python3 - "$PLUGIN_ROOT/templates/$template_name" "$output_path" "$ticket_key" "$summary" "$upstream_ref" "$notes" <<'PY'
import pathlib
import sys

template_path, output_path, ticket_key, summary, upstream_ref, notes = sys.argv[1:7]
template = pathlib.Path(template_path).read_text(encoding="utf-8")
rendered = (
    template.replace("{{TICKET_KEY}}", ticket_key)
    .replace("{{TICKET_SUMMARY}}", summary)
    .replace("{{UPSTREAM_REF}}", upstream_ref)
    .replace("{{NOTES}}", notes)
)

path = pathlib.Path(output_path)
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(rendered, encoding="utf-8")
PY
}

cff_planning_write_tasks() {
  local project_root="$1"
  local ticket_key="$2"
  local summary="$3"
  local notes="$4"
  local output_path

  output_path="$(cff_planning_artifact_path "$project_root" "$ticket_key" "tasks")"

  python3 - "$output_path" "$ticket_key" "$summary" "$notes" <<'PY'
import json
import pathlib
import sys

output_path, ticket_key, summary, notes = sys.argv[1:5]
payload = {
    "schema_version": 1,
    "ticket_key": ticket_key,
    "generated_from": {
        "plan": f"docs/specs/{ticket_key}/plan.md",
        "design": f"docs/specs/{ticket_key}/design.md",
    },
    "tasks": [
        {
            "id": f"{ticket_key}-T1",
            "title": f"Implement {summary}",
            "phase": "implement",
            "parallel_safe": False,
            "target_files": [],
            "acceptance": [
                notes,
                "Implementation should stay aligned with plan.md and design.md.",
            ],
        }
    ],
}

path = pathlib.Path(output_path)
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(payload, ensure_ascii=True, indent=2) + "\n", encoding="utf-8")
PY

  cff_state_set_artifact "$project_root" "$ticket_key" "tasks" "docs/specs/$ticket_key/tasks.json" "true"
}

cff_planning_write_stage_artifact() {
  local project_root="$1"
  local ticket_key="$2"
  local stage_key="$3"
  local notes="$4"
  local template_name="$5"
  local upstream_ref="$6"
  local phase_name="$7"
  local summary
  local output_path

  summary="$(cff_planning_summary "$project_root" "$ticket_key")"
  output_path="$(cff_planning_artifact_path "$project_root" "$ticket_key" "$stage_key")"

  cff_planning_render_markdown_template "$template_name" "$output_path" "$ticket_key" "$summary" "$upstream_ref" "$notes"
  cff_state_set_artifact "$project_root" "$ticket_key" "$stage_key" "docs/specs/$ticket_key/$stage_key.md" "true"
  cff_approval_reset_from "$project_root" "$ticket_key" "$stage_key"
  cff_state_set_phase "$project_root" "$ticket_key" "$phase_name"
}

cff_planning_write_clarify() {
  local project_root="$1"
  local ticket_key="$2"
  local notes="${3:-Clarify scope, assumptions, and unresolved questions.}"

  cff_planning_write_stage_artifact \
    "$project_root" \
    "$ticket_key" \
    "clarify" \
    "$notes" \
    "clarify.md" \
    "docs/specs/$ticket_key/intake.md" \
    "clarify-draft"
}

cff_planning_write_plan() {
  local project_root="$1"
  local ticket_key="$2"
  local notes="${3:-Turn clarified scope into execution steps and acceptance criteria.}"

  cff_planning_write_stage_artifact \
    "$project_root" \
    "$ticket_key" \
    "plan" \
    "$notes" \
    "plan.md" \
    "docs/specs/$ticket_key/clarify.md" \
    "plan-draft"
}

cff_planning_write_design() {
  local project_root="$1"
  local ticket_key="$2"
  local notes="${3:-Translate the approved plan into file-level design and atomic tasks.}"
  local summary

  summary="$(cff_planning_summary "$project_root" "$ticket_key")"

  cff_planning_write_stage_artifact \
    "$project_root" \
    "$ticket_key" \
    "design" \
    "$notes" \
    "design.md" \
    "docs/specs/$ticket_key/plan.md" \
    "design-draft"
  cff_planning_write_tasks "$project_root" "$ticket_key" "$summary" "$notes"
}

cff_planning_approve_stage() {
  local project_root="$1"
  local ticket_key="$2"
  local stage_key="$3"

  cff_approval_set "$project_root" "$ticket_key" "$stage_key" "true"
  cff_state_set_phase "$project_root" "$ticket_key" "${stage_key}-approved"
}
