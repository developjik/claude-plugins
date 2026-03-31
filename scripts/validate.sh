#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MODE="${1:---quick}"

if [[ "$MODE" != "--quick" && "$MODE" != "--full" ]]; then
  echo "Usage: bash scripts/validate.sh [--quick|--full]"
  exit 1
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ERRORS=0
WARNINGS=0
FOUND_PLUGIN=0

validate_marketplace_json() {
  local marketplace_file=".claude-plugin/marketplace.json"

  echo "--- Marketplace ---"

  if [[ ! -f "$marketplace_file" ]]; then
    echo -e "${RED}[ERROR]${NC} Missing ${marketplace_file}"
    ERRORS=$((ERRORS + 1))
    return
  fi

  if ! command -v jq > /dev/null 2>&1; then
    echo -e "${YELLOW}[WARN]${NC} jq not found (marketplace JSON validation skipped)"
    WARNINGS=$((WARNINGS + 1))
    return
  fi

  if ! jq empty "$marketplace_file" > /dev/null 2>&1; then
    echo -e "${RED}[ERROR]${NC} marketplace.json is not valid JSON"
    ERRORS=$((ERRORS + 1))
    return
  fi

  echo -e "${GREEN}[OK]${NC} marketplace.json is valid JSON"

  if jq -e '.name | strings | length > 0' "$marketplace_file" > /dev/null 2>&1; then
    echo -e "${GREEN}[OK]${NC} Marketplace name present"
  else
    echo -e "${RED}[ERROR]${NC} Marketplace name missing"
    ERRORS=$((ERRORS + 1))
  fi

  if jq -e '.owner.name | strings | length > 0' "$marketplace_file" > /dev/null 2>&1; then
    echo -e "${GREEN}[OK]${NC} Marketplace owner present"
  else
    echo -e "${RED}[ERROR]${NC} Marketplace owner missing"
    ERRORS=$((ERRORS + 1))
  fi

  if jq -e '.plugins | arrays | length > 0' "$marketplace_file" > /dev/null 2>&1; then
    echo -e "${GREEN}[OK]${NC} Marketplace has plugin entries"
  else
    echo -e "${RED}[ERROR]${NC} Marketplace has no plugin entries"
    ERRORS=$((ERRORS + 1))
  fi
}

validate_root_scripts() {
  local script_file

  echo ""
  echo "--- Root Scripts ---"

  for script_file in scripts/*.sh; do
    [[ -f "$script_file" ]] || continue

    if bash -n "$script_file" 2> /dev/null; then
      echo -e "${GREEN}[OK]${NC} Syntax check passed: ${script_file}"
    else
      echo -e "${RED}[ERROR]${NC} Syntax error: ${script_file}"
      ERRORS=$((ERRORS + 1))
    fi
  done
}

validate_plugins() {
  local plugin_dir plugin_name plugin_validator

  echo ""
  echo "--- Plugins ---"

  for plugin_dir in plugins/*; do
    [[ -d "$plugin_dir" ]] || continue
    FOUND_PLUGIN=1
    plugin_name="$(basename "$plugin_dir")"
    plugin_validator="${plugin_dir}/scripts/validate.sh"

    if [[ ! -f "$plugin_validator" ]]; then
      echo -e "${YELLOW}[WARN]${NC} ${plugin_name}: missing scripts/validate.sh"
      WARNINGS=$((WARNINGS + 1))
      continue
    fi

    echo "Running validation for ${plugin_name}..."
    if bash "$plugin_validator" "$MODE"; then
      echo -e "${GREEN}[OK]${NC} ${plugin_name} validation passed"
    else
      echo -e "${RED}[ERROR]${NC} ${plugin_name} validation failed"
      ERRORS=$((ERRORS + 1))
    fi
  done

  if [[ "$FOUND_PLUGIN" -eq 0 ]]; then
    echo -e "${YELLOW}[WARN]${NC} No plugins found under plugins/"
    WARNINGS=$((WARNINGS + 1))
  fi
}

echo "========================================"
echo "Marketplace Validation"
echo "========================================"
echo "Mode: ${MODE#--}"
echo ""

validate_marketplace_json
validate_root_scripts
validate_plugins

echo ""
echo "========================================"
echo "Validation Summary"
echo "========================================"

if [[ "$ERRORS" -gt 0 ]]; then
  echo -e "${RED}FAILED${NC}: ${ERRORS} error(s), ${WARNINGS} warning(s)"
  exit 1
fi

if [[ "$WARNINGS" -gt 0 ]]; then
  echo -e "${YELLOW}PASSED WITH WARNINGS${NC}: ${WARNINGS} warning(s)"
  exit 0
fi

echo -e "${GREEN}ALL CHECKS PASSED${NC}"
