#!/usr/bin/env bash
# subagent-request.sh — subagent request/build/start helpers

set -euo pipefail

: "${SUBAGENT_DIR:=.harness/subagents}"
: "${SUBAGENT_STATE_FILE:=state.json}"
: "${SUBAGENT_TASK_FILE:=task.md}"
: "${SUBAGENT_CONTEXT_FILE:=context.md}"
: "${SUBAGENT_EXECUTION_REQUEST_FILE:=execution-request.json}"
: "${SUBAGENT_ADAPTER_RESULT_FILE:=adapter-result.json}"
: "${SUBAGENT_COLLECTED_RESULT_FILE:=collected-result.json}"
: "${SUBAGENT_RESULT_FILE:=result.md}"
: "${SUBAGENT_FAILURE_FILE:=failure.json}"

subagent_request_prepare_context() {
  local project_root="${1:-}"
  local subagent_dir="${2:-}"
  local purpose="${3:-task_execution}"

  local context_file="${subagent_dir}/${SUBAGENT_CONTEXT_FILE}"
  local context=""

  context+="# Subagent Context\n\n"
  context+="## Purpose\n\n$purpose\n\n"

  if [[ -f "${project_root}/PROJECT.md" ]]; then
    context+="## Project Overview\n\n"
    context+="$(head -100 "${project_root}/PROJECT.md" 2> /dev/null)\n\n"
  fi

  case "$purpose" in
    code_review)
      if [[ -f "${project_root}/CLAUDE.md" ]]; then
        context+="## Guidelines\n\n"
        context+="$(head -50 "${project_root}/CLAUDE.md" 2> /dev/null)\n\n"
      fi
      ;;
  esac

  if [[ -f "${subagent_dir}/${SUBAGENT_TASK_FILE}" ]]; then
    context+="## Task\n\n"
    context+="$(cat "${subagent_dir}/${SUBAGENT_TASK_FILE}")\n\n"
  fi

  context+="## Output Contract\n\n"
  context+="- Write the human-readable summary to: ${SUBAGENT_RESULT_FILE}\n"
  context+="- If an adapter emits raw structured output, persist it to: ${SUBAGENT_ADAPTER_RESULT_FILE}\n"
  context+="- Normalize collected execution output into: ${SUBAGENT_COLLECTED_RESULT_FILE}\n"
  context+="- If execution fails, write failure details as JSON to: ${SUBAGENT_FAILURE_FILE}\n"

  echo -e "$context" > "$context_file"
}

subagent_request_spawn() {
  local task_file="${1:-}"
  local project_root="${2:-}"
  local model="${3:-sonnet}"
  local purpose="${4:-task_execution}"

  local timestamp
  timestamp=$(date +%s)
  local random_suffix
  random_suffix=$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom 2> /dev/null | head -c 6 || echo "rand$$")
  local subagent_id="subagent_${timestamp}_${random_suffix}"

  local subagent_dir
  subagent_dir=$(get_subagent_dir_path "$subagent_id" "$project_root")
  mkdir -p "$subagent_dir"

  if [[ -f "$task_file" ]]; then
    cp "$task_file" "${subagent_dir}/${SUBAGENT_TASK_FILE}"
  else
    echo "$task_file" > "${subagent_dir}/${SUBAGENT_TASK_FILE}"
  fi

  subagent_request_prepare_context "$project_root" "$subagent_dir" "$purpose"

  local model_full
  model_full=$(get_model_full_name "$model")
  local created_at
  created_at=$(subagent_now_utc)
  local artifacts_json
  artifacts_json=$(get_subagent_artifact_paths "$subagent_id" "$project_root")

  jq -n \
    --arg id "$subagent_id" \
    --arg status "pending" \
    --arg model "$model_full" \
    --arg model_short "$model" \
    --arg purpose "$purpose" \
    --arg task_file "$(basename "${task_file:-${SUBAGENT_TASK_FILE}}")" \
    --arg created_at "$created_at" \
    --argjson artifacts "$artifacts_json" \
    '{
      id: $id,
      status: $status,
      model: $model,
      model_short: $model_short,
      purpose: $purpose,
      task_file: $task_file,
      created_at: $created_at,
      started_at: null,
      completed_at: null,
      duration_ms: null,
      result: null,
      error: null,
      artifacts: $artifacts,
      lifecycle: {
        created_at: $created_at,
        prepared_at: null,
        started_at: null,
        collected_at: null,
        completed_at: null
      },
      executor: {
        name: null,
        run_id: null,
        request_file: $artifacts.execution_request_file,
        metadata: {}
      }
    }' > "${subagent_dir}/${SUBAGENT_STATE_FILE}"

  if declare -f log_event > /dev/null 2>&1; then
    log_event "$project_root" "INFO" "subagent_spawned" "Subagent created" \
      "{\"subagent_id\":\"$subagent_id\",\"model\":\"$model\"}"
  fi

  echo "$subagent_id"
}

subagent_request_build_execution_contract() {
  local subagent_id="${1:-}"
  local project_root="${2:-}"
  local subagent_dir
  subagent_dir=$(get_subagent_dir_path "$subagent_id" "$project_root")

  if [[ ! -d "$subagent_dir" ]]; then
    echo '{"error": "subagent_not_found"}'
    return 1
  fi

  local state_file="${subagent_dir}/${SUBAGENT_STATE_FILE}"
  local context_file="${subagent_dir}/${SUBAGENT_CONTEXT_FILE}"
  local state_json
  state_json=$(cat "$state_file")
  local artifacts_json
  artifacts_json=$(get_subagent_artifact_paths "$subagent_id" "$project_root")
  local prompt=""
  if [[ -f "$context_file" ]]; then
    prompt=$(cat "$context_file")
  fi

  jq -n \
    --argjson state "$state_json" \
    --argjson artifacts "$artifacts_json" \
    --arg prompt "$prompt" \
    '{
      contract_version: 1,
      subagent_id: $state.id,
      purpose: $state.purpose,
      status: $state.status,
      model: $state.model,
      model_short: $state.model_short,
      state_file: $artifacts.state_file,
      task_file: $artifacts.task_file,
      context_file: $artifacts.context_file,
      execution_request_file: $artifacts.execution_request_file,
      adapter_result_file: $artifacts.adapter_result_file,
      collected_result_file: $artifacts.collected_result_file,
      result_file: $artifacts.result_file,
      failure_file: $artifacts.failure_file,
      artifacts: $artifacts,
      failure_reason_format: {
        code: "short_machine_code",
        message: "human readable summary",
        details: {}
      },
      lifecycle: {
        spawn: "Create task/context/state artifacts and leave status=pending",
        prepare: "Write execution-request.json and set status=ready",
        start: "Set status=running and record started_at",
        collect: "Persist adapter-result.json and collected-result.json, then set status=collected",
        finalize: "Write result.md and optional failure.json, then set terminal status"
      },
      agent_params: {
        subagent_type: "general-purpose",
        description: $state.id,
        model: $state.model,
        prompt: $prompt
      }
    }'
}

subagent_request_prepare_execution() {
  local subagent_id="${1:-}"
  local project_root="${2:-}"
  local subagent_dir
  subagent_dir=$(get_subagent_dir_path "$subagent_id" "$project_root")

  if [[ ! -d "$subagent_dir" ]]; then
    echo '{"error": "subagent_not_found"}'
    return 1
  fi

  local state_file="${subagent_dir}/${SUBAGENT_STATE_FILE}"
  local current_status
  current_status=$(jq -r '.status // "pending"' "$state_file" 2> /dev/null)
  local next_status="$current_status"
  if [[ "$current_status" == "pending" || "$current_status" == "ready" ]]; then
    next_status="ready"
  fi

  local prepared_at
  prepared_at=$(subagent_now_utc)
  local contract_json
  contract_json=$(subagent_request_build_execution_contract "$subagent_id" "$project_root")
  contract_json=$(echo "$contract_json" | jq --arg status "$next_status" --arg ts "$prepared_at" \
    '.status = $status | .prepared_at = $ts')

  local request_file
  request_file=$(echo "$contract_json" | jq -r '.execution_request_file')
  echo "$contract_json" | jq '.' > "$request_file"

  if command -v jq > /dev/null 2>&1; then
    local tmp="${subagent_dir}/state.tmp"
    jq --arg status "$next_status" \
      --arg ts "$prepared_at" \
      --arg request_file "$request_file" \
      '
       .status = (if .status == "pending" or .status == "ready" then $status else .status end)
       | .lifecycle.prepared_at = $ts
       | .executor.request_file = $request_file
       ' "$state_file" > "$tmp" && mv "$tmp" "$state_file"
  fi

  echo "$contract_json"
}

subagent_request_start_execution() {
  local subagent_id="${1:-}"
  local project_root="${2:-}"
  local subagent_dir
  subagent_dir=$(get_subagent_dir_path "$subagent_id" "$project_root")

  if [[ ! -d "$subagent_dir" ]]; then
    return 1
  fi

  local state_file="${subagent_dir}/${SUBAGENT_STATE_FILE}"
  local request_file="${subagent_dir}/${SUBAGENT_EXECUTION_REQUEST_FILE}"
  if [[ ! -f "$request_file" ]]; then
    subagent_request_prepare_execution "$subagent_id" "$project_root" > /dev/null
  fi

  local current_status
  current_status=$(jq -r '.status // "pending"' "$state_file" 2> /dev/null)
  if is_terminal_subagent_status "$current_status"; then
    return 0
  fi

  local timestamp
  timestamp=$(subagent_now_utc)

  if command -v jq > /dev/null 2>&1; then
    local tmp="${subagent_dir}/state.tmp"
    jq --arg ts "$timestamp" '
      .status = "running"
      | .started_at = (.started_at // $ts)
      | .lifecycle.started_at = (.lifecycle.started_at // $ts)
    ' \
      "$state_file" > "$tmp" && mv "$tmp" "$state_file"
  fi
}

subagent_request_generate_agent_params() {
  local subagent_id="${1:-}"
  local project_root="${2:-}"
  local subagent_dir="${project_root}/${SUBAGENT_DIR}/${subagent_id}"

  if [[ ! -d "$subagent_dir" ]]; then
    echo '{"error": "subagent_not_found"}'
    return 1
  fi

  local request_file="${subagent_dir}/${SUBAGENT_EXECUTION_REQUEST_FILE}"
  if [[ -f "$request_file" ]]; then
    jq '.agent_params' "$request_file"
    return 0
  fi

  local state_file="${subagent_dir}/${SUBAGENT_STATE_FILE}"
  local model
  model=$(jq -r '.model // "claude-sonnet-4-6"' "$state_file" 2> /dev/null)

  local context_file="${subagent_dir}/${SUBAGENT_CONTEXT_FILE}"
  local prompt=""
  if [[ -f "$context_file" ]]; then
    prompt=$(cat "$context_file")
  fi

  jq -n \
    --arg prompt "$prompt" \
    --arg model "$model" \
    --arg subagent_id "$subagent_id" \
    '{
      subagent_type: "general-purpose",
      description: $subagent_id,
      model: $model,
      prompt: $prompt
    }'
}
