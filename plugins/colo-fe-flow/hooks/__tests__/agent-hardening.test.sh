#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local file_path="$1"
  local needle="$2"
  local message="$3"

  if ! grep -Fq "$needle" "$file_path"; then
    fail "$message ($file_path missing '$needle')"
  fi
}

for file in \
  "$ROOT_DIR/agents/intake-agent.md" \
  "$ROOT_DIR/agents/context-agent.md" \
  "$ROOT_DIR/agents/planning-agent.md" \
  "$ROOT_DIR/agents/implementation-agent.md" \
  "$ROOT_DIR/agents/check-agent.md"; do
  assert_contains "$file" "## 역할" "agent doc should define role"
  assert_contains "$file" "## 입력" "agent doc should define inputs"
  assert_contains "$file" "## 출력 계약" "agent doc should define output contract"
  assert_contains "$file" "## 호출되는 Skill" "agent doc should list calling skills"
  assert_contains "$file" "## 하지 않는 일" "agent doc should list forbidden scope"
  assert_contains "$file" "\"ticket_key\"" "agent doc should include structured output example"
done

assert_contains "$ROOT_DIR/skills/intake/SKILL.md" "Primary agent" "intake skill should name primary agent"
assert_contains "$ROOT_DIR/skills/clarify/SKILL.md" "Primary agent" "clarify skill should name primary agent"
assert_contains "$ROOT_DIR/skills/plan/SKILL.md" "Primary agent" "plan skill should name primary agent"
assert_contains "$ROOT_DIR/skills/design/SKILL.md" "Primary agent" "design skill should name primary agent"
assert_contains "$ROOT_DIR/skills/implement/SKILL.md" "Primary agent" "implement skill should name primary agent"
assert_contains "$ROOT_DIR/skills/check/SKILL.md" "Primary agent" "check skill should name primary agent"
assert_contains "$ROOT_DIR/skills/iterate/SKILL.md" "Primary agent" "iterate skill should name primary agent"
assert_contains "$ROOT_DIR/skills/sync-docs/SKILL.md" "Primary agent" "sync-docs skill should name primary agent"

echo "agent-hardening.test.sh passed"
