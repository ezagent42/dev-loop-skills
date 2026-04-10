#!/bin/bash
set -euo pipefail

# 验证 skill-2-test-plan-generator 的所有文件存在且格式正确。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DRY_RUN=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [--dry-run] [--help]

Verify that all skill-2-test-plan-generator files exist and templates
have the expected structure.

Options:
  --dry-run   Only show what checks would be performed
  --help      Show this help message

Checks:
  1. All required files exist
  2. SKILL.md has valid YAML frontmatter
  3. Templates contain required placeholder fields
  4. References contain expected section headings
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

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== skill-2-test-plan-generator self-test ==="
echo ""

# --- Check 1: Required files exist ---
echo "Check 1: Required files exist"

REQUIRED_FILES=(
    "SKILL.md"
    "references/diff-analysis-guide.md"
    "references/coverage-gap-guide.md"
    "templates/test-case.md"
    "templates/plan-summary.md"
    "scripts/self-test.sh"
)

if $DRY_RUN; then
    echo "  [dry-run] Would check existence of ${#REQUIRED_FILES[@]} files:"
    for f in "${REQUIRED_FILES[@]}"; do
        echo "    $SKILL_DIR/$f"
    done
    echo ""
    echo "  [dry-run] Would check SKILL.md frontmatter"
    echo "  [dry-run] Would check template placeholders"
    echo "  [dry-run] Would check reference headings"
    echo ""
    echo "=== Dry-run complete ==="
    exit 0
fi

for f in "${REQUIRED_FILES[@]}"; do
    if [[ -f "$SKILL_DIR/$f" ]]; then
        pass "$f exists"
    else
        fail "$f missing"
    fi
done
echo ""

# --- Check 2: SKILL.md has valid YAML frontmatter ---
echo "Check 2: SKILL.md frontmatter"

SKILL_MD="$SKILL_DIR/SKILL.md"
if [[ -f "$SKILL_MD" ]]; then
    # Check starts with ---
    if head -1 "$SKILL_MD" | grep -q "^---$"; then
        pass "SKILL.md starts with ---"
    else
        fail "SKILL.md does not start with ---"
    fi

    # Check has name field
    if grep -q "^name:" "$SKILL_MD"; then
        pass "SKILL.md has name field"
    else
        fail "SKILL.md missing name field"
    fi

    # Check has description field
    if grep -q "^description:" "$SKILL_MD"; then
        pass "SKILL.md has description field"
    else
        fail "SKILL.md missing description field"
    fi

    # Check closing ---
    FRONT_CLOSE=$(awk 'NR>1 && /^---$/{print NR; exit}' "$SKILL_MD")
    if [[ -n "$FRONT_CLOSE" ]]; then
        pass "SKILL.md frontmatter closes at line $FRONT_CLOSE"
    else
        fail "SKILL.md frontmatter not closed"
    fi

    # Check line count < 500
    LINE_COUNT=$(wc -l < "$SKILL_MD")
    if [[ "$LINE_COUNT" -lt 500 ]]; then
        pass "SKILL.md has $LINE_COUNT lines (< 500)"
    else
        fail "SKILL.md has $LINE_COUNT lines (>= 500)"
    fi
else
    fail "SKILL.md not found, skipping frontmatter checks"
fi
echo ""

# --- Check 3: Templates have required placeholders ---
echo "Check 3: Template format"

TC_TEMPLATE="$SKILL_DIR/templates/test-case.md"
if [[ -f "$TC_TEMPLATE" ]]; then
    for field in "来源" "优先级" "前置条件" "操作步骤" "预期结果" "涉及模块"; do
        if grep -q "$field" "$TC_TEMPLATE"; then
            pass "test-case.md contains '$field'"
        else
            fail "test-case.md missing '$field'"
        fi
    done
    # Check source types match SKILL.md definitions
    for src_type in "code-diff" "coverage-gap" "eval-doc" "bug-feedback"; do
        if grep -q "$src_type" "$TC_TEMPLATE"; then
            pass "test-case.md lists source type '$src_type'"
        else
            fail "test-case.md missing source type '$src_type'"
        fi
    done
else
    fail "test-case.md not found"
fi

PLAN_TEMPLATE="$SKILL_DIR/templates/plan-summary.md"
if [[ -f "$PLAN_TEMPLATE" ]]; then
    # Check YAML frontmatter fields
    for field in "type: test-plan" "status: draft" "producer: skill-2" "trigger:"; do
        if grep -q "$field" "$PLAN_TEMPLATE"; then
            pass "plan-summary.md contains '$field'"
        else
            fail "plan-summary.md missing '$field'"
        fi
    done

    # Check required sections
    for section in "触发原因" "用例列表" "统计" "风险标注"; do
        if grep -q "## $section" "$PLAN_TEMPLATE"; then
            pass "plan-summary.md has section '$section'"
        else
            fail "plan-summary.md missing section '$section'"
        fi
    done

    # Check statistics table has key rows (including all source types)
    for row in "总用例数" "P0" "P1" "P2" "bug-feedback"; do
        if grep -q "$row" "$PLAN_TEMPLATE"; then
            pass "plan-summary.md statistics has '$row'"
        else
            fail "plan-summary.md statistics missing '$row'"
        fi
    done
else
    fail "plan-summary.md not found"
fi
echo ""

# --- Check 4: References have expected headings ---
echo "Check 4: Reference documents"

DIFF_GUIDE="$SKILL_DIR/references/diff-analysis-guide.md"
if [[ -f "$DIFF_GUIDE" ]]; then
    for heading in "提取变更文件列表" "定位模块" "识别.*用户流程" "评估改动风险"; do
        if grep -qE "$heading" "$DIFF_GUIDE"; then
            pass "diff-analysis-guide.md covers '$heading'"
        else
            fail "diff-analysis-guide.md missing '$heading'"
        fi
    done
else
    fail "diff-analysis-guide.md not found"
fi

COVERAGE_GUIDE="$SKILL_DIR/references/coverage-gap-guide.md"
if [[ -f "$COVERAGE_GUIDE" ]]; then
    for heading in "读取已有覆盖" "映射改动到场景" "标注缺口" "标注回归风险"; do
        if grep -qE "$heading" "$COVERAGE_GUIDE"; then
            pass "coverage-gap-guide.md covers '$heading'"
        else
            fail "coverage-gap-guide.md missing '$heading'"
        fi
    done
else
    fail "coverage-gap-guide.md not found"
fi
echo ""

# --- Summary ---
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
