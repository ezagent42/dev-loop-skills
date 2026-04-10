#!/bin/bash
set -euo pipefail

# 验证 feature-eval 的所有脚本能正常工作。
# 测试 --help 和 --dry-run 模式。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [--dry-run] [--help]

Run self-tests for all feature-eval scripts.

Options:
  --dry-run   Only test --help and --dry-run modes (no external calls)
  --help      Show this help message

Tests:
  1. --help flag works for all scripts
  2. --dry-run flag works for all scripts (with sample inputs)
  3. Template file exists and has correct structure
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

SCRIPTS=(create-issue.sh add-watcher.sh)
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== feature-eval self-test ==="
echo ""

# Test 1: --help 返回 0
echo "Test 1: --help flag"
for s in "${SCRIPTS[@]}"; do
    if bash "$SCRIPT_DIR/$s" --help > /dev/null 2>&1; then
        pass "$s --help"
    else
        fail "$s --help"
    fi
done
# self-test 自身
if bash "$SCRIPT_DIR/self-test.sh" --help > /dev/null 2>&1; then
    pass "self-test.sh --help"
else
    fail "self-test.sh --help"
fi
echo ""

# Test 2: --dry-run 返回 0（使用模拟输入）
echo "Test 2: --dry-run flag"

# 创建临时 eval-doc 用于测试
TMPDIR=$(mktemp -d -t feature-eval-test-XXXXXX)
cat > "$TMPDIR/test-eval-doc.md" <<'EVALDOC'
---
type: eval-doc
id: eval-doc-001
status: draft
producer: skill-5
created_at: "2026-04-10"
mode: "verify"
feature: "自测功能"
submitter: "tester"
related: []
---

# Eval: 自测功能

## Testcase 表格

| # | 场景 | 前置条件 | 操作步骤 | 预期效果 | 实际效果 | 差异描述 | 优先级 |
|---|------|---------|---------|---------|---------|---------|--------|
| 1 | 测试场景 | 无 | 运行命令 | 正常输出 | 报错 | 有错误 | P0 |
EVALDOC

# create-issue.sh --dry-run
bash "$SCRIPT_DIR/create-issue.sh" \
    --eval-doc "$TMPDIR/test-eval-doc.md" \
    --repo "test-owner/test-repo" \
    --dry-run > /dev/null 2>&1 && pass "create-issue --dry-run" || fail "create-issue --dry-run"

# create-issue.sh --dry-run with labels
bash "$SCRIPT_DIR/create-issue.sh" \
    --eval-doc "$TMPDIR/test-eval-doc.md" \
    --repo "test-owner/test-repo" \
    --labels "bug,P0" \
    --dry-run > /dev/null 2>&1 && pass "create-issue --dry-run --labels" || fail "create-issue --dry-run --labels"

# add-watcher.sh --dry-run
bash "$SCRIPT_DIR/add-watcher.sh" \
    --issue-url "https://github.com/test-owner/test-repo/issues/1" \
    --watcher "testuser" \
    --dry-run > /dev/null 2>&1 && pass "add-watcher --dry-run" || fail "add-watcher --dry-run"

# add-watcher.sh invalid URL should fail
if bash "$SCRIPT_DIR/add-watcher.sh" \
    --issue-url "not-a-valid-url" \
    --watcher "testuser" \
    --dry-run > /dev/null 2>&1; then
    fail "add-watcher should reject invalid URL"
else
    pass "add-watcher rejects invalid URL"
fi

# create-issue.sh missing --eval-doc should fail
if bash "$SCRIPT_DIR/create-issue.sh" \
    --repo "test-owner/test-repo" \
    --dry-run > /dev/null 2>&1; then
    fail "create-issue should require --eval-doc"
else
    pass "create-issue requires --eval-doc"
fi

# create-issue.sh missing --repo should fail
if bash "$SCRIPT_DIR/create-issue.sh" \
    --eval-doc "$TMPDIR/test-eval-doc.md" \
    --dry-run > /dev/null 2>&1; then
    fail "create-issue should require --repo"
else
    pass "create-issue requires --repo"
fi

# add-watcher.sh missing --issue-url should fail
if bash "$SCRIPT_DIR/add-watcher.sh" \
    --watcher "testuser" \
    --dry-run > /dev/null 2>&1; then
    fail "add-watcher should require --issue-url"
else
    pass "add-watcher requires --issue-url"
fi

# add-watcher.sh missing --watcher should fail
if bash "$SCRIPT_DIR/add-watcher.sh" \
    --issue-url "https://github.com/test-owner/test-repo/issues/1" \
    --dry-run > /dev/null 2>&1; then
    fail "add-watcher should require --watcher"
else
    pass "add-watcher requires --watcher"
fi

rm -rf "$TMPDIR"
echo ""

# Test 3: 模板和引用文件存在
echo "Test 3: Required files exist"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$SKILL_DIR/templates/eval-doc.md" ]]; then
    pass "templates/eval-doc.md exists"
else
    fail "templates/eval-doc.md exists"
fi

if [[ -f "$SKILL_DIR/references/feedback-guide.md" ]]; then
    pass "references/feedback-guide.md exists"
else
    fail "references/feedback-guide.md exists"
fi

if [[ -f "$SKILL_DIR/SKILL.md" ]]; then
    pass "SKILL.md exists"
else
    fail "SKILL.md exists"
fi

# 检查 eval-doc 模板包含关键字段
if grep -q "type: eval-doc" "$SKILL_DIR/templates/eval-doc.md"; then
    pass "eval-doc template has type field"
else
    fail "eval-doc template has type field"
fi

if grep -q "Testcase" "$SKILL_DIR/templates/eval-doc.md"; then
    pass "eval-doc template has testcase table"
else
    fail "eval-doc template has testcase table"
fi

# 检查 feedback-guide 包含五步引导
GUIDE_STEPS=$(grep -c "^### 第" "$SKILL_DIR/references/feedback-guide.md" || true)
if [[ "$GUIDE_STEPS" -ge 5 ]]; then
    pass "feedback-guide has 5+ steps ($GUIDE_STEPS found)"
else
    fail "feedback-guide has 5+ steps ($GUIDE_STEPS found)"
fi

echo ""

echo "=== Results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
