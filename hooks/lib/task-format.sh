#!/usr/bin/env bash
# task-format.sh — Hybrid Task Format Conversion Library
# DEPENDENCIES: json-utils.sh, logging.sh
#
# Supports both Markdown and XML task formats with bidirectional conversion.
# Reference: GSD XML Prompt Format

set -euo pipefail

# ============================================================================
# Constants
# ============================================================================

readonly TASK_SCHEMA="${CLAUDE_PLUGIN_ROOT:-.}/docs/schemas/task.xsd"
readonly TASK_XML_EXT=".xml"
readonly TASK_MD_EXT=".md"

# ============================================================================
# Format Detection
# ============================================================================

# detect_task_format <task_file>
# Returns: xml|md|unknown
detect_task_format() {
  local task_file="${1:-}"

  if [[ ! -f "$task_file" ]]; then
    echo "unknown"
    return 1
  fi

  local ext="${task_file##*.}"

  case "$ext" in
    xml)
      echo "xml"
      return 0
      ;;
    md)
      echo "md"
      return 0
      ;;
    *)
      # Try to detect by content
      if head -5 "$task_file" | grep -q '<task'; then
        echo "xml"
      elif head -5 "$task_file" | grep -q '^# Task'; then
        echo "md"
      else
        echo "unknown"
      fi
      return 0
      ;;
  esac
}

# ============================================================================
# XML Validation
# ============================================================================

# validate_task_xml <xml_file>
# Returns: 0 if valid, 1 if invalid
validate_task_xml() {
  local xml_file="${1:-}"

  if [[ ! -f "$xml_file" ]]; then
    echo '{"error": "file_not_found", "file": "'"$xml_file"'"}'
    return 1
  fi

  # Check for xmllint
  if ! command -v xmllint &>/dev/null; then
    # Basic well-formedness check without schema
    if grep -q '<task' "$xml_file" && grep -q '</task>' "$xml_file"; then
      echo '{"valid": true, "schema_validation": "skipped", "reason": "xmllint not available"}'
      return 0
    else
      echo '{"valid": false, "error": "malformed_xml"}'
      return 1
    fi
  fi

  # Full schema validation
  local schema_file="${TASK_SCHEMA}"
  if [[ ! -f "$schema_file" ]]; then
    schema_file="$(dirname "$xml_file")/../../../schemas/task.xsd"
  fi

  if [[ -f "$schema_file" ]]; then
    if xmllint --schema "$schema_file" "$xml_file" &>/dev/null; then
      echo '{"valid": true, "schema_validation": "passed"}'
      return 0
    else
      echo '{"valid": false, "error": "schema_validation_failed"}'
      return 1
    fi
  else
    # Well-formedness only
    if xmllint --noout "$xml_file" 2>/dev/null; then
      echo '{"valid": true, "schema_validation": "skipped", "reason": "schema_not_found"}'
      return 0
    else
      echo '{"valid": false, "error": "malformed_xml"}'
      return 1
    fi
  fi
}

# ============================================================================
# XML to Markdown Conversion
# ============================================================================

# xml_to_md <xml_file> [output_file]
# Converts XML task to Markdown format
xml_to_md() {
  local xml_file="${1:-}"
  local output_file="${2:-}"

  if [[ ! -f "$xml_file" ]]; then
    echo "ERROR: XML file not found: $xml_file" >&2
    return 1
  fi

  local content
  content=$(cat "$xml_file")

  # Extract attributes using grep (POSIX compatible)
  # Note: grep -o is POSIX compliant, -E for extended regex
  local task_id task_wave task_depends task_type task_priority
  task_id=$(echo "$content" | grep -oE 'id="[^"]*"' | head -1 | sed 's/id="//;s/"$//' || echo "")
  task_wave=$(echo "$content" | grep -oE 'wave="[^"]*"' | head -1 | sed 's/wave="//;s/"$//' || echo "1")
  task_depends=$(echo "$content" | grep -oE 'depends="[^"]*"' | head -1 | sed 's/depends="//;s/"$//' || echo "")
  task_type=$(echo "$content" | grep -oE 'type="[^"]*"' | head -1 | sed 's/type="//;s/"$//' || echo "implementation")
  task_priority=$(echo "$content" | grep -oE 'priority="[^"]*"' | head -1 | sed 's/priority="//;s/"$//' || echo "medium")

  # Extract elements (using sed for portability)
  local title description requirements action acceptance_criteria verify done notes

  title=$(extract_xml_element "$content" "title")
  description=$(extract_xml_element "$content" "description")
  requirements=$(extract_xml_element "$content" "requirements")
  action=$(extract_xml_element "$content" "action")
  acceptance_criteria=$(extract_xml_element "$content" "acceptance_criteria")
  verify=$(extract_xml_element "$content" "verify")
  done=$(extract_xml_element "$content" "done")
  notes=$(extract_xml_element "$content" "notes")

  # Extract files
  local files
  files=$(echo "$content" | sed -n 's/<file>\([^<]*\)<\/file>/\1/p' | tr '\n' '|' | sed 's/|$//')

  # Build Markdown output
  local md_content="# Task ${task_id}: ${title}

**Wave:** ${task_wave}
**Type:** ${task_type}
**Priority:** ${task_priority}
**Depends:** ${task_depends:-none}

---

## Description

${description:-_No description provided_}

## Files

"

  if [[ -n "$files" ]]; then
    IFS='|' read -ra file_array <<< "$files"
    for f in "${file_array[@]}"; do
      md_content+="- \`$f\`"$'\n'
    done
  else
    md_content+="_No files specified_"$'\n'
  fi

  md_content+="
---

## Requirements

${requirements:-_No requirements specified_}

---

## Action

\`\`\`
${action:-_No action specified_}
\`\`\`

---

## Acceptance Criteria

${acceptance_criteria:-_No acceptance criteria specified_}

---

## Verify

\`\`\`bash
${verify:-# Add verification commands}
\`\`\`

---

## Done

${done:-_Not yet completed_}

---

## Notes

${notes:-_No additional notes_}
"

  # Output
  if [[ -n "$output_file" ]]; then
    echo "$md_content" > "$output_file"
    echo "{\"converted\": true, \"output\": \"$output_file\"}"
  else
    echo "$md_content"
  fi

  return 0
}

# Helper: Extract XML element content
extract_xml_element() {
  local content="${1:-}"
  local element="${2:-}"

  echo "$content" | sed -n "s/.*<${element}>\(.*\)<\/${element}>.*/\1/p" | head -1
}

# ============================================================================
# Markdown to XML Conversion
# ============================================================================

# md_to_xml <md_file> [output_file]
# Converts Markdown task to XML format
md_to_xml() {
  local md_file="${1:-}"
  local output_file="${2:-}"

  if [[ ! -f "$md_file" ]]; then
    echo "ERROR: Markdown file not found: $md_file" >&2
    return 1
  fi

  local content
  content=$(cat "$md_file")

  # Extract metadata from Markdown
  local task_id title wave type priority depends

  # Parse title line: "# Task 001: Title"
  title=$(echo "$content" | grep -m1 '^# Task' | sed 's/^# Task [0-9]*: //')
  task_id=$(echo "$content" | grep -m1 '^# Task' | sed 's/^# Task \([0-9]*\):.*/\1/')

  # Parse metadata
  wave=$(echo "$content" | grep '^\*\*Wave:\*\*' | sed 's/\*\*Wave:\*\* //' || echo "1")
  type=$(echo "$content" | grep '^\*\*Type:\*\*' | sed 's/\*\*Type:\*\* //' || echo "implementation")
  priority=$(echo "$content" | grep '^\*\*Priority:\*\*' | sed 's/\*\*Priority:\*\* //' || echo "medium")
  depends=$(echo "$content" | grep '^\*\*Depends:\*\*' | sed 's/\*\*Depends:\*\* //' | tr -d 'none')

  # Extract sections
  local description requirements action acceptance_criteria verify done notes

  description=$(extract_md_section "$content" "Description")
  requirements=$(extract_md_section "$content" "Requirements")
  action=$(extract_md_section "$content" "Action" | sed 's/```\|```//g' | sed 's/^$//')
  acceptance_criteria=$(extract_md_section "$content" "Acceptance Criteria")
  verify=$(extract_md_section "$content" "Verify" | sed 's/```bash\|```//g')
  done=$(extract_md_section "$content" "Done")
  notes=$(extract_md_section "$content" "Notes")

  # Extract files
  local files_section
  files_section=$(echo "$content" | sed -n '/^## Files$/,/^## /p' | sed -n 's/`\([^`]*\)`/\1/p' | tr '\n' '|')

  # Build XML output
  local xml_content='<?xml version="1.0" encoding="UTF-8"?>
<task id="'"${task_id:-000}"'" wave="'"${wave:-1}"'" type="'"${type:-implementation}"'" priority="'"${priority:-medium}"'"'

  if [[ -n "$depends" ]]; then
    xml_content+=" depends=\"${depends}\""
  fi

  xml_content+=">
  <title>${title:-Untitled Task}</title>
"

  if [[ -n "$description" ]]; then
    xml_content+="  <description>${description}</description>
"
  fi

  if [[ -n "$files_section" ]]; then
    xml_content+="  <files>
"
    IFS='|' read -ra file_array <<< "$files_section"
    for f in "${file_array[@]}"; do
      if [[ -n "$f" ]]; then
        xml_content+="    <file>${f}</file>
"
      fi
    done
    xml_content+="  </files>
"
  fi

  if [[ -n "$requirements" ]]; then
    xml_content+="  <requirements>
${requirements}
  </requirements>
"
  fi

  if [[ -n "$action" ]]; then
    xml_content+="  <action>
${action}
  </action>
"
  fi

  if [[ -n "$acceptance_criteria" ]]; then
    xml_content+="  <acceptance_criteria>
${acceptance_criteria}
  </acceptance_criteria>
"
  fi

  if [[ -n "$verify" ]]; then
    xml_content+="  <verify>
${verify}
  </verify>
"
  fi

  if [[ -n "$done" ]]; then
    xml_content+="  <done>${done}</done>
"
  fi

  if [[ -n "$notes" ]]; then
    xml_content+="  <notes>${notes}</notes>
"
  fi

  xml_content+="</task>
"

  # Output
  if [[ -n "$output_file" ]]; then
    echo "$xml_content" > "$output_file"
    echo "{\"converted\": true, \"output\": \"$output_file\"}"
  else
    echo "$xml_content"
  fi

  return 0
}

# Helper: Extract Markdown section content
# Note: Using POSIX-compatible patterns for BSD/GNU sed compatibility
extract_md_section() {
  local content="${1:-}"
  local section="${2:-}"

  # Extract content between ## Section and next ## or end
  # Using awk for reliable cross-platform section extraction
  echo "$content" | awk -v sec="$section" '
    BEGIN { found=0 }
    $0 ~ "^## " sec "$" { found=1; next }
    found && /^## / { exit }
    found && /^---$/ { next }
    found && /^\*_/ { next }
    found && /^_No/ { next }
    found { print }
  '
}

# ============================================================================
# Batch Conversion
# ============================================================================

# convert_all_tasks <tasks_dir> <to_format>
# to_format: xml|md
convert_all_tasks() {
  local tasks_dir="${1:-}"
  local to_format="${2:-xml}"

  if [[ ! -d "$tasks_dir" ]]; then
    echo "{\"error\": \"directory_not_found\", \"path\": \"$tasks_dir\"}"
    return 1
  fi

  local converted=0
  local failed=0
  local results="[]"

  local task_file
  for task_file in "$tasks_dir"/*.md "$tasks_dir"/*.xml; do
    [[ -f "$task_file" ]] || continue

    local format
    format=$(detect_task_format "$task_file")

    local basename="${task_file%.*}"
    local output_file

    case "$to_format" in
      xml)
        if [[ "$format" == "md" ]]; then
          output_file="${basename}.xml"
          if md_to_xml "$task_file" "$output_file" &>/dev/null; then
            ((converted++))
            results=$(echo "$results" | jq --arg f "$task_file" --arg o "$output_file" \
              '. += [{"from": $f, "to": $o, "status": "success"}]')
          else
            ((failed++))
            results=$(echo "$results" | jq --arg f "$task_file" \
              '. += [{"from": $f, "status": "failed"}]')
          fi
        fi
        ;;
      md)
        if [[ "$format" == "xml" ]]; then
          output_file="${basename}.md"
          if xml_to_md "$task_file" "$output_file" &>/dev/null; then
            ((converted++))
            results=$(echo "$results" | jq --arg f "$task_file" --arg o "$output_file" \
              '. += [{"from": $f, "to": $o, "status": "success"}]')
          else
            ((failed++))
            results=$(echo "$results" | jq --arg f "$task_file" \
              '. += [{"from": $f, "status": "failed"}]')
          fi
        fi
        ;;
    esac
  done

  echo "{\"converted\": $converted, \"failed\": $failed, \"results\": $results}"
}

# ============================================================================
# Unified Task Parser (handles both formats)
# ============================================================================

# parse_task <task_file>
# Returns JSON with normalized task data
parse_task() {
  local task_file="${1:-}"

  if [[ ! -f "$task_file" ]]; then
    echo '{"error": "file_not_found"}'
    return 1
  fi

  local format
  format=$(detect_task_format "$task_file")

  case "$format" in
    xml)
      parse_xml_task "$task_file"
      ;;
    md)
      parse_md_task "$task_file"
      ;;
    *)
      echo '{"error": "unknown_format"}'
      return 1
      ;;
  esac
}

# Parse XML task to JSON
parse_xml_task() {
  local xml_file="${1:-}"
  local content
  content=$(cat "$xml_file")

  local id wave depends type priority title description requirements action acceptance_criteria verify done notes

  # Extract attributes using grep (POSIX compatible)
  id=$(echo "$content" | grep -oE 'id="[^"]*"' | head -1 | sed 's/id="//;s/"$//')
  wave=$(echo "$content" | grep -oE 'wave="[^"]*"' | head -1 | sed 's/wave="//;s/"$//')
  depends=$(echo "$content" | grep -oE 'depends="[^"]*"' | head -1 | sed 's/depends="//;s/"$//')
  type=$(echo "$content" | grep -oE 'type="[^"]*"' | head -1 | sed 's/type="//;s/"$//')
  priority=$(echo "$content" | grep -oE 'priority="[^"]*"' | head -1 | sed 's/priority="//;s/"$//')
  title=$(extract_xml_element "$content" "title")
  description=$(extract_xml_element "$content" "description")
  requirements=$(extract_xml_element "$content" "requirements")
  action=$(extract_xml_element "$content" "action")
  acceptance_criteria=$(extract_xml_element "$content" "acceptance_criteria")
  verify=$(extract_xml_element "$content" "verify")
  done=$(extract_xml_element "$content" "done")
  notes=$(extract_xml_element "$content" "notes")

  # Extract files as JSON array
  local files_json="[]"
  while IFS= read -r file; do
    [[ -n "$file" ]] && files_json=$(echo "$files_json" | jq --arg f "$file" '. += [$f]')
  done < <(echo "$content" | grep -oE '<file>[^<]+</file>' | sed 's/<file>//;s/<\/file>//')

  # Ensure wave is a valid number for --argjson
  wave="${wave:-1}"
  [[ ! "$wave" =~ ^[0-9]+$ ]] && wave=1

  jq -n \
    --arg id "${id:-}" \
    --argjson wave "$wave" \
    --arg depends "${depends:-}" \
    --arg type "${type:-implementation}" \
    --arg priority "${priority:-medium}" \
    --arg title "${title:-}" \
    --arg description "${description:-}" \
    --arg requirements "${requirements:-}" \
    --arg action "${action:-}" \
    --arg acceptance_criteria "${acceptance_criteria:-}" \
    --arg verify "${verify:-}" \
    --arg done "${done:-}" \
    --arg notes "${notes:-}" \
    --argjson files "$files_json" \
    --arg format "xml" \
    --arg file "$xml_file" \
    '{
      id: $id,
      wave: $wave,
      depends: $depends,
      type: $type,
      priority: $priority,
      title: $title,
      description: $description,
      requirements: $requirements,
      action: $action,
      acceptance_criteria: $acceptance_criteria,
      verify: $verify,
      done: $done,
      notes: $notes,
      files: $files,
      format: $format,
      file: $file
    }'
}

# Parse Markdown task to JSON
parse_md_task() {
  local md_file="${1:-}"
  local content
  content=$(cat "$md_file")

  local id title wave type priority depends

  title=$(echo "$content" | grep -m1 '^# Task' | sed 's/^# Task [0-9]*: //')
  id=$(echo "$content" | grep -m1 '^# Task' | sed 's/^# Task \([0-9]*\):.*/\1/')
  wave=$(echo "$content" | grep '^\*\*Wave:\*\*' | sed 's/\*\*Wave:\*\* //' | tr -d ' ')
  type=$(echo "$content" | grep '^\*\*Type:\*\*' | sed 's/\*\*Type:\*\* //')
  priority=$(echo "$content" | grep '^\*\*Priority:\*\*' | sed 's/\*\*Priority:\*\* //')
  depends=$(echo "$content" | grep '^\*\*Depends:\*\*' | sed 's/\*\*Depends:\*\* //' | tr -d 'none')

  local description requirements action acceptance_criteria verify done notes

  description=$(extract_md_section "$content" "Description")
  requirements=$(extract_md_section "$content" "Requirements")
  action=$(extract_md_section "$content" "Action" | sed 's/```\|```//g')
  acceptance_criteria=$(extract_md_section "$content" "Acceptance Criteria")
  verify=$(extract_md_section "$content" "Verify" | sed 's/```bash\|```//g')
  done=$(extract_md_section "$content" "Done")
  notes=$(extract_md_section "$content" "Notes")

  # Extract files as JSON array
  local files_json="[]"
  while IFS= read -r file; do
    [[ -n "$file" ]] && files_json=$(echo "$files_json" | jq --arg f "$file" '. += [$f]')
  done < <(echo "$content" | sed -n '/^## Files$/,/^## /p' | sed -n 's/`\([^`]*\)`/\1/p')

  jq -n \
    --arg id "${id:-}" \
    --argjson wave "${wave:-1}" \
    --arg depends "${depends:-}" \
    --arg type "${type:-implementation}" \
    --arg priority "${priority:-medium}" \
    --arg title "${title:-}" \
    --arg description "${description:-}" \
    --arg requirements "${requirements:-}" \
    --arg action "${action:-}" \
    --arg acceptance_criteria "${acceptance_criteria:-}" \
    --arg verify "${verify:-}" \
    --arg done "${done:-}" \
    --arg notes "${notes:-}" \
    --argjson files "$files_json" \
    --arg format "md" \
    --arg file "$md_file" \
    '{
      id: $id,
      wave: $wave,
      depends: $depends,
      type: $type,
      priority: $priority,
      title: $title,
      description: $description,
      requirements: $requirements,
      action: $action,
      acceptance_criteria: $acceptance_criteria,
      verify: $verify,
      done: $done,
      notes: $notes,
      files: $files,
      format: $format,
      file: $file
    }'
}
