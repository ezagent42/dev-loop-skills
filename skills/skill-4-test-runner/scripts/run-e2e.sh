#!/bin/bash
set -euo pipefail

# 统一 E2E 测试入口。
# 执行项目完整 E2E 测试套件，识别新增 vs 回归 case，输出 JSON 格式结果。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=false
PROJECT_ROOT=""
TEST_DIFF_ID=""
TEST_DIR=""
TEST_CMD=""

usage() {
    cat <<EOF
Usage: $(basename "$0") --project-root <path> [--test-diff-id <id>] \\
       [--test-dir <dir>] [--test-cmd <cmd>] [--dry-run] [--help]

Run the full E2E test suite and output structured JSON results.

Required:
  --project-root <path>    Project root directory

Optional:
  --test-diff-id <id>      test-diff artifact ID to identify new cases
                           (e.g. test-diff-001). If omitted, all cases
                           are treated as regression.
  --test-dir <dir>         Override E2E test directory (default: auto-detect)
  --test-cmd <cmd>         Override test command (default: uv run pytest)
  --dry-run                Show what would be executed without running tests
  --help                   Show this help message

Output: JSON object to stdout with structure:
  {
    "project_root": "/path",
    "test_diff_id": "test-diff-001" | null,
    "timestamp": "2026-04-10T14:30:22Z",
    "branch": "main",
    "commit": "abc1234",
    "duration_seconds": 42,
    "exit_code": 0,
    "new_cases": [ ... ],
    "regression_cases": [ ... ],
    "summary": { "new_passed": 0, "new_failed": 0, ... },
    "raw_output_path": "/path/to/raw-output.txt"
  }
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project-root) PROJECT_ROOT="$2"; shift 2 ;;
        --test-diff-id) TEST_DIFF_ID="$2"; shift 2 ;;
        --test-dir) TEST_DIR="$2"; shift 2 ;;
        --test-cmd) TEST_CMD="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        --help) usage ;;
        *) echo "Error: unknown option '$1'. Use --help for usage." >&2; exit 1 ;;
    esac
done

if [[ -z "$PROJECT_ROOT" ]]; then
    echo "Error: --project-root is required. Use --help for usage." >&2
    exit 1
fi

if [[ ! -d "$PROJECT_ROOT" ]]; then
    echo "Error: project root '$PROJECT_ROOT' does not exist." >&2
    exit 1
fi

# --- Auto-detect test directory ---
if [[ -z "$TEST_DIR" ]]; then
    # Common E2E test locations, ordered by preference
    for candidate in "tests/e2e" "test/e2e" "tests/e2e_tests" "e2e"; do
        if [[ -d "$PROJECT_ROOT/$candidate" ]]; then
            TEST_DIR="$candidate"
            break
        fi
    done
    if [[ -z "$TEST_DIR" ]]; then
        echo "Error: could not auto-detect E2E test directory. Use --test-dir." >&2
        exit 1
    fi
fi

if [[ ! -d "$PROJECT_ROOT/$TEST_DIR" ]]; then
    echo "Error: test directory '$PROJECT_ROOT/$TEST_DIR' does not exist." >&2
    exit 1
fi

# --- Auto-detect test command ---
if [[ -z "$TEST_CMD" ]]; then
    if command -v uv &>/dev/null && [[ -f "$PROJECT_ROOT/pyproject.toml" ]]; then
        TEST_CMD="uv run pytest"
    elif command -v pytest &>/dev/null; then
        TEST_CMD="pytest"
    elif $DRY_RUN; then
        TEST_CMD="(not detected)"
    else
        echo "Error: could not find pytest or uv. Use --test-cmd." >&2
        exit 1
    fi
fi

# --- Parse new case names from test-diff ---
NEW_CASE_NAMES=()
if [[ -n "$TEST_DIFF_ID" ]]; then
    DIFF_DIR="$PROJECT_ROOT/.artifacts/test-diffs"
    # Find the test-diff file: search for files containing the test-diff ID
    DIFF_FILE=""
    if [[ -d "$DIFF_DIR" ]]; then
        # Look for markdown files in test-diffs/
        while IFS= read -r -d '' f; do
            if grep -q "id: *${TEST_DIFF_ID}" "$f" 2>/dev/null; then
                DIFF_FILE="$f"
                break
            fi
        done < <(find "$DIFF_DIR" -name "*.md" -print0 2>/dev/null)
    fi

    if [[ -n "$DIFF_FILE" ]]; then
        # Extract test function names from the test-diff.
        # Strategy: prefer backtick-quoted names (`test_xxx`), fall back to
        # "- test_xxx" list items. This avoids capturing file-path fragments
        # like test_example from tests/e2e/test_example.py.
        while IFS= read -r name; do
            if [[ -n "$name" ]]; then
                NEW_CASE_NAMES+=("$name")
            fi
        done < <(grep -oP '`(test_[a-zA-Z0-9_]+)`' "$DIFF_FILE" 2>/dev/null \
                 | sed 's/`//g' | sort -u)

        # Fallback: if no backtick-quoted names, try "- test_xxx" list items
        if [[ ${#NEW_CASE_NAMES[@]} -eq 0 ]]; then
            while IFS= read -r name; do
                if [[ -n "$name" ]]; then
                    NEW_CASE_NAMES+=("$name")
                fi
            done < <(grep -oP '^\s*-\s+test_[a-zA-Z0-9_]+' "$DIFF_FILE" 2>/dev/null \
                     | grep -oP 'test_[a-zA-Z0-9_]+' | sort -u)
        fi
        echo "Identified ${#NEW_CASE_NAMES[@]} new case(s) from $TEST_DIFF_ID" >&2
    else
        echo "Warning: test-diff '$TEST_DIFF_ID' not found in $DIFF_DIR. All cases treated as regression." >&2
    fi
fi

# --- Git info ---
BRANCH=$(cd "$PROJECT_ROOT" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
COMMIT=$(cd "$PROJECT_ROOT" && git rev-parse --short HEAD 2>/dev/null || echo "unknown")
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# --- Dry run ---
if $DRY_RUN; then
    echo "[dry-run] Would execute in $PROJECT_ROOT:"
    echo "  Command: $TEST_CMD $TEST_DIR -v --tb=long -q"
    echo "  Branch: $BRANCH"
    echo "  Commit: $COMMIT"
    echo "  Test diff: ${TEST_DIFF_ID:-none}"
    echo "  New cases: ${NEW_CASE_NAMES[*]:-none}"
    exit 0
fi

# --- Prepare output paths ---
RUN_ID="e2e-run-$(date +%Y%m%d-%H%M%S)"
EVIDENCE_DIR="$PROJECT_ROOT/$TEST_DIR/evidence"
mkdir -p "$EVIDENCE_DIR"
RAW_OUTPUT="$EVIDENCE_DIR/${RUN_ID}-raw-output.txt"

# --- Execute tests ---
echo "Running E2E suite: $TEST_CMD $TEST_DIR -v --tb=long" >&2
echo "Output: $RAW_OUTPUT" >&2

START_TIME=$(date +%s)
TEST_EXIT_CODE=0

cd "$PROJECT_ROOT"
$TEST_CMD "$TEST_DIR" -v --tb=long 2>&1 | tee "$RAW_OUTPUT" >&2 || TEST_EXIT_CODE=$?

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo "Tests completed in ${DURATION}s with exit code $TEST_EXIT_CODE" >&2

# --- Parse pytest output into structured results ---
# Use Python to parse the verbose pytest output
python3 -c "
import json
import re
import sys

raw_output_path = '$RAW_OUTPUT'
new_case_names = set('''${NEW_CASE_NAMES[*]:-}'''.split()) - {''}
test_diff_id = '${TEST_DIFF_ID}' or None

with open(raw_output_path) as f:
    raw = f.read()

# Parse pytest verbose output lines like:
# tests/e2e/test_e2e.py::test_something PASSED
# tests/e2e/test_e2e.py::test_other FAILED
test_pattern = re.compile(
    r'^([\w/\.\-]+)::(\w+)\s+(PASSED|FAILED|ERROR|SKIPPED)',
    re.MULTILINE
)

results = []
for match in test_pattern.finditer(raw):
    filepath, funcname, status = match.groups()
    is_new = funcname in new_case_names

    # Extract failure detail if failed
    failure_detail = ''
    if status in ('FAILED', 'ERROR'):
        # Look for the FAILURES section
        fail_pattern = re.compile(
            rf'_{2,}\s+{re.escape(funcname)}\s+_{2,}\n(.*?)(?=\n_{2,}|\n={2,}|\Z)',
            re.DOTALL
        )
        fail_match = fail_pattern.search(raw)
        if fail_match:
            failure_detail = fail_match.group(1).strip()[:2000]  # Cap at 2000 chars

    results.append({
        'name': funcname,
        'file': filepath,
        'status': status.lower(),
        'category': 'new' if is_new else 'regression',
        'failure_detail': failure_detail,
        'evidence': []
    })

# If no results parsed from verbose output, try the short summary
if not results:
    # Try to parse lines like: 3 passed, 1 failed
    summary_match = re.search(r'=+\s+(.*?)\s+=+', raw)
    if summary_match:
        sys.stderr.write(f'Warning: could not parse individual test results. Summary: {summary_match.group(1)}\n')

new_cases = [r for r in results if r['category'] == 'new']
regression_cases = [r for r in results if r['category'] == 'regression']

summary = {
    'new_passed': sum(1 for r in new_cases if r['status'] == 'passed'),
    'new_failed': sum(1 for r in new_cases if r['status'] == 'failed'),
    'new_error': sum(1 for r in new_cases if r['status'] == 'error'),
    'new_skipped': sum(1 for r in new_cases if r['status'] == 'skipped'),
    'new_total': len(new_cases),
    'regression_passed': sum(1 for r in regression_cases if r['status'] == 'passed'),
    'regression_failed': sum(1 for r in regression_cases if r['status'] == 'failed'),
    'regression_error': sum(1 for r in regression_cases if r['status'] == 'error'),
    'regression_skipped': sum(1 for r in regression_cases if r['status'] == 'skipped'),
    'regression_total': len(regression_cases),
    'total': len(results)
}

output = {
    'project_root': '$PROJECT_ROOT',
    'test_diff_id': test_diff_id if test_diff_id else None,
    'timestamp': '$NOW',
    'branch': '$BRANCH',
    'commit': '$COMMIT',
    'duration_seconds': $DURATION,
    'exit_code': $TEST_EXIT_CODE,
    'new_cases': new_cases,
    'regression_cases': regression_cases,
    'summary': summary,
    'raw_output_path': raw_output_path
}

print(json.dumps(output, indent=2, ensure_ascii=False))
"
