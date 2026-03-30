#!/usr/bin/env bash
# browser-test-report.sh — browser-testing report and history helpers

set -euo pipefail

browser_test_sorted_result_files() {
  local results_dir="${1:-}"

  find "$results_dir" -maxdepth 1 -type f -name 'browser_test_*.json' -print 2> /dev/null | while IFS= read -r file; do
    local file_ts
    file_ts=$(stat -f %m "$file" 2> /dev/null || stat -c %Y "$file" 2> /dev/null || echo 0)
    printf '%s\t%s\n' "$file_ts" "$file"
  done | sort -rn | cut -f2-
}

generate_html_report() {
  local project_root="${1:-}"
  local results_file="${2:-}"
  local results_dir
  results_dir=$(browser_test_results_dir "$project_root")

  mkdir -p "$results_dir"

  if [[ -z "$results_file" ]] || [[ ! -f "$results_file" ]]; then
    results_file=$(browser_test_sorted_result_files "$results_dir" | head -1)
  fi

  if [[ -z "$results_file" ]] || [[ ! -f "$results_file" ]]; then
    echo '{"error": "No results file found"}'
    return 1
  fi

  local report_file="${results_dir}/report.html"
  local timestamp
  timestamp=$(date -u '+%Y-%m-%d %H:%M:%S UTC')

  local results
  results=$(cat "$results_file")

  local success framework total passed failed skipped duration
  success=$(echo "$results" | jq -r '.success')
  framework=$(echo "$results" | jq -r '.framework')
  total=$(echo "$results" | jq -r '.summary.total // 0')
  passed=$(echo "$results" | jq -r '.summary.passed // 0')
  failed=$(echo "$results" | jq -r '.summary.failed // 0')
  skipped=$(echo "$results" | jq -r '.summary.skipped // 0')
  duration=$(echo "$results" | jq -r '.summary.duration_ms // 0')

  local status_color="#10b981"
  local status_text="PASSED"
  if [[ "$success" != "true" ]]; then
    status_color="#ef4444"
    status_text="FAILED"
  fi

  cat > "$report_file" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Browser Test Report</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; margin: 0; padding: 20px; background: #f3f4f6; }
    .container { max-width: 800px; margin: 0 auto; background: white; border-radius: 8px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); padding: 24px; }
    h1 { margin: 0 0 8px; font-size: 24px; }
    .timestamp { color: #6b7280; font-size: 14px; margin-bottom: 24px; }
    .status-badge { display: inline-block; padding: 4px 12px; border-radius: 9999px; color: white; font-weight: 600; font-size: 14px; }
    .metrics { display: grid; grid-template-columns: repeat(5, 1fr); gap: 16px; margin-top: 24px; }
    .metric { text-align: center; padding: 16px; background: #f9fafb; border-radius: 8px; }
    .metric-value { font-size: 32px; font-weight: 700; color: #1f2937; }
    .metric-label { font-size: 12px; color: #6b7280; text-transform: uppercase; margin-top: 4px; }
    .passed { color: #10b981; }
    .failed { color: #ef4444; }
    .skipped { color: #f59e0b; }
    .framework { margin-top: 24px; padding: 12px; background: #f3f4f6; border-radius: 6px; font-size: 14px; }
  </style>
</head>
<body>
  <div class="container">
    <h1>Browser Test Report</h1>
    <p class="timestamp">$timestamp</p>

    <span class="status-badge" style="background-color: $status_color;">$status_text</span>

    <div class="metrics">
      <div class="metric">
        <div class="metric-value">$total</div>
        <div class="metric-label">Total</div>
      </div>
      <div class="metric">
        <div class="metric-value passed">$passed</div>
        <div class="metric-label">Passed</div>
      </div>
      <div class="metric">
        <div class="metric-value failed">$failed</div>
        <div class="metric-label">Failed</div>
      </div>
      <div class="metric">
        <div class="metric-value skipped">$skipped</div>
        <div class="metric-label">Skipped</div>
      </div>
      <div class="metric">
        <div class="metric-value">${duration}ms</div>
        <div class="metric-label">Duration</div>
      </div>
    </div>

    <div class="framework">
      <strong>Framework:</strong> $framework
    </div>
  </div>
</body>
</html>
EOF

  echo "{\"report_file\": \"$report_file\", \"success\": $success}"
}

get_browser_test_history() {
  local project_root="${1:-}"
  local limit="${2:-10}"
  local results_dir
  results_dir=$(browser_test_results_dir "$project_root")

  if [[ ! -d "$results_dir" ]]; then
    echo '[]'
    return 0
  fi

  local history='[]'
  local count=0

  while IFS= read -r file; do
    if [[ $count -ge $limit ]]; then
      break
    fi

    local entry
    entry=$(jq -c '{
      timestamp: .timestamp,
      success: .success,
      framework: .framework,
      passed: .summary.passed,
      failed: .summary.failed,
      total: .summary.total
    }' "$file" 2> /dev/null)

    if [[ -n "$entry" ]]; then
      history=$(echo "$history" | jq ". + [$entry]")
      count=$((count + 1))
    fi
  done < <(browser_test_sorted_result_files "$results_dir")

  echo "$history"
}

cleanup_old_browser_results() {
  local project_root="${1:-}"
  local max_age_days="${2:-7}"
  local results_dir
  results_dir=$(browser_test_results_dir "$project_root")

  if [[ ! -d "$results_dir" ]]; then
    echo "0"
    return 0
  fi

  local cleaned=0
  local now
  now=$(date +%s)
  local max_age_seconds=$((max_age_days * 86400))

  for file in "$results_dir"/*.json "$results_dir"/*.html; do
    if [[ -f "$file" ]]; then
      local file_ts
      file_ts=$(stat -f %m "$file" 2> /dev/null || stat -c %Y "$file" 2> /dev/null || echo 0)

      if [[ $((now - file_ts)) -gt $max_age_seconds ]]; then
        rm -f "$file"
        cleaned=$((cleaned + 1))
      fi
    fi
  done

  echo "$cleaned"
}
