#!/usr/bin/env bash

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$LIB_DIR/common.sh"

cff_worktree_root() {
  local project_root="$1"
  printf '%s/.worktrees\n' "$project_root"
}

cff_worktree_path() {
  local project_root="$1"
  local ticket_key="$2"
  printf '%s/%s\n' "$(cff_worktree_root "$project_root")" "$ticket_key"
}

cff_branch_name() {
  local ticket_key="$1"
  printf 'feat/%s\n' "$ticket_key"
}

