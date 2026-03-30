#!/usr/bin/env bash
# wave-plan-contract.test.sh — Bash/Python wave planner parity tests

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"
FIXTURE_DIR="${SCRIPT_DIR}/fixtures/wave-planner"

source "${LIB_DIR}/json-utils.sh"
source "${LIB_DIR}/logging.sh"
source "${LIB_DIR}/wave-executor.sh"

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

setup() {
	TESTS_RUN=$((TESTS_RUN + 1))
	ORIGINAL_WAVE_PLANNER="${HARNESS_WAVE_PLANNER-__unset__}"
	ORIGINAL_WAVE_PYTHON_BIN="${HARNESS_WAVE_PYTHON_BIN-__unset__}"
	ORIGINAL_WAVE_PLANNER_SCRIPT="${HARNESS_WAVE_PLANNER_SCRIPT-__unset__}"
}

teardown() {
	if [[ "$ORIGINAL_WAVE_PLANNER" == "__unset__" ]]; then
		unset HARNESS_WAVE_PLANNER
	else
		export HARNESS_WAVE_PLANNER="$ORIGINAL_WAVE_PLANNER"
	fi

	if [[ "$ORIGINAL_WAVE_PYTHON_BIN" == "__unset__" ]]; then
		unset HARNESS_WAVE_PYTHON_BIN
	else
		export HARNESS_WAVE_PYTHON_BIN="$ORIGINAL_WAVE_PYTHON_BIN"
	fi

	if [[ "$ORIGINAL_WAVE_PLANNER_SCRIPT" == "__unset__" ]]; then
		unset HARNESS_WAVE_PLANNER_SCRIPT
	else
		export HARNESS_WAVE_PLANNER_SCRIPT="$ORIGINAL_WAVE_PLANNER_SCRIPT"
	fi
}

pass() {
	local message="${1:-}"
	TESTS_PASSED=$((TESTS_PASSED + 1))
	echo -e "${GREEN}✓ $message${NC}"
}

fail() {
	local message="${1:-}"
	TESTS_FAILED=$((TESTS_FAILED + 1))
	echo -e "${RED}✗ $message${NC}"
}

normalize_json() {
	local payload="${1:-}"
	if [[ -z "$payload" ]]; then
		payload='{}'
	fi
	echo "$payload" | jq -cS '.'
}

fixture_path() {
	local fixture_name="${1:-}"
	echo "${FIXTURE_DIR}/${fixture_name}"
}

read_fixture() {
	local fixture_name="${1:-}"
	cat "$(fixture_path "$fixture_name")"
}

assert_json_equals() {
	local label="${1:-}"
	local expected="${2:-}"
	local actual="${3:-}"
	local normalized_expected normalized_actual

	if [[ -z "$expected" ]]; then
		expected='{}'
	fi

	if [[ -z "$actual" ]]; then
		actual='{}'
	fi

	normalized_expected="$(normalize_json "$expected")"
	normalized_actual="$(normalize_json "$actual")"

	if [[ "$normalized_expected" == "$normalized_actual" ]]; then
		pass "$label"
		return 0
	fi

	fail "$label"
	echo "  expected: $normalized_expected"
	echo "  actual:   $normalized_actual"
	return 1
}

run_parity_fixture_case() {
	local fixture_stem="${1:-}"
	local expected_status="${2:-0}"
	local label="${3:-$fixture_stem}"
	local tasks_json expected_json
	local bash_result python_result
	local bash_status=0 python_status=0
	local normalized_expected normalized_bash normalized_python

	tasks_json="$(read_fixture "${fixture_stem}.input.json")"
	expected_json="$(read_fixture "${fixture_stem}.expected.json")"

	if bash_result=$(resolve_task_dependency_layers_bash "$tasks_json" 2>/dev/null); then
		bash_status=0
	else
		bash_status=$?
	fi

	if python_result=$(resolve_task_dependency_layers_python "$tasks_json" 2>/dev/null); then
		python_status=0
	else
		python_status=$?
	fi

	if [[ "$bash_status" -ne "$expected_status" ]]; then
		fail "${label} (bash status)"
		echo "  expected status: $expected_status"
		echo "  actual status:   $bash_status"
		return 1
	fi

	if [[ "$python_status" -ne "$expected_status" ]]; then
		fail "${label} (python status)"
		echo "  expected status: $expected_status"
		echo "  actual status:   $python_status"
		return 1
	fi

	normalized_expected="$(normalize_json "$expected_json")"
	normalized_bash="$(normalize_json "$bash_result")"
	normalized_python="$(normalize_json "$python_result")"

	if [[ "$normalized_expected" == "$normalized_bash" && "$normalized_expected" == "$normalized_python" ]]; then
		pass "$label"
		return 0
	fi

	fail "$label"
	echo "  expected: $normalized_expected"
	echo "  bash:     $normalized_bash"
	echo "  python:   $normalized_python"
	return 1
}

run_python_cli_fixture_case() {
	local fixture_stem="${1:-}"
	local expected_status="${2:-0}"
	local label="${3:-$fixture_stem}"
	local payload expected_json actual_json
	local actual_status=0
	local python_bin planner_script

	payload="$(read_fixture "${fixture_stem}.input.json")"
	expected_json="$(read_fixture "${fixture_stem}.expected.json")"
	python_bin="$(wave_planner_python_bin)"
	planner_script="$(wave_planner_script_path)"

	if actual_json=$(printf '%s' "$payload" | "$python_bin" "$planner_script" 2>/dev/null); then
		actual_status=0
	else
		actual_status=$?
	fi

	if [[ "$actual_status" -ne "$expected_status" ]]; then
		fail "${label} (python cli status)"
		echo "  expected status: $expected_status"
		echo "  actual status:   $actual_status"
		return 1
	fi

	assert_json_equals "${label} (python cli)" "$expected_json" "$actual_json"
}

require_python_planner() {
	if can_use_python_wave_planner; then
		return 0
	fi

	pass "python planner unavailable; skipped"
	return 1
}

assert_command_fails_with_json() {
	local label="${1:-}"
	local expected_json="${2:-}"
	local actual_json
	local actual_status=0

	shift 2
	if actual_json=$("$@" 2>/dev/null); then
		fail "${label} (expected failure)"
		return 1
	else
		actual_status=$?
	fi

	if [[ "$actual_status" -eq 0 ]]; then
		fail "${label} (status)"
		return 1
	fi

	assert_json_equals "$label" "$expected_json" "$actual_json"
}

test_wave_planner_fixture_success_diamond() {
	setup
	if ! require_python_planner; then
		teardown
		return 0
	fi

	run_parity_fixture_case "success-diamond" 0 "test_wave_planner_fixture_success_diamond"
	teardown
}

test_wave_planner_fixture_success_multi_root() {
	setup
	if ! require_python_planner; then
		teardown
		return 0
	fi

	run_parity_fixture_case "success-multi-root" 0 "test_wave_planner_fixture_success_multi_root"
	teardown
}

test_wave_planner_fixture_invalid_missing_dependency() {
	setup
	if ! require_python_planner; then
		teardown
		return 0
	fi

	run_parity_fixture_case "invalid-missing-dependency" 1 "test_wave_planner_fixture_invalid_missing_dependency"
	teardown
}

test_wave_planner_fixture_invalid_duplicate_id() {
	setup
	if ! require_python_planner; then
		teardown
		return 0
	fi

	run_parity_fixture_case "invalid-duplicate-id" 1 "test_wave_planner_fixture_invalid_duplicate_id"
	teardown
}

test_wave_planner_fixture_cycle_simple() {
	setup
	if ! require_python_planner; then
		teardown
		return 0
	fi

	run_parity_fixture_case "cycle-simple" 1 "test_wave_planner_fixture_cycle_simple"
	teardown
}

test_wave_planner_feature_flag_python() {
	setup
	if ! require_python_planner; then
		teardown
		return 0
	fi

	export HARNESS_WAVE_PLANNER="python"
	local tasks_json python_result
	tasks_json="$(read_fixture "success-diamond.input.json")"

	local result
	result=$(resolve_task_dependency_layers "$tasks_json")
	python_result=$(resolve_task_dependency_layers_python "$tasks_json")

	assert_json_equals "test_wave_planner_feature_flag_python" "$python_result" "$result"

	teardown
}

test_wave_planner_default_auto_prefers_python() {
	setup
	if ! require_python_planner; then
		teardown
		return 0
	fi

	unset HARNESS_WAVE_PLANNER

	local tasks_json python_result
	tasks_json="$(read_fixture "success-diamond.input.json")"

	local result
	result=$(resolve_task_dependency_layers "$tasks_json")
	python_result=$(resolve_task_dependency_layers_python "$tasks_json")

	assert_json_equals "test_wave_planner_default_auto_prefers_python" "$python_result" "$result"

	teardown
}

test_wave_planner_auto_fallback_to_bash_when_python_unavailable() {
	setup

	export HARNESS_WAVE_PLANNER="auto"
	export HARNESS_WAVE_PYTHON_BIN="python-does-not-exist"

	local tasks_json bash_result
	tasks_json="$(read_fixture "success-diamond.input.json")"

	local result
	result=$(resolve_task_dependency_layers "$tasks_json" 2>/dev/null)
	bash_result=$(resolve_task_dependency_layers_bash "$tasks_json")

	assert_json_equals "test_wave_planner_auto_fallback_to_bash_when_python_unavailable" "$bash_result" "$result"

	teardown
}

test_wave_planner_python_mode_is_strict_when_python_unavailable() {
	setup

	export HARNESS_WAVE_PLANNER="python"
	export HARNESS_WAVE_PYTHON_BIN="python-does-not-exist"

	assert_command_fails_with_json \
		"test_wave_planner_python_mode_is_strict_when_python_unavailable" \
		'{"ok": false, "error": "python_planner_unavailable"}' \
		resolve_task_dependency_layers \
		"$(read_fixture "success-diamond.input.json")"

	teardown
}

test_wave_planner_auto_fallback_to_bash_on_runtime_failure() {
	setup
	if ! require_python_planner; then
		teardown
		return 0
	fi

	export HARNESS_WAVE_PLANNER="auto"

	local temp_dir tasks_json bash_result
	temp_dir="$(mktemp -d)"
	export HARNESS_WAVE_PLANNER_SCRIPT="${temp_dir}/wave_plan.py"
	printf '%s\n' 'def broken(:' >"$HARNESS_WAVE_PLANNER_SCRIPT"

	tasks_json="$(read_fixture "success-diamond.input.json")"
	local result
	result=$(resolve_task_dependency_layers "$tasks_json" 2>/dev/null)
	bash_result=$(resolve_task_dependency_layers_bash "$tasks_json")

	local assertion_failed=0
	if ! assert_json_equals "test_wave_planner_auto_fallback_to_bash_on_runtime_failure" "$bash_result" "$result"; then
		assertion_failed=1
	fi
	rm -rf "$temp_dir"

	teardown

	if [[ "$assertion_failed" -ne 0 ]]; then
		return 1
	fi
}

test_wave_planner_python_cli_wrapped_input() {
	setup
	if ! require_python_planner; then
		teardown
		return 0
	fi

	run_python_cli_fixture_case "wrapped-success" 0 "test_wave_planner_python_cli_wrapped_input"
	teardown
}

test_wave_planner_python_cli_invalid_input() {
	setup
	if ! require_python_planner; then
		teardown
		return 0
	fi

	run_python_cli_fixture_case "invalid-input" 1 "test_wave_planner_python_cli_invalid_input"
	teardown
}

main() {
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	echo "Wave Planner Contract Tests"
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	echo ""

	test_wave_planner_fixture_success_diamond
	test_wave_planner_fixture_success_multi_root
	test_wave_planner_fixture_invalid_missing_dependency
	test_wave_planner_fixture_invalid_duplicate_id
	test_wave_planner_fixture_cycle_simple
	test_wave_planner_feature_flag_python
	test_wave_planner_default_auto_prefers_python
	test_wave_planner_auto_fallback_to_bash_when_python_unavailable
	test_wave_planner_python_mode_is_strict_when_python_unavailable
	test_wave_planner_auto_fallback_to_bash_on_runtime_failure
	test_wave_planner_python_cli_wrapped_input
	test_wave_planner_python_cli_invalid_input

	echo ""
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	echo "Test Summary"
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	echo ""
	echo "  Total:   $TESTS_RUN"
	echo -e "  ${GREEN}Passed:  $TESTS_PASSED${NC}"
	echo -e "  ${RED}Failed:  $TESTS_FAILED${NC}"
	echo ""

	if [[ $TESTS_FAILED -eq 0 ]]; then
		echo -e "${GREEN}✅ All tests passed!${NC}"
		exit 0
	fi

	echo -e "${RED}❌ Some tests failed.${NC}"
	exit 1
}

main "$@"
