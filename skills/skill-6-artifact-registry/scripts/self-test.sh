#!/bin/bash
set -euo pipefail

# 验证 artifact-registry 的所有脚本能正常工作。
# 使用临时目录模拟完整操作流程。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [--dry-run] [--help]

Run self-tests for all artifact-registry scripts.

Options:
  --dry-run   Only test --dry-run mode of each script (no temp dir, no git)
  --help      Show this help message

Tests:
  1. --help flag works for all scripts
  2. --dry-run flag works for all scripts
  3. Full integration: init → register → query → update-status → link
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

SCRIPTS=(init-artifact-space.sh register.sh query.sh update-status.sh link.sh)
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== artifact-registry self-test ==="
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
echo ""

# Test 2: --dry-run 返回 0（需要 --project-root 等必选参数）
echo "Test 2: --dry-run flag"
DUMMY="/tmp/self-test-dummy-$$"
mkdir -p "$DUMMY/.artifacts"
echo '{"version":1,"artifacts":[]}' > "$DUMMY/.artifacts/registry.json"

bash "$SCRIPT_DIR/init-artifact-space.sh" --project-root "$DUMMY" --dry-run > /dev/null 2>&1 && pass "init --dry-run" || fail "init --dry-run"
bash "$SCRIPT_DIR/register.sh" --project-root "$DUMMY" --type eval-doc --name test --producer test --path .artifacts/eval-docs/test.md --dry-run > /dev/null 2>&1 && pass "register --dry-run" || fail "register --dry-run"
bash "$SCRIPT_DIR/query.sh" --project-root "$DUMMY" --summary --dry-run > /dev/null 2>&1 && pass "query --dry-run" || fail "query --dry-run"
bash "$SCRIPT_DIR/update-status.sh" --project-root "$DUMMY" --id eval-doc-001 --status confirmed --dry-run > /dev/null 2>&1 && pass "update-status --dry-run" || fail "update-status --dry-run"
bash "$SCRIPT_DIR/link.sh" --project-root "$DUMMY" --from eval-doc-001 --to test-plan-001 --dry-run > /dev/null 2>&1 && pass "link --dry-run" || fail "link --dry-run"

rm -rf "$DUMMY"
echo ""

if $DRY_RUN; then
    echo "=== Dry-run mode: skipping integration test ==="
    echo ""
    echo "Results: $PASS passed, $FAIL failed"
    [[ $FAIL -eq 0 ]] && exit 0 || exit 1
fi

# Test 3: 完整集成测试（使用临时 git 仓库）
echo "Test 3: Integration test"
TMPDIR=$(mktemp -d -t artifact-registry-test-XXXXXX)
cd "$TMPDIR"
git init -q
git commit --allow-empty -m "init" -q

# init
bash "$SCRIPT_DIR/init-artifact-space.sh" --project-root "$TMPDIR" > /dev/null 2>&1 && pass "init" || fail "init"
[[ -f "$TMPDIR/.artifacts/registry.json" ]] && pass "registry.json exists" || fail "registry.json exists"

# register
REG_OUT=$(bash "$SCRIPT_DIR/register.sh" --project-root "$TMPDIR" --type eval-doc --name "test eval" --producer skill-5 --path .artifacts/eval-docs/eval-test-001.md 2>/dev/null)
[[ "$REG_OUT" == "eval-doc-001" ]] && pass "register returns ID" || fail "register returns ID (got: $REG_OUT)"

REG_OUT2=$(bash "$SCRIPT_DIR/register.sh" --project-root "$TMPDIR" --type test-plan --name "test plan" --producer skill-2 --path .artifacts/test-plans/plan-test-001.md 2>/dev/null)
[[ "$REG_OUT2" == "test-plan-001" ]] && pass "register second artifact" || fail "register second artifact (got: $REG_OUT2)"

# query
Q_COUNT=$(bash "$SCRIPT_DIR/query.sh" --project-root "$TMPDIR" --type eval-doc 2>/dev/null | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
[[ "$Q_COUNT" == "1" ]] && pass "query by type" || fail "query by type (count=$Q_COUNT)"

bash "$SCRIPT_DIR/query.sh" --project-root "$TMPDIR" --summary > /dev/null 2>&1 && pass "query --summary" || fail "query --summary"

# update-status
bash "$SCRIPT_DIR/update-status.sh" --project-root "$TMPDIR" --id eval-doc-001 --status confirmed > /dev/null 2>&1 && pass "update-status" || fail "update-status"

Q_STATUS=$(bash "$SCRIPT_DIR/query.sh" --project-root "$TMPDIR" --id eval-doc-001 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['status'])")
[[ "$Q_STATUS" == "confirmed" ]] && pass "status updated correctly" || fail "status updated (got: $Q_STATUS)"

# update-status backward should fail
if bash "$SCRIPT_DIR/update-status.sh" --project-root "$TMPDIR" --id eval-doc-001 --status draft 2>/dev/null; then
    fail "backward status transition should fail"
else
    pass "backward status transition rejected"
fi

# link
bash "$SCRIPT_DIR/link.sh" --project-root "$TMPDIR" --from eval-doc-001 --to test-plan-001 > /dev/null 2>&1 && pass "link" || fail "link"

Q_RELATED=$(bash "$SCRIPT_DIR/query.sh" --project-root "$TMPDIR" --id eval-doc-001 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print('test-plan-001' in d[0].get('related_ids',[]))")
[[ "$Q_RELATED" == "True" ]] && pass "link forward" || fail "link forward"

Q_RELATED_REV=$(bash "$SCRIPT_DIR/query.sh" --project-root "$TMPDIR" --id test-plan-001 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print('eval-doc-001' in d[0].get('related_ids',[]))")
[[ "$Q_RELATED_REV" == "True" ]] && pass "link bidirectional" || fail "link bidirectional"

# 清理
rm -rf "$TMPDIR"
echo ""

echo "=== Results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
