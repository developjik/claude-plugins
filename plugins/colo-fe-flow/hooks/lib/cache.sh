#!/usr/bin/env bash

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$LIB_DIR/common.sh"

cff_cache_dir() {
  local project_root="$1"
  printf '%s/.colo-fe-flow/.cache\n' "$project_root"
}

cff_cache_namespace_dir() {
  local project_root="$1"
  local namespace="$2"
  printf '%s/%s\n' "$(cff_cache_dir "$project_root")" "$namespace"
}

cff_cache_file() {
  local project_root="$1"
  local namespace="$2"
  local file_name="$3"
  printf '%s/%s\n' "$(cff_cache_namespace_dir "$project_root" "$namespace")" "$file_name"
}

cff_cache_write_json() {
  local project_root="$1"
  local namespace="$2"
  local file_name="$3"
  local payload="$4"
  local cache_file

  cache_file="$(cff_cache_file "$project_root" "$namespace" "$file_name")"
  mkdir -p "$(dirname "$cache_file")"
  cff_json_write_pretty "$cache_file" "$payload"
}

cff_cache_read_json() {
  local project_root="$1"
  local namespace="$2"
  local file_name="$3"
  local cache_file

  cache_file="$(cff_cache_file "$project_root" "$namespace" "$file_name")"
  cat "$cache_file"
}

