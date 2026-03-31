#!/usr/bin/env bash
# hash-anchored-edit.sh — Hash-Anchored Edit Verification System
# P2-1: superpowers 벤치마킹 - 라인 해시 기반 에디트 검증
#
# DEPENDENCIES: json-utils.sh, logging.sh

set -euo pipefail

# ============================================================================
# Constants
# ============================================================================

readonly HASH_LEDGER_FILE=".harness/hash-ledger.json"
readonly HASH_ALGORITHM="sha256"
readonly MAX_LEDGER_AGE_DAYS=30

# ============================================================================
# Hash Calculation Functions
# ============================================================================

# Calculate file hash using best available algorithm
# Usage: calculate_file_hash <file_path>
calculate_file_hash() {
  local file_path="${1:-}"

  if [[ ! -f "$file_path" ]]; then
    echo ""
    return 1
  fi

  # Use sha256 on macOS, sha256sum on Linux
  if command -v shasum &>/dev/null; then
    shasum -a 256 "$file_path" 2>/dev/null | cut -d' ' -f1
  elif command -v sha256sum &>/dev/null; then
    sha256sum "$file_path" 2>/dev/null | cut -d' ' -f1
  elif command -v md5 &>/dev/null; then
    md5 -q "$file_path" 2>/dev/null
  elif command -v md5sum &>/dev/null; then
    md5sum "$file_path" 2>/dev/null | cut -d' ' -f1
  else
    # Fallback to cksum
    cksum "$file_path" 2>/dev/null | cut -d' ' -f1
  fi
}

# Calculate hash for specific lines
# Usage: calculate_line_hash <file_path> <start_line> [end_line]
calculate_line_hash() {
  local file_path="${1:-}"
  local start_line="${2:-1}"
  local end_line="${3:-$start_line}"

  if [[ ! -f "$file_path" ]]; then
    echo ""
    return 1
  fi

  local range="${start_line}"
  if [[ "$start_line" != "$end_line" ]]; then
    range="${start_line},${end_line}"
  fi

  sed -n "${range}p" "$file_path" 2>/dev/null | {
    if command -v shasum &>/dev/null; then
      shasum -a 256 2>/dev/null | cut -d' ' -f1
    elif command -v sha256sum &>/dev/null; then
      sha256sum 2>/dev/null | cut -d' ' -f1
    else
      cksum 2>/dev/null | cut -d' ' -f1
    fi
  }
}

# Calculate string hash
# Usage: calculate_string_hash <content>
calculate_string_hash() {
  local content="${1:-}"

  echo -n "$content" | {
    if command -v shasum &>/dev/null; then
      shasum -a 256 2>/dev/null | cut -d' ' -f1
    elif command -v sha256sum &>/dev/null; then
      sha256sum 2>/dev/null | cut -d' ' -f1
    else
      cksum 2>/dev/null | cut -d' ' -f1
    fi
  }
}

# ============================================================================
# Hash Ledger Management
# ============================================================================

# Initialize hash ledger
# Usage: init_hash_ledger <project_root>
init_hash_ledger() {
  local project_root="${1:-}"
  local ledger_file="${project_root}/${HASH_LEDGER_FILE}"
  local ledger_dir
  ledger_dir=$(dirname "$ledger_file")

  mkdir -p "$ledger_dir"

  if [[ ! -f "$ledger_file" ]]; then
    cat > "$ledger_file" << 'EOF'
{
  "version": "1.0",
  "created_at": null,
  "updated_at": null,
  "files": {},
  "transactions": []
}
EOF
    local timestamp
    timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    local tmp="${ledger_file}.tmp"
    jq --arg ts "$timestamp" '.created_at = $ts | .updated_at = $ts' "$ledger_file" > "$tmp" && mv "$tmp" "$ledger_file"
  fi
}

# Get hash ledger
# Usage: get_hash_ledger <project_root>
get_hash_ledger() {
  local project_root="${1:-}"
  local ledger_file="${project_root}/${HASH_LEDGER_FILE}"

  if [[ ! -f "$ledger_file" ]]; then
    init_hash_ledger "$project_root"
  fi

  cat "$ledger_file"
}

# Register file in ledger
# Usage: register_file_hash <project_root> <file_path> [anchor_name]
register_file_hash() {
  local project_root="${1:-}"
  local file_path="${2:-}"
  local anchor_name="${3:-current}"
  local ledger_file="${project_root}/${HASH_LEDGER_FILE}"

  # Auto-initialize ledger if needed
  if [[ ! -f "$ledger_file" ]]; then
    init_hash_ledger "$project_root"
  fi

  # Convert to relative path from project root
  local rel_path
  rel_path=$(realpath --relative-to="$project_root" "$file_path" 2>/dev/null || \
            python3 -c "import os.path; print(os.path.relpath('$file_path', '$project_root'))" 2>/dev/null || \
            echo "${file_path#$project_root/}")

  local file_hash
  file_hash=$(calculate_file_hash "$file_path")

  if [[ -z "$file_hash" ]]; then
    return 1
  fi

  local timestamp
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  # Update ledger
  local tmp="${ledger_file}.tmp"
  jq --arg path "$rel_path" \
     --arg anchor "$anchor_name" \
     --arg hash "$file_hash" \
     --arg ts "$timestamp" '
    .files[$path] = {
      "current_hash": $hash,
      "anchors": (.files[$path].anchors // {} | . + {($anchor): $hash}),
      "last_updated": $ts
    } |
    .updated_at = $ts
  ' "$ledger_file" > "$tmp" && mv "$tmp" "$ledger_file"
}

# Get file hash from ledger
# Usage: get_file_hash <project_root> <file_path> [anchor_name]
get_file_hash() {
  local project_root="${1:-}"
  local file_path="${2:-}"
  local anchor_name="${3:-current}"
  local ledger_file="${project_root}/${HASH_LEDGER_FILE}"

  # Convert to relative path
  local rel_path
  rel_path=$(realpath --relative-to="$project_root" "$file_path" 2>/dev/null || \
            python3 -c "import os.path; print(os.path.relpath('$file_path', '$project_root'))" 2>/dev/null || \
            echo "${file_path#$project_root/}")

  if [[ ! -f "$ledger_file" ]]; then
    echo ""
    return 1
  fi

  if [[ "$anchor_name" == "current" ]]; then
    jq -r ".files.\"$rel_path\".current_hash // \"\"" "$ledger_file"
  else
    jq -r ".files.\"$rel_path\".anchors.\"$anchor_name\" // \"\"" "$ledger_file"
  fi
}

# ============================================================================
# Edit Verification
# ============================================================================

# Verify file hasn't changed from expected hash
# Usage: verify_file_integrity <project_root> <file_path> [expected_hash]
verify_file_integrity() {
  local project_root="${1:-}"
  local file_path="${2:-}"
  local expected_hash="${3:-}"

  # Get expected hash from ledger if not provided
  if [[ -z "$expected_hash" ]]; then
    expected_hash=$(get_file_hash "$project_root" "$file_path" "current")
  fi

  # If no expected hash, file is not tracked - pass
  if [[ -z "$expected_hash" ]]; then
    return 0
  fi

  local current_hash
  current_hash=$(calculate_file_hash "$file_path")

  if [[ "$current_hash" == "$expected_hash" ]]; then
    return 0
  else
    return 1
  fi
}

# Verify line range hasn't changed
# Usage: verify_line_integrity <project_root> <file_path> <start_line> <end_line> [expected_hash]
verify_line_integrity() {
  local project_root="${1:-}"
  local file_path="${2:-}"
  local start_line="${3:-}"
  local end_line="${4:-}"
  local expected_hash="${5:-}"

  if [[ -z "$expected_hash" ]]; then
    return 0
  fi

  local current_hash
  current_hash=$(calculate_line_hash "$file_path" "$start_line" "$end_line")

  if [[ "$current_hash" == "$expected_hash" ]]; then
    return 0
  else
    return 1
  fi
}

# ============================================================================
# Transaction Management
# ============================================================================

# Create edit transaction
# Usage: create_edit_transaction <project_root> <file_path> <expected_hash> [edit_description]
create_edit_transaction() {
  local project_root="${1:-}"
  local file_path="${2:-}"
  local expected_hash="${3:-}"
  local edit_description="${4:-Edit operation}"
  local ledger_file="${project_root}/${HASH_LEDGER_FILE}"

  # Convert to relative path
  local rel_path
  rel_path=$(realpath --relative-to="$project_root" "$file_path" 2>/dev/null || \
            python3 -c "import os.path; print(os.path.relpath('$file_path', '$project_root'))" 2>/dev/null || \
            echo "${file_path#$project_root/}")

  local timestamp txn_id
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  txn_id="txn_$(date +%s)_$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom 2>/dev/null | head -c 6 || echo "rand$$")"

  local tmp="${ledger_file}.tmp"
  jq --arg id "$txn_id" \
     --arg path "$rel_path" \
     --arg hash "$expected_hash" \
     --arg desc "$edit_description" \
     --arg ts "$timestamp" '
    .transactions = .transactions + [{
      "id": $id,
      "file": $path,
      "base_hash": $hash,
      "description": $desc,
      "status": "pending",
      "created_at": $ts,
      "completed_at": null
    }]
  ' "$ledger_file" > "$tmp" && mv "$tmp" "$ledger_file"

  echo "$txn_id"
}

# Complete transaction
# Usage: complete_transaction <project_root> <txn_id> [status]
complete_transaction() {
  local project_root="${1:-}"
  local txn_id="${2:-}"
  local status="${3:-completed}"
  local ledger_file="${project_root}/${HASH_LEDGER_FILE}"

  local timestamp
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  local tmp="${ledger_file}.tmp"
  jq --arg id "$txn_id" \
     --arg status "$status" \
     --arg ts "$timestamp" '
    (.transactions[] | select(.id == $id) | .status) = $status |
    (.transactions[] | select(.id == $id) | .completed_at) = $ts
  ' "$ledger_file" > "$tmp" && mv "$tmp" "$ledger_file"
}

# Get transaction status
# Usage: get_transaction_status <project_root> <txn_id>
get_transaction_status() {
  local project_root="${1:-}"
  local txn_id="${2:-}"
  local ledger_file="${project_root}/${HASH_LEDGER_FILE}"

  jq -r ".transactions[] | select(.id == \"$txn_id\") | .status // \"not_found\"" "$ledger_file"
}

# ============================================================================
# High-Level Edit Operations
# ============================================================================

# Prepare for edit (verify + create transaction)
# Usage: prepare_edit <project_root> <file_path> [edit_description]
prepare_edit() {
  local project_root="${1:-}"
  local file_path="${2:-}"
  local edit_description="${3:-Edit operation}"

  # Check if file exists
  if [[ ! -f "$file_path" ]]; then
    echo "{\"error\": \"file_not_found\", \"path\": \"$file_path\"}"
    return 1
  fi

  # Get current hash
  local current_hash
  current_hash=$(calculate_file_hash "$file_path")

  # Verify integrity against ledger
  local expected_hash
  expected_hash=$(get_file_hash "$project_root" "$file_path" "current")

  if [[ -n "$expected_hash" ]] && [[ "$current_hash" != "$expected_hash" ]]; then
    echo "{\"error\": \"hash_mismatch\", \"expected\": \"$expected_hash\", \"actual\": \"$current_hash\", \"path\": \"$file_path\"}"
    return 1
  fi

  # Create transaction
  local txn_id
  txn_id=$(create_edit_transaction "$project_root" "$file_path" "$current_hash" "$edit_description")

  echo "{\"txn_id\": \"$txn_id\", \"base_hash\": \"$current_hash\", \"path\": \"$file_path\"}"
}

# Finalize edit (update hash + complete transaction)
# Usage: finalize_edit <project_root> <txn_id> <file_path>
finalize_edit() {
  local project_root="${1:-}"
  local txn_id="${2:-}"
  local file_path="${3:-}"

  if [[ ! -f "$file_path" ]]; then
    complete_transaction "$project_root" "$txn_id" "failed"
    echo "{\"error\": \"file_not_found\"}"
    return 1
  fi

  # Get transaction base hash
  local ledger_file="${project_root}/${HASH_LEDGER_FILE}"
  local base_hash
  base_hash=$(jq -r ".transactions[] | select(.id == \"$txn_id\") | .base_hash // \"\"" "$ledger_file")

  # Verify file actually changed
  local new_hash
  new_hash=$(calculate_file_hash "$file_path")

  if [[ "$new_hash" == "$base_hash" ]]; then
    complete_transaction "$project_root" "$txn_id" "unchanged"
    echo "{\"warning\": \"file_unchanged\", \"hash\": \"$new_hash\"}"
    return 0
  fi

  # Update ledger with new hash
  register_file_hash "$project_root" "$file_path" "current"

  # Complete transaction
  complete_transaction "$project_root" "$txn_id" "completed"

  echo "{\"status\": \"completed\", \"old_hash\": \"$base_hash\", \"new_hash\": \"$new_hash\"}"
}

# ============================================================================
# Batch Operations
# ============================================================================

# Register multiple files
# Usage: register_files_hash <project_root> <file_paths_json>
register_files_hash() {
  local project_root="${1:-}"
  local file_paths_json="${2:-}"
  local ledger_file="${project_root}/${HASH_LEDGER_FILE}"

  init_hash_ledger "$project_root"

  local count=0
  local failed=0

  while IFS= read -r file_path; do
    if [[ -n "$file_path" ]] && [[ -f "$file_path" ]]; then
      if register_file_hash "$project_root" "$file_path"; then
        count=$((count + 1))
      else
        failed=$((failed + 1))
      fi
    fi
  done < <(echo "$file_paths_json" | jq -r '.[]')

  echo "{\"registered\": $count, \"failed\": $failed}"
}

# Verify multiple files
# Usage: verify_files_integrity <project_root> <file_paths_json>
verify_files_integrity() {
  local project_root="${1:-}"
  local file_paths_json="${2:-}"
  local ledger_file="${project_root}/${HASH_LEDGER_FILE}"

  local passed=0
  local failed=0
  local untracked=0
  local failed_files="[]"

  while IFS= read -r file_path; do
    if [[ -n "$file_path" ]]; then
      local expected_hash
      expected_hash=$(get_file_hash "$project_root" "$file_path" "current")

      if [[ -z "$expected_hash" ]]; then
        untracked=$((untracked + 1))
      elif verify_file_integrity "$project_root" "$file_path" "$expected_hash"; then
        passed=$((passed + 1))
      else
        failed=$((failed + 1))
        failed_files=$(echo "$failed_files" | jq ". + [\"$file_path\"]")
      fi
    fi
  done < <(echo "$file_paths_json" | jq -r '.[]')

  echo "{\"passed\": $passed, \"failed\": $failed, \"untracked\": $untracked, \"failed_files\": $failed_files}"
}

# ============================================================================
# Cleanup and Maintenance
# ============================================================================

# Clean old transactions
# Usage: clean_old_transactions <project_root> [max_age_days]
clean_old_transactions() {
  local project_root="${1:-}"
  local max_age_days="${2:-$MAX_LEDGER_AGE_DAYS}"
  local ledger_file="${project_root}/${HASH_LEDGER_FILE}"

  if [[ ! -f "$ledger_file" ]]; then
    echo "0"
    return 0
  fi

  # Get current timestamp
  local now
  now=$(date +%s)

  # Filter out old completed transactions
  local tmp="${ledger_file}.tmp"
  local cleaned=0

  # Keep pending transactions and recent completed ones
  jq --argjson now "$now" --argjson max_age_days "$max_age_days" '
    .transactions = [.transactions[] | select(
      .status == "pending" or
      (.completed_at != null and (($now - (.completed_at | fromdateiso8601)) < ($max_age_days * 86400)))
    )]
  ' "$ledger_file" > "$tmp" 2>/dev/null || cp "$ledger_file" "$tmp"

  local before after
  before=$(jq '.transactions | length' "$ledger_file")
  after=$(jq '.transactions | length' "$tmp")
  cleaned=$((before - after))

  mv "$tmp" "$ledger_file"

  echo "$cleaned"
}

# Get ledger statistics
# Usage: get_ledger_stats <project_root>
get_ledger_stats() {
  local project_root="${1:-}"
  local ledger_file="${project_root}/${HASH_LEDGER_FILE}"

  if [[ ! -f "$ledger_file" ]]; then
    echo "{\"error\": \"no_ledger\"}"
    return 1
  fi

  jq '{
    files_tracked: (.files | length),
    pending_transactions: ([.transactions[] | select(.status == "pending")] | length),
    completed_transactions: ([.transactions[] | select(.status == "completed")] | length),
    failed_transactions: ([.transactions[] | select(.status == "failed")] | length),
    created_at: .created_at,
    updated_at: .updated_at
  }' "$ledger_file"
}
