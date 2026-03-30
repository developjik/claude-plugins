#!/usr/bin/env bash
# browser-session.sh — browser-controller session bridge helpers

set -euo pipefail

browser_run_node_script() {
  local project_root="${1:-$(pwd)}"
  local script_file="${2:-}"
  shift 2 || true

  (
    cd "$project_root" \
      && env "$@" node "$script_file" 2>&1
  )
}

browser_check_playwright() {
  local project_root="${1:-$(pwd)}"

  if ! command -v node > /dev/null 2>&1; then
    echo '{"success": false, "error": "node_not_installed"}'
    return 1
  fi

  if ! (cd "$project_root" && node -e "require('playwright')") > /dev/null 2>&1; then
    echo '{"success": false, "error": "playwright_not_installed"}'
    return 1
  fi
}

# browser_connect — headed Chrome 연결
# Usage: browser_connect [project_root] [options]
# Options: --url=<url> --browser=<browser>
browser_connect() {
  local project_root="${1:-$(pwd)}"
  shift || true

  local url=""
  local browser="chromium"

  for arg in "$@"; do
    case "$arg" in
      --url=*) url="${arg#*=}" ;;
      --browser=*) browser="${arg#*=}" ;;
    esac
  done

  local dependency_check
  if ! dependency_check=$(browser_check_playwright "$project_root"); then
    echo "$dependency_check"
    return 1
  fi

  _init_browser_state "$project_root"

  local state_dir script_file result
  state_dir=$(browser_state_dir "$project_root")
  script_file=$(browser_runtime_script_file "$project_root" "connect.js")

  cat > "$script_file" << 'SCRIPT'
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

async function connect() {
  const stateDir = process.env.HARNESS_BROWSER_STATE_DIR || '.harness/browser';
  const url = process.env.BROWSER_URL || 'about:blank';
  const browserType = process.env.BROWSER_TYPE || 'chromium';

  let browser, context, page;

  try {
    const { chromium } = require('playwright');

    browser = await chromium.launch({
      headless: false,
      args: [
        '--disable-blink-features=AutomationControlled',
        '--no-sandbox',
        '--disable-setuid-sandbox'
      ]
    });

    context = await browser.newContext({
      viewport: { width: 1280, height: 720 }
    });

    page = await context.newPage();

    if (url && url !== 'about:blank') {
      await page.goto(url, { waitUntil: 'networkidle', timeout: 60000 });
    }

    const session = {
      connected: true,
      mode: 'headed',
      browser: browserType,
      page: 'active',
      url: page.url(),
      last_action: 'connect',
      actions_count: 0,
      timestamp: new Date().toISOString()
    };

    fs.writeFileSync(
      path.join(stateDir, 'session.json'),
      JSON.stringify(session, null, 2)
    );

    const wsEndpoint = browser.wsEndpoint();
    fs.writeFileSync(
      path.join(stateDir, 'ws-endpoint.txt'),
      wsEndpoint
    );

    console.log(JSON.stringify({
      success: true,
      mode: 'headed',
      url: page.url(),
      wsEndpoint: wsEndpoint,
      message: 'Browser connected. Use browser_* functions to control.'
    }));
  } catch (error) {
    console.log(JSON.stringify({
      success: false,
      error: error.message
    }));
    process.exit(1);
  }
}

connect();
SCRIPT

  result=$(browser_run_node_script \
    "$project_root" \
    "$script_file" \
    "HARNESS_BROWSER_STATE_DIR=${state_dir}" \
    "BROWSER_URL=$url" \
    "BROWSER_TYPE=$browser")

  if echo "$result" | jq -e '.success' > /dev/null 2>&1; then
    _update_browser_state "$project_root" "connected" "true"
    _update_browser_state "$project_root" "mode" '"headed"'
    echo "$result"
    return 0
  fi

  if echo "$result" | jq -e . > /dev/null 2>&1; then
    echo "$result"
  elif [[ -n "$result" ]]; then
    jq -cn --arg err "$result" '{"success": false, "error": $err}'
  else
    echo '{"success": false, "error": "browser_connect_failed"}'
  fi
  return 1
}

# browser_disconnect — headless 모드로 복귀
# Usage: browser_disconnect [project_root]
browser_disconnect() {
  local project_root="${1:-$(pwd)}"
  local state_dir script_file result

  _init_browser_state "$project_root"

  state_dir=$(browser_state_dir "$project_root")
  script_file=$(browser_runtime_script_file "$project_root" "disconnect.js")

  cat > "$script_file" << 'SCRIPT'
const fs = require('fs');
const path = require('path');

async function disconnect() {
  const stateDir = process.env.HARNESS_BROWSER_STATE_DIR || '.harness/browser';
  const wsEndpointFile = path.join(stateDir, 'ws-endpoint.txt');

  if (!fs.existsSync(wsEndpointFile)) {
    console.log(JSON.stringify({ success: true, message: 'No active session' }));
    return;
  }

  try {
    const wsEndpoint = fs.readFileSync(wsEndpointFile, 'utf8').trim();
    const { chromium } = require('playwright');

    const browser = await chromium.connect({ wsEndpoint });
    await browser.close();

    fs.writeFileSync(
      path.join(stateDir, 'session.json'),
      JSON.stringify({
        connected: false,
        mode: 'headless',
        browser: null,
        page: null,
        url: null,
        last_action: 'disconnect',
        actions_count: 0
      }, null, 2)
    );

    fs.unlinkSync(wsEndpointFile);

    console.log(JSON.stringify({ success: true, message: 'Browser disconnected' }));
  } catch (error) {
    console.log(JSON.stringify({ success: false, error: error.message }));
  }
}

disconnect();
SCRIPT

  if ! command -v node > /dev/null 2>&1; then
    result='{"success": false, "error": "node_not_installed"}'
  else
    result=$(browser_run_node_script \
      "$project_root" \
      "$script_file" \
      "HARNESS_BROWSER_STATE_DIR=${state_dir}")
  fi

  _update_browser_state "$project_root" "connected" "false"
  _update_browser_state "$project_root" "mode" '"headless"'

  echo "$result"
}
