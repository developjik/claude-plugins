#!/usr/bin/env bash

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$LIB_DIR/../.." && pwd)"
# shellcheck source=./state.sh
source "$LIB_DIR/state.sh"
# shellcheck source=./worktree.sh
source "$LIB_DIR/worktree.sh"

cff_bootstrap_specs_root() {
  local project_root="$1"
  printf '%s/docs/specs\n' "$project_root"
}

cff_bootstrap_ticket_specs_dir() {
  local project_root="$1"
  local ticket_key="$2"
  printf '%s/%s\n' "$(cff_bootstrap_specs_root "$project_root")" "$ticket_key"
}

cff_bootstrap_intake_path() {
  local project_root="$1"
  local ticket_key="$2"
  printf '%s/intake.md\n' "$(cff_bootstrap_ticket_specs_dir "$project_root" "$ticket_key")"
}

cff_bootstrap_prepare_layout() {
  local project_root="$1"
  local ticket_key="$2"

  mkdir -p \
    "$(cff_worktree_root "$project_root")" \
    "$(cff_bootstrap_ticket_specs_dir "$project_root" "$ticket_key")"
}

cff_bootstrap_seed_ticket_state() {
  local project_root="$1"
  local ticket_key="$2"
  local base_branch="${3:-main}"
  local ticket_path
  local worktree_path
  local branch_name

  ticket_path="$(cff_ticket_state_path "$project_root" "$ticket_key")"
  worktree_path="$(cff_worktree_path "$project_root" "$ticket_key")"
  branch_name="$(cff_branch_name "$ticket_key")"

  cff_state_init_index "$project_root"
  if [[ ! -f "$ticket_path" ]]; then
    cff_state_init_ticket "$project_root" "$ticket_key" "$project_root" "$worktree_path" "$branch_name" "$base_branch"
  fi
  cff_state_set_active_ticket "$project_root" "$ticket_key"
}

cff_bootstrap_write_intake() {
  local project_root="$1"
  local ticket_key="$2"
  local issue_id="$3"
  local summary="$4"
  local jira_url="$5"
  local initial_notes="${6:-Initial ticket context collected. Clarify unresolved questions before planning.}"
  local intake_path
  local worktree_path
  local branch_name
  local template_path
  local now

  intake_path="$(cff_bootstrap_intake_path "$project_root" "$ticket_key")"
  worktree_path="$(cff_worktree_path "$project_root" "$ticket_key")"
  branch_name="$(cff_branch_name "$ticket_key")"
  template_path="$PLUGIN_ROOT/templates/intake.md"
  now="$(cff_now_iso8601)"

  python3 - "$template_path" "$intake_path" "$ticket_key" "$issue_id" "$summary" "$jira_url" "$project_root" "$worktree_path" "$branch_name" "$initial_notes" <<'PY'
import pathlib
import sys

(
    template_path,
    intake_path,
    ticket_key,
    issue_id,
    summary,
    jira_url,
    project_root,
    worktree_path,
    branch_name,
    initial_notes,
) = sys.argv[1:11]

template = pathlib.Path(template_path).read_text(encoding="utf-8")
rendered = (
    template.replace("{{TICKET_KEY}}", ticket_key)
    .replace("{{ISSUE_ID}}", issue_id)
    .replace("{{TICKET_SUMMARY}}", summary)
    .replace("{{JIRA_URL}}", jira_url)
    .replace("{{PROJECT_ROOT}}", project_root)
    .replace("{{WORKTREE_PATH}}", worktree_path)
    .replace("{{BRANCH_NAME}}", branch_name)
    .replace("{{CONFLUENCE_SOURCES}}", "없음")
    .replace("{{FIGMA_SOURCES}}", "없음")
    .replace("{{INITIAL_NOTES}}", initial_notes)
)

path = pathlib.Path(intake_path)
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(rendered, encoding="utf-8")
PY

  cff_state_set_jira_source "$project_root" "$ticket_key" "$issue_id" "$summary" "$jira_url" "$now"
  cff_state_set_artifact "$project_root" "$ticket_key" "intake" "docs/specs/$ticket_key/intake.md" "true" "$now"
  cff_state_set_phase "$project_root" "$ticket_key" "branch-ready"
}

cff_bootstrap_ticket() {
  local project_root="$1"
  local ticket_key="$2"
  local issue_id="${3:-$ticket_key}"
  local summary="${4:-Untitled ticket}"
  local jira_url="${5:-https://jira.example.com/browse/$ticket_key}"
  local base_branch="${6:-main}"
  local initial_notes="${7:-Initial ticket context collected. Clarify unresolved questions before planning.}"

  cff_assert_ticket_key "$ticket_key"
  cff_bootstrap_prepare_layout "$project_root" "$ticket_key"
  cff_bootstrap_seed_ticket_state "$project_root" "$ticket_key" "$base_branch"
  cff_bootstrap_write_intake "$project_root" "$ticket_key" "$issue_id" "$summary" "$jira_url" "$initial_notes"
}
