#!/bin/bash
set -euo pipefail

# 验证 project-builder 的所有脚本能正常工作。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [--dry-run] [--help]

Run self-tests for all project-builder scripts.

Options:
  --dry-run   Only test --help and --dry-run modes
  --help      Show this help message
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

SCRIPTS=(scan-project.sh env-check.sh env-setup.sh run-full-tests.sh verify-skill1.sh)
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== project-builder self-test ==="
echo ""

# Test 1: --help flag
echo "Test 1: --help flag"
for s in "${SCRIPTS[@]}"; do
    if bash "$SCRIPT_DIR/$s" --help > /dev/null 2>&1; then
        pass "$s --help"
    else
        fail "$s --help"
    fi
done
echo ""

# Test 2: --dry-run with a dummy project
echo "Test 2: --dry-run flag"
DUMMY=$(mktemp -d -t pb-selftest-XXXXXX)
mkdir -p "$DUMMY/src" "$DUMMY/tests" "$DUMMY/scripts"
echo "print('hello')" > "$DUMMY/src/main.py"
echo "def test_1(): pass" > "$DUMMY/tests/test_main.py"

bash "$SCRIPT_DIR/scan-project.sh" --project-root "$DUMMY" --dry-run > /dev/null 2>&1 && pass "scan --dry-run" || fail "scan --dry-run"
bash "$SCRIPT_DIR/env-check.sh" --project-root "$DUMMY" --dry-run > /dev/null 2>&1 && pass "env-check --dry-run" || fail "env-check --dry-run"
DUMMY_ENV_REPORT="$DUMMY/env-report.json"
echo '{"checks":[],"project_dependencies":[]}' > "$DUMMY_ENV_REPORT"
bash "$SCRIPT_DIR/env-setup.sh" --project-root "$DUMMY" --env-report "$DUMMY_ENV_REPORT" --dry-run > /dev/null 2>&1 && pass "env-setup --dry-run" || fail "env-setup --dry-run"
bash "$SCRIPT_DIR/run-full-tests.sh" --project-root "$DUMMY" --dry-run > /dev/null 2>&1 && pass "run-full-tests --dry-run" || fail "run-full-tests --dry-run"
DUMMY_BASELINE="$DUMMY/baseline.json"
echo '{"test_runs":[]}' > "$DUMMY_BASELINE"
bash "$SCRIPT_DIR/verify-skill1.sh" --skill1-path "$DUMMY" --baseline "$DUMMY_BASELINE" --dry-run > /dev/null 2>&1 && pass "verify --dry-run" || fail "verify --dry-run"

rm -rf "$DUMMY"
echo ""

if $DRY_RUN; then
    echo "=== Dry-run mode: skipping integration test ==="
    echo ""
    echo "Results: $PASS passed, $FAIL failed"
    [[ $FAIL -eq 0 ]] && exit 0 || exit 1
fi

# Test 3: scan-project produces valid JSON
echo "Test 3: scan-project integration"
TMPPROJ=$(mktemp -d -t pb-inttest-XXXXXX)
mkdir -p "$TMPPROJ/src" "$TMPPROJ/tests"
echo "def hello(): pass" > "$TMPPROJ/src/app.py"
echo "def test_hello(): pass" > "$TMPPROJ/tests/test_app.py"
echo "# README" > "$TMPPROJ/README.md"

MANIFEST=$(bash "$SCRIPT_DIR/scan-project.sh" --project-root "$TMPPROJ" 2>/dev/null)
FILE_COUNT=$(echo "$MANIFEST" | python3 -c "import json,sys; print(json.load(sys.stdin)['summary']['total_files'])")
[[ "$FILE_COUNT" == "3" ]] && pass "scan found 3 files" || fail "scan found $FILE_COUNT files (expected 3)"

# Test 4: env-check produces valid JSON
echo ""
echo "Test 4: env-check integration"
ENV_REPORT=$(bash "$SCRIPT_DIR/env-check.sh" --project-root "$TMPPROJ" 2>/dev/null)
HAS_CHECKS=$(echo "$ENV_REPORT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d['checks']) > 0)")
[[ "$HAS_CHECKS" == "True" ]] && pass "env-check has checks" || fail "env-check empty"

rm -rf "$TMPPROJ"
echo ""

echo "=== Results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
