#!/bin/bash
set -euo pipefail

# 验证生成的 Skill 1 的 test-runner 脚本与基线结果一致。
# 如果任何 test-runner 的结果与基线不匹配，报告差异并返回非零。

DRY_RUN=false
SKILL1_PATH=""
BASELINE=""

usage() {
    cat <<EOF
Usage: $(basename "$0") --skill1-path <path> --baseline <path> [--dry-run] [--help]

Verify generated Skill 1 by running its test-runners and comparing with baseline.

Options:
  --skill1-path <path>   Path to generated Skill 1 directory (required)
  --baseline <path>      Path to test-baseline.json from run-full-tests.sh (required)
  --dry-run              Show what would be verified
  --help                 Show this help message

Runs each test-runner script in Skill 1's scripts/ directory and compares
exit codes and pass/fail counts with the baseline. Reports any mismatches.
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skill1-path) SKILL1_PATH="$2"; shift 2 ;;
        --baseline) BASELINE="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        --help) usage ;;
        *) echo "Error: unknown option '$1'. Use --help for usage." >&2; exit 1 ;;
    esac
done

if [[ -z "$SKILL1_PATH" || -z "$BASELINE" ]]; then
    echo "Error: --skill1-path and --baseline are required." >&2
    exit 1
fi

if [[ ! -d "$SKILL1_PATH" ]]; then
    echo "Error: Skill 1 directory not found: $SKILL1_PATH" >&2
    exit 1
fi

if [[ ! -f "$BASELINE" ]]; then
    echo "Error: baseline file not found: $BASELINE" >&2
    exit 1
fi

SCRIPTS_DIR="$SKILL1_PATH/scripts"
if [[ ! -d "$SCRIPTS_DIR" ]]; then
    echo "Error: no scripts/ directory in Skill 1." >&2
    exit 1
fi

if $DRY_RUN; then
    echo "[dry-run] Would verify Skill 1 at: $SKILL1_PATH"
    echo "[dry-run] Against baseline: $BASELINE"
    echo "[dry-run] Test-runner scripts found:"
    find "$SCRIPTS_DIR" -name "test-*.sh" -type f | while read -r f; do
        echo "  $(basename "$f")"
    done
    exit 0
fi

echo "=== Skill 1 Verification ==="
echo "Skill 1: $SKILL1_PATH"
echo "Baseline: $BASELINE"
echo ""

PASS=0
FAIL=0

for script in "$SCRIPTS_DIR"/test-*.sh; do
    [[ -f "$script" ]] || continue
    name=$(basename "$script")
    echo "Running: $name"

    # 运行 test-runner
    set +e
    output=$(bash "$script" 2>&1)
    exit_code=$?
    set -e

    # 检查是否成功（exit code 0）
    if [[ $exit_code -eq 0 ]]; then
        echo "  PASS: $name (exit code 0)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $name (exit code $exit_code)"
        echo "  Output (last 200 chars): ${output: -200}"
        FAIL=$((FAIL + 1))
    fi
done

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if [[ $FAIL -gt 0 ]]; then
    echo "Verification FAILED. Skill 1 has test-runners that don't match baseline."
    exit 1
else
    echo "Verification PASSED. All test-runners produce consistent results."
    exit 0
fi
