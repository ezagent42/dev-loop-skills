#!/bin/bash
set -euo pipefail

# E2E 执行前的环境预检。
# 检查外部服务、工具链和测试目录是否就绪。

DRY_RUN=false
PROJECT_ROOT=""

usage() {
    cat <<EOF
Usage: $(basename "$0") --project-root <path> [--dry-run] [--help]

Pre-flight check for E2E test dependencies.

Required:
  --project-root <path>   Project root directory

Optional:
  --dry-run               Show what checks would be performed
  --help                  Show this help message

Checks (hard = blocks test execution, soft = warning only):
  [hard] Python / uv / pytest available
  [hard] E2E test directory exists with test files
  [hard] Project dependencies installed (uv sync)
  [soft] Zellij available (terminal evidence capture)
  [soft] Asciinema available (session recording)
  [soft] tmux available (fallback terminal capture)
  [soft] IRC server reachable (if project uses IRC)
  [soft] Evidence output directory writable

Output:
  stdout: JSON object with overall status, check details, and counts
  stderr: human-readable check results
  exit 0: all hard checks pass
  exit 1: any hard check fails
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project-root) PROJECT_ROOT="$2"; shift 2 ;;
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

if $DRY_RUN; then
    echo "[dry-run] Would check the following for project at $PROJECT_ROOT:" >&2
    echo "  [hard] Python runtime" >&2
    echo "  [hard] uv package manager" >&2
    echo "  [hard] pytest test framework" >&2
    echo "  [hard] E2E test directory" >&2
    echo "  [hard] Project dependencies (uv sync)" >&2
    echo "  [soft] Zellij terminal multiplexer" >&2
    echo "  [soft] Asciinema recorder" >&2
    echo "  [soft] tmux terminal multiplexer" >&2
    echo "  [soft] IRC server connectivity" >&2
    echo "  [soft] Evidence directory writable" >&2
    cat <<ENDJSON
{
  "project_root": "$PROJECT_ROOT",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "overall": "dry_run",
  "total_checks": 0,
  "hard_failures": 0,
  "soft_warnings": 0,
  "checks": []
}
ENDJSON
    exit 0
fi

HARD_FAIL=0
SOFT_FAIL=0
TOTAL=0

check_hard() {
    local name="$1"
    local result="$2"
    TOTAL=$((TOTAL + 1))
    if [[ "$result" == "ok" ]]; then
        echo "  [hard] PASS  $name" >&2
        JSON_CHECKS+=("{\"name\":\"$name\",\"level\":\"hard\",\"status\":\"pass\",\"detail\":\"ok\"}")
    else
        echo "  [hard] FAIL  $name -- $result" >&2
        HARD_FAIL=$((HARD_FAIL + 1))
        JSON_CHECKS+=("{\"name\":\"$name\",\"level\":\"hard\",\"status\":\"fail\",\"detail\":\"$result\"}")
    fi
}

check_soft() {
    local name="$1"
    local result="$2"
    TOTAL=$((TOTAL + 1))
    if [[ "$result" == "ok" ]]; then
        echo "  [soft] PASS  $name" >&2
        JSON_CHECKS+=("{\"name\":\"$name\",\"level\":\"soft\",\"status\":\"pass\",\"detail\":\"ok\"}")
    else
        echo "  [soft] WARN  $name -- $result" >&2
        SOFT_FAIL=$((SOFT_FAIL + 1))
        JSON_CHECKS+=("{\"name\":\"$name\",\"level\":\"soft\",\"status\":\"warn\",\"detail\":\"$result\"}")
    fi
}

echo "=== E2E Environment Check ===" >&2
echo "Project: $PROJECT_ROOT" >&2
echo "" >&2

# JSON output accumulators
declare -a JSON_CHECKS=()

# --- Hard checks ---

# Python
if command -v python3 &>/dev/null; then
    PY_VER=$(python3 --version 2>&1)
    check_hard "Python ($PY_VER)" "ok"
else
    check_hard "Python" "python3 not found in PATH"
fi

# uv
if command -v uv &>/dev/null; then
    UV_VER=$(uv --version 2>&1 | head -1)
    check_hard "uv ($UV_VER)" "ok"
else
    check_hard "uv" "uv not found in PATH (install: curl -LsSf https://astral.sh/uv/install.sh | sh)"
fi

# pytest (via uv or direct)
if command -v uv &>/dev/null; then
    if (cd "$PROJECT_ROOT" && uv run pytest --version &>/dev/null); then
        PYTEST_VER=$(cd "$PROJECT_ROOT" && uv run pytest --version 2>&1 | head -1)
        check_hard "pytest ($PYTEST_VER)" "ok"
    else
        check_hard "pytest (via uv)" "uv run pytest --version failed. Run: uv sync"
    fi
elif command -v pytest &>/dev/null; then
    PYTEST_VER=$(pytest --version 2>&1 | head -1)
    check_hard "pytest ($PYTEST_VER)" "ok"
else
    check_hard "pytest" "pytest not found"
fi

# E2E test directory
E2E_DIR=""
for candidate in "tests/e2e" "test/e2e" "tests/e2e_tests" "e2e"; do
    if [[ -d "$PROJECT_ROOT/$candidate" ]]; then
        E2E_DIR="$candidate"
        break
    fi
done

if [[ -n "$E2E_DIR" ]]; then
    TEST_COUNT=$(find "$PROJECT_ROOT/$E2E_DIR" -name "test_*.py" -o -name "*_test.py" 2>/dev/null | wc -l)
    if [[ "$TEST_COUNT" -gt 0 ]]; then
        check_hard "E2E test directory ($E2E_DIR, $TEST_COUNT file(s))" "ok"
    else
        check_hard "E2E test directory ($E2E_DIR)" "directory exists but no test files found"
    fi
else
    check_hard "E2E test directory" "no e2e test directory found (tried tests/e2e, test/e2e, etc.)"
fi

# Project dependencies
if [[ -f "$PROJECT_ROOT/pyproject.toml" ]] && command -v uv &>/dev/null; then
    if (cd "$PROJECT_ROOT" && uv sync --dry-run &>/dev/null 2>&1); then
        check_hard "Project dependencies (uv)" "ok"
    else
        check_hard "Project dependencies (uv)" "uv sync may be needed. Run: cd $PROJECT_ROOT && uv sync"
    fi
else
    check_hard "Project dependencies" "ok (no pyproject.toml or uv not available, skipping)"
fi

echo "" >&2

# --- Soft checks ---

# Zellij
if command -v zellij &>/dev/null; then
    ZELLIJ_VER=$(zellij --version 2>&1 | head -1)
    check_soft "Zellij ($ZELLIJ_VER)" "ok"
else
    check_soft "Zellij" "not found (terminal evidence capture will be limited)"
fi

# Asciinema
if command -v asciinema &>/dev/null; then
    check_soft "Asciinema" "ok"
else
    check_soft "Asciinema" "not found (session recording unavailable)"
fi

# tmux
if command -v tmux &>/dev/null; then
    TMUX_VER=$(tmux -V 2>&1 | head -1)
    check_soft "tmux ($TMUX_VER)" "ok"
else
    check_soft "tmux" "not found (fallback terminal capture unavailable)"
fi

# IRC server (check common ports)
IRC_PORT=6667
if command -v ss &>/dev/null; then
    if ss -tlnp 2>/dev/null | grep -q ":${IRC_PORT} "; then
        check_soft "IRC server (port $IRC_PORT)" "ok"
    else
        check_soft "IRC server (port $IRC_PORT)" "not listening (IRC-dependent tests may skip)"
    fi
elif command -v netstat &>/dev/null; then
    if netstat -tlnp 2>/dev/null | grep -q ":${IRC_PORT} "; then
        check_soft "IRC server (port $IRC_PORT)" "ok"
    else
        check_soft "IRC server (port $IRC_PORT)" "not listening (IRC-dependent tests may skip)"
    fi
else
    check_soft "IRC server (port $IRC_PORT)" "cannot check (ss/netstat not available)"
fi

# Evidence directory writable
if [[ -n "$E2E_DIR" ]]; then
    EVIDENCE_DIR="$PROJECT_ROOT/$E2E_DIR/evidence"
    if [[ -d "$EVIDENCE_DIR" ]] && [[ -w "$EVIDENCE_DIR" ]]; then
        check_soft "Evidence directory ($EVIDENCE_DIR)" "ok"
    elif mkdir -p "$EVIDENCE_DIR" 2>/dev/null; then
        check_soft "Evidence directory ($EVIDENCE_DIR)" "ok (created)"
    else
        check_soft "Evidence directory ($EVIDENCE_DIR)" "cannot create or write"
    fi
fi

echo "" >&2

# --- Summary ---
HARD_PASS=$((TOTAL - HARD_FAIL - SOFT_FAIL))
echo "=== Summary: $TOTAL checks, $((TOTAL - HARD_FAIL - SOFT_FAIL)) passed, $HARD_FAIL hard fail(s), $SOFT_FAIL soft warning(s) ===" >&2

# --- JSON output to stdout ---
OVERALL="ready"
if [[ $HARD_FAIL -gt 0 ]]; then
    OVERALL="blocked"
elif [[ $SOFT_FAIL -gt 0 ]]; then
    OVERALL="ready_with_warnings"
fi

# Build JSON array from checks
JSON_ARRAY=""
for i in "${!JSON_CHECKS[@]}"; do
    if [[ $i -gt 0 ]]; then JSON_ARRAY+=","; fi
    JSON_ARRAY+="${JSON_CHECKS[$i]}"
done

cat <<ENDJSON
{
  "project_root": "$PROJECT_ROOT",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "overall": "$OVERALL",
  "total_checks": $TOTAL,
  "hard_failures": $HARD_FAIL,
  "soft_warnings": $SOFT_FAIL,
  "checks": [$JSON_ARRAY]
}
ENDJSON

if [[ $HARD_FAIL -gt 0 ]]; then
    echo "" >&2
    echo "BLOCKED: $HARD_FAIL hard dependency missing. Fix before running E2E tests." >&2
    exit 1
fi

if [[ $SOFT_FAIL -gt 0 ]]; then
    echo "" >&2
    echo "READY with warnings: $SOFT_FAIL soft dependency missing. Tests can run but evidence capture may be limited." >&2
fi

exit 0
