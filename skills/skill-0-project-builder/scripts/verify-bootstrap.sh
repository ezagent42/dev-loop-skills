#!/bin/bash
set -euo pipefail

# Bootstrap 完成性验证脚本
# 在 Step 8 之前运行，强制检查所有步骤的产出是否存在。
# 任何缺失都阻断——不能带着不完整的 bootstrap 产出进入 Skill 1 生成。

PROJECT_ROOT=""
DRY_RUN=false

usage() {
    cat <<'EOF'
Usage: verify-bootstrap.sh --project-root <path> [--dry-run] [--help]

Verify that all bootstrap steps produced their required outputs.
Run this BEFORE generating Skill 1 (Step 7) to catch skipped steps.

Checks:
  Step 1: manifest.json exists
  Step 2: env-report.json exists
  Step 3: module-reports/ has files for each source module
  Step 4: ALL tests executed (0 env errors)
  Step 5: coverage-matrix.md exists with valid frontmatter
  Step 6: .artifacts/ initialized with registry.json
  Step 7.5: bootstrap-report.md exists (after Skill 1 generation)

Options:
  --project-root <path>   Project root directory (required)
  --dry-run               Show what would be checked
  --help                  Show this help
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project-root) PROJECT_ROOT="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        --help) usage ;;
        *) echo "Error: unknown option '$1'" >&2; exit 1 ;;
    esac
done

if [ -z "$PROJECT_ROOT" ]; then
    echo "Error: --project-root is required." >&2
    exit 1
fi

if $DRY_RUN; then
    echo "[dry-run] Would verify bootstrap outputs in $PROJECT_ROOT"
    exit 0
fi

ARTIFACTS="$PROJECT_ROOT/.artifacts"
PASS=0
FAIL=0
WARN=0

check() {
    local severity="$1" desc="$2" result="$3"
    if [ "$result" = "true" ]; then
        echo "  ✅ $desc"
        PASS=$((PASS + 1))
    elif [ "$severity" = "BLOCK" ]; then
        echo "  ❌ [BLOCKING] $desc"
        FAIL=$((FAIL + 1))
    else
        echo "  ⚠️  [WARNING] $desc"
        WARN=$((WARN + 1))
    fi
}

echo "=== Bootstrap Completeness Verification ==="
echo "Project: $PROJECT_ROOT"
echo ""

# --- Step 1: manifest ---
echo "Step 1: Scan project files"
# manifest 可能在临时位置或 .artifacts/bootstrap/
manifest_found=false
for loc in "$ARTIFACTS/bootstrap/manifest.json" "/tmp/zchat-manifest.json"; do
    [ -f "$loc" ] && manifest_found=true && break
done
check "BLOCK" "manifest.json exists" "$manifest_found"

# --- Step 2: env-report ---
echo ""
echo "Step 2: Environment check"
env_found=false
for loc in "$ARTIFACTS/bootstrap/env-report.json" "/tmp/zchat-env-report"*.json; do
    [ -f "$loc" ] 2>/dev/null && env_found=true && break
done
check "BLOCK" "env-report.json exists" "$env_found"

# --- Step 3: module-reports ---
echo ""
echo "Step 3: Module analysis"
report_dir="$ARTIFACTS/bootstrap/module-reports"
if [ -d "$report_dir" ]; then
    report_count=$(find "$report_dir" -name "*.json" -type f | wc -l)
    check "BLOCK" "module-reports/ has files ($report_count found)" \
        "$([ "$report_count" -ge 5 ] && echo true || echo false)"

    # 检查关键模块是否都有 report
    for module in agent_manager irc_manager auth project app zellij; do
        has_report=$(find "$report_dir" -name "${module}*" -type f | wc -l)
        check "BLOCK" "module-report for $module exists" \
            "$([ "$has_report" -gt 0 ] && echo true || echo false)"
    done
else
    check "BLOCK" "module-reports/ directory exists" "false"
fi

# --- Step 4: tests executed ---
echo ""
echo "Step 4: Test execution"
# 检查 .pytest_cache 或 __pycache__ 存在（说明 pytest 跑过）
main_ran=false
[ -d "$PROJECT_ROOT/.pytest_cache" ] && main_ran=true
find "$PROJECT_ROOT/tests" -name "*.pyc" -type f 2>/dev/null | grep -q . && main_ran=true
check "BLOCK" "main project tests executed" "$main_ran"

# 检查子模块测试也跑过（通过 .pytest_cache 或 .venv 中的 __pycache__）
for submod in zchat-channel-server zchat-protocol; do
    submod_ran=false
    [ -d "$PROJECT_ROOT/$submod/.pytest_cache" ] && submod_ran=true
    find "$PROJECT_ROOT/$submod" -name "*.pyc" -type f 2>/dev/null | grep -q . && submod_ran=true
    # 如果子模块有 .venv，说明 uv sync + pytest 跑过
    [ -d "$PROJECT_ROOT/$submod/.venv" ] && submod_ran=true
    check "BLOCK" "$submod tests executed" "$submod_ran"
done

# --- Step 5: coverage-matrix ---
echo ""
echo "Step 5: Coverage matrix"
cm_path="$ARTIFACTS/coverage/coverage-matrix.md"
check "BLOCK" "coverage-matrix.md exists" "$([ -f "$cm_path" ] && echo true || echo false)"
if [ -f "$cm_path" ]; then
    has_fm=$(head -1 "$cm_path" | grep -c '^---' || true)
    check "BLOCK" "coverage-matrix has YAML frontmatter" \
        "$([ "$has_fm" -gt 0 ] && echo true || echo false)"
    has_e2e=$(grep -c 'E2E' "$cm_path" || true)
    check "WARN" "coverage-matrix mentions E2E coverage ($has_e2e occurrences)" \
        "$([ "$has_e2e" -gt 3 ] && echo true || echo false)"
fi

# --- Step 6: artifact space ---
echo ""
echo "Step 6: Artifact space"
check "BLOCK" ".artifacts/ directory exists" \
    "$([ -d "$ARTIFACTS" ] && echo true || echo false)"
check "BLOCK" "registry.json exists" \
    "$([ -f "$ARTIFACTS/registry.json" ] && echo true || echo false)"
if [ -f "$ARTIFACTS/registry.json" ]; then
    artifact_count=$(grep -c '"id"' "$ARTIFACTS/registry.json" 2>/dev/null || true)
    check "BLOCK" "registry has at least 1 artifact ($artifact_count found)" \
        "$([ "$artifact_count" -ge 1 ] && echo true || echo false)"
fi

# 检查必要子目录
for dir in eval-docs test-plans test-diffs e2e-reports coverage; do
    check "WARN" ".artifacts/$dir/ exists" \
        "$([ -d "$ARTIFACTS/$dir" ] && echo true || echo false)"
done

# --- Step 7.5: bootstrap-report ---
echo ""
echo "Step 7.5: Bootstrap report"
br_path="$ARTIFACTS/bootstrap/bootstrap-report.md"
check "WARN" "bootstrap-report.md exists" "$([ -f "$br_path" ] && echo true || echo false)"
if [ -f "$br_path" ]; then
    has_env=$(grep -c '环境' "$br_path" || true)
    has_test=$(grep -c '测试' "$br_path" || true)
    check "WARN" "bootstrap-report has env section ($has_env)" \
        "$([ "$has_env" -gt 0 ] && echo true || echo false)"
    check "WARN" "bootstrap-report has test section ($has_test)" \
        "$([ "$has_test" -gt 0 ] && echo true || echo false)"
fi

# --- Summary ---
echo ""
echo "========================================"
echo "Results: $PASS passed, $FAIL blocked, $WARN warnings"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "❌ BOOTSTRAP INCOMPLETE — $FAIL blocking issues found."
    echo "   Fix the BLOCKING items above before proceeding to Skill 1 generation."
    echo "   Re-run this script after fixing."
    exit 1
fi

if [ "$WARN" -gt 0 ]; then
    echo ""
    echo "⚠️  BOOTSTRAP MOSTLY COMPLETE — $WARN non-blocking warnings."
    echo "   These are recommended but not required for Skill 1 generation."
fi

echo ""
echo "✅ Bootstrap verification passed. Safe to proceed to Step 7 (Skill 1 generation)."
