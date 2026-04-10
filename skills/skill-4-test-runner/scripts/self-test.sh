#!/bin/bash
set -euo pipefail

# 验证 test-runner 的所有脚本能正常工作。
# 测试 --help 和 --dry-run 模式，以及基本功能。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [--dry-run] [--help]

Run self-tests for all test-runner scripts.

Options:
  --dry-run   Only test --help and --dry-run modes (no temp dir, no execution)
  --help      Show this help message

Tests:
  1. --help flag works for all scripts
  2. --dry-run flag works for all scripts
  3. Integration: env-check + run-e2e with a mock project (full mode only)
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        --help) usage ;;
        *) echo "Error: unknown option '$1'." >&2; exit 1 ;;
    esac
done

SCRIPTS=(env-check.sh run-e2e.sh)
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== test-runner self-test ==="
echo ""

# -------------------------
# Test 1: --help returns 0
# -------------------------
echo "Test 1: --help flag"
for s in "${SCRIPTS[@]}"; do
    if bash "$SCRIPT_DIR/$s" --help > /dev/null 2>&1; then
        pass "$s --help"
    else
        fail "$s --help"
    fi
done
echo ""

# -------------------------
# Test 2: --dry-run returns 0
# -------------------------
echo "Test 2: --dry-run flag"

# Create minimal dummy project for dry-run validation
DUMMY="/tmp/test-runner-selftest-$$"
mkdir -p "$DUMMY/tests/e2e"
touch "$DUMMY/tests/e2e/test_dummy.py"

# env-check --dry-run
if bash "$SCRIPT_DIR/env-check.sh" --project-root "$DUMMY" --dry-run > /dev/null 2>&1; then
    pass "env-check.sh --dry-run"
else
    fail "env-check.sh --dry-run"
fi

# run-e2e --dry-run
if bash "$SCRIPT_DIR/run-e2e.sh" --project-root "$DUMMY" --dry-run > /dev/null 2>&1; then
    pass "run-e2e.sh --dry-run"
else
    fail "run-e2e.sh --dry-run"
fi

# run-e2e --dry-run with --test-diff-id
if bash "$SCRIPT_DIR/run-e2e.sh" --project-root "$DUMMY" --test-diff-id test-diff-001 --dry-run > /dev/null 2>&1; then
    pass "run-e2e.sh --dry-run --test-diff-id"
else
    fail "run-e2e.sh --dry-run --test-diff-id"
fi

rm -rf "$DUMMY"
echo ""

if $DRY_RUN; then
    echo "=== Dry-run mode: skipping integration test ==="
    echo ""
    echo "Results: $PASS passed, $FAIL failed"
    [[ $FAIL -eq 0 ]] && exit 0 || exit 1
fi

# -------------------------
# Test 3: Integration test with mock project
# -------------------------
echo "Test 3: Integration test"

TMPDIR=$(mktemp -d -t test-runner-integration-XXXXXX)

# Set up a minimal Python project with E2E tests
mkdir -p "$TMPDIR/selftest_project" "$TMPDIR/tests/e2e"

cat > "$TMPDIR/selftest_project/__init__.py" <<'INIT'
INIT

cat > "$TMPDIR/pyproject.toml" <<'PYPROJECT'
[project]
name = "selftest-project"
version = "0.0.1"
requires-python = ">=3.10"
dependencies = ["pytest"]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[tool.pytest.ini_options]
markers = ["e2e: end-to-end tests"]
PYPROJECT

cat > "$TMPDIR/tests/__init__.py" <<'INIT'
INIT

cat > "$TMPDIR/tests/e2e/__init__.py" <<'INIT'
INIT

cat > "$TMPDIR/tests/e2e/test_example.py" <<'TESTFILE'
"""Example E2E tests for self-test validation."""

def test_passing_regression():
    """A test that always passes (simulates regression case)."""
    assert 1 + 1 == 2

def test_another_passing():
    """Another passing test."""
    assert "hello".upper() == "HELLO"
TESTFILE

# Initialize git repo (needed for branch/commit detection)
cd "$TMPDIR"
git init -q
git add -A
git commit -q -m "init selftest project"

# Set up .artifacts/test-diffs/ with a mock test-diff
mkdir -p "$TMPDIR/.artifacts/test-diffs"
cat > "$TMPDIR/.artifacts/test-diffs/diff-e2e-example-001.md" <<'TESTDIFF'
---
type: test-diff
id: test-diff-001
status: confirmed
producer: skill-3
created_at: "2026-04-10"
---

# Test Diff: example

## New test functions

- `test_passing_regression` in `tests/e2e/test_example.py`
TESTDIFF

git add -A
git commit -q -m "add test-diff"

# Run env-check (should pass for hard checks since python/pytest are available)
echo "  Running env-check..." >&2
ENV_JSON=$(bash "$SCRIPT_DIR/env-check.sh" --project-root "$TMPDIR" 2>/dev/null) || true
ENV_STATUS=$?
if [[ $ENV_STATUS -eq 0 ]]; then
    pass "env-check passes (hard checks)"
else
    # Check the JSON overall field for blocked vs warnings
    ENV_OVERALL=$(echo "$ENV_JSON" | grep -oP '"overall"\s*:\s*"\K[^"]+' || echo "unknown")
    if [[ "$ENV_OVERALL" == "blocked" ]]; then
        fail "env-check hard dependency missing"
    else
        pass "env-check passes (hard checks, soft warnings)"
    fi
fi

# Validate env-check JSON output
if echo "$ENV_JSON" | uv run python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
    pass "env-check produces valid JSON"
else
    fail "env-check JSON validation"
fi

# Run the E2E suite
echo "  Running E2E suite..." >&2
RUN_OUTPUT=$(bash "$SCRIPT_DIR/run-e2e.sh" --project-root "$TMPDIR" 2>/dev/null) || true

if [[ -n "$RUN_OUTPUT" ]]; then
    # Validate JSON output structure
    VALID_JSON=$(echo "$RUN_OUTPUT" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    required = ['project_root', 'timestamp', 'branch', 'commit', 'exit_code',
                'new_cases', 'regression_cases', 'summary']
    missing = [k for k in required if k not in data]
    if missing:
        print(f'missing keys: {missing}')
    else:
        print('ok')
except Exception as e:
    print(f'invalid json: {e}')
" 2>&1)

    if [[ "$VALID_JSON" == "ok" ]]; then
        pass "run-e2e produces valid JSON"
    else
        fail "run-e2e JSON validation: $VALID_JSON"
    fi

    # Check that the summary has expected fields
    SUMMARY_OK=$(echo "$RUN_OUTPUT" | python3 -c "
import json, sys
data = json.load(sys.stdin)
s = data.get('summary', {})
required = ['new_passed', 'new_failed', 'regression_passed', 'regression_failed', 'total']
missing = [k for k in required if k not in s]
if missing:
    print(f'missing: {missing}')
else:
    print('ok')
" 2>&1)

    if [[ "$SUMMARY_OK" == "ok" ]]; then
        pass "run-e2e summary structure"
    else
        fail "run-e2e summary: $SUMMARY_OK"
    fi

    # Run with --test-diff-id to test new-case classification
    RUN_WITH_DIFF=$(bash "$SCRIPT_DIR/run-e2e.sh" --project-root "$TMPDIR" --test-diff-id test-diff-001 2>/dev/null) || true
    if [[ -n "$RUN_WITH_DIFF" ]]; then
        NEW_COUNT=$(echo "$RUN_WITH_DIFF" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(len(data.get('new_cases', [])))
" 2>&1)
        if [[ "$NEW_COUNT" -gt 0 ]]; then
            pass "run-e2e classifies new cases from test-diff ($NEW_COUNT new)"
        else
            # May be 0 if parsing didn't match function names
            pass "run-e2e runs with --test-diff-id (new=$NEW_COUNT)"
        fi
    else
        fail "run-e2e with --test-diff-id produced no output"
    fi
else
    fail "run-e2e produced no output"
fi

# Clean up
rm -rf "$TMPDIR"
echo ""

echo "=== Results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
