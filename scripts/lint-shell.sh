#!/usr/bin/env bash
# lint-shell.sh — shellcheck/shfmt wrapper for managed shell targets
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MODE="${1:---check}"

if [[ "$MODE" != "--check" && "$MODE" != "--write" ]]; then
  echo "Usage: bash scripts/lint-shell.sh [--check|--write]"
  exit 1
fi

SHELLCHECK_TARGETS=(
  "hooks/common.sh"
  "hooks/on-agent-start.sh"
  "hooks/on-agent-stop.sh"
  "hooks/post-tool.sh"
  "hooks/pre-tool.sh"
  "hooks/session-end.sh"
  "hooks/session-start.sh"
  "scripts/lint-shell.sh"
  "scripts/validate.sh"
  "hooks/lib/state-store.sh"
  "hooks/lib/phase-cache.sh"
  "hooks/lib/snapshot-store.sh"
  "hooks/lib/review-evidence.sh"
  "hooks/lib/review-engine.sh"
  "hooks/lib/skill-metrics.sh"
  "hooks/lib/skill-scoring.sh"
  "hooks/lib/skill-report.sh"
  "hooks/lib/skill-evaluation.sh"
  "hooks/lib/crash-detection.sh"
  "hooks/lib/crash-report.sh"
  "hooks/lib/crash-recovery.sh"
  "hooks/lib/subagent-request.sh"
  "hooks/lib/subagent-collect.sh"
  "hooks/lib/subagent-finalize.sh"
  "hooks/lib/subagent-spawner.sh"
  "hooks/lib/lsp-diagnostics.sh"
  "hooks/lib/lsp-symbols.sh"
  "hooks/lib/lsp-tools.sh"
  "hooks/lib/browser-state.sh"
  "hooks/lib/browser-session.sh"
  "hooks/lib/browser-actions.sh"
  "hooks/lib/browser-controller.sh"
  "hooks/lib/browser-test-runner.sh"
  "hooks/lib/browser-test-report.sh"
  "hooks/lib/browser-testing.sh"
  "hooks/lib/test-detection.sh"
  "hooks/lib/test-results.sh"
  "hooks/lib/test-runner.sh"
  "hooks/lib/wave-graph.sh"
  "hooks/lib/wave-runner.sh"
  "hooks/lib/wave-executor.sh"
)

SHFMT_TARGETS=(
  "${SHELLCHECK_TARGETS[@]}"
)

for tool in shellcheck shfmt; do
  if ! command -v "$tool" > /dev/null 2>&1; then
    echo "[ERROR] Missing required tool: $tool" >&2
    exit 127
  fi
done

shellcheck_disable_codes="SC1091,SC2016,SC2034"
shellcheck_args=(
  -x
  -e
  "$shellcheck_disable_codes"
)

shfmt_args=(
  -i
  2
  -ci
  -bn
  -sr
)

echo "==> ShellCheck (${#SHELLCHECK_TARGETS[@]} files)"
shellcheck "${shellcheck_args[@]}" "${SHELLCHECK_TARGETS[@]}"

echo ""
echo "==> shfmt (${#SHFMT_TARGETS[@]} files)"
if [[ "$MODE" == "--write" ]]; then
  shfmt "${shfmt_args[@]}" -w "${SHFMT_TARGETS[@]}"
else
  shfmt "${shfmt_args[@]}" -d "${SHFMT_TARGETS[@]}"
fi
