#!/bin/bash
set -euo pipefail

# Verify skill-3 (test-code-writer) directory structure and file integrity.
# Checks that all expected files exist, SKILL.md has valid frontmatter,
# references are non-empty, and all cross-references resolve.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
DRY_RUN=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [--dry-run] [--help]

Verify test-code-writer skill structure and content integrity.

Options:
  --dry-run   Only check file existence (skip content validation)
  --help      Show this help message

Checks:
  1. Directory structure: SKILL.md, references/, scripts/
  2. SKILL.md frontmatter: name and description fields present
  3. SKILL.md length: under 500 lines
  4. Reference files: exist and are non-empty
  5. Cross-references: all file references in SKILL.md resolve
  6. Script compliance: self-test.sh supports --help and --dry-run
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

echo "=== test-code-writer self-test ==="
echo ""

# Test 1: Directory structure
echo "Test 1: Directory structure"
[[ -f "$SKILL_DIR/SKILL.md" ]] && pass "SKILL.md exists" || fail "SKILL.md missing"
[[ -d "$SKILL_DIR/references" ]] && pass "references/ exists" || fail "references/ missing"
[[ -d "$SKILL_DIR/scripts" ]] && pass "scripts/ exists" || fail "scripts/ missing"
echo ""

# Test 2: Expected files
echo "Test 2: Expected files"
EXPECTED_FILES=(
    "references/pytest-pattern.md"
    "references/append-rules.md"
    "references/naming-convention.md"
    "scripts/self-test.sh"
)

for f in "${EXPECTED_FILES[@]}"; do
    if [[ -f "$SKILL_DIR/$f" ]]; then
        pass "$f exists"
    else
        fail "$f missing"
    fi
done
echo ""

if $DRY_RUN; then
    echo "=== Dry-run mode: skipping content validation ==="
    echo ""
    echo "Results: $PASS passed, $FAIL failed"
    [[ $FAIL -eq 0 ]] && exit 0 || exit 1
fi

# Test 3: SKILL.md frontmatter
echo "Test 3: SKILL.md frontmatter"
SKILL_MD="$SKILL_DIR/SKILL.md"

# Check YAML frontmatter delimiters
HEAD=$(head -1 "$SKILL_MD")
if [[ "$HEAD" == "---" ]]; then
    pass "frontmatter starts with ---"
else
    fail "frontmatter missing opening ---"
fi

# Check name field
if grep -q '^name:' "$SKILL_MD"; then
    NAME_VAL=$(grep '^name:' "$SKILL_MD" | head -1 | sed 's/^name: *//' | tr -d '"')
    if [[ "$NAME_VAL" == "test-code-writer" ]]; then
        pass "name: test-code-writer"
    else
        fail "name is '$NAME_VAL' (expected 'test-code-writer')"
    fi
else
    fail "name field missing"
fi

# Check description field
if grep -q '^description:' "$SKILL_MD"; then
    pass "description field present"
else
    fail "description field missing"
fi
echo ""

# Test 4: SKILL.md length
echo "Test 4: SKILL.md length"
LINE_COUNT=$(wc -l < "$SKILL_MD")
if [[ "$LINE_COUNT" -lt 500 ]]; then
    pass "SKILL.md is $LINE_COUNT lines (< 500)"
else
    fail "SKILL.md is $LINE_COUNT lines (>= 500, limit is 500)"
fi
echo ""

# Test 5: Reference files are non-empty
echo "Test 5: Reference file content"
for f in "${EXPECTED_FILES[@]}"; do
    FPATH="$SKILL_DIR/$f"
    if [[ -f "$FPATH" ]]; then
        SIZE=$(wc -c < "$FPATH")
        if [[ "$SIZE" -gt 100 ]]; then
            pass "$f has content ($SIZE bytes)"
        else
            fail "$f is too small ($SIZE bytes)"
        fi
    fi
done
echo ""

# Test 6: Cross-references in SKILL.md resolve
echo "Test 6: Cross-reference integrity"
# Extract references to local references/ and scripts/ paths.
# Skip absolute paths (containing /) that point to other skills — those are
# external commands, not local file references. We only check paths that appear
# as bare `references/...` or `scripts/...` without a leading path component.
REFS=$(grep -oP '(?<![a-zA-Z0-9_/.-])references/[a-zA-Z0-9_-]+\.md' "$SKILL_MD" | sort -u || true)
for ref in $REFS; do
    if [[ -f "$SKILL_DIR/$ref" ]]; then
        pass "ref $ref resolves"
    else
        fail "ref $ref is dead link"
    fi
done

# Only match scripts/ that are local to this skill (not preceded by a path separator)
# External scripts like /home/.../artifact-registry/scripts/query.sh are excluded
SCRIPT_REFS=$(grep -oP '(?<![a-zA-Z0-9_/.-])scripts/[a-zA-Z0-9_-]+\.sh' "$SKILL_MD" | sort -u || true)
for ref in $SCRIPT_REFS; do
    if [[ -f "$SKILL_DIR/$ref" ]]; then
        pass "ref $ref resolves"
    else
        fail "ref $ref is dead link"
    fi
done
echo ""

# Test 7: Description quality (has key triggers but is not excessively long)
echo "Test 7: Description quality"
DESC=$(grep '^description:' "$SKILL_MD" | head -1)
DESC_LEN=${#DESC}
TRIGGERS=("test-plan" "E2E" "pytest" "test-diff")
TRIGGER_COUNT=0
for t in "${TRIGGERS[@]}"; do
    if echo "$DESC" | grep -qi "$t"; then
        TRIGGER_COUNT=$((TRIGGER_COUNT + 1))
    fi
done
if [[ "$TRIGGER_COUNT" -ge 3 ]]; then
    pass "description covers $TRIGGER_COUNT/4 key terms"
else
    fail "description only covers $TRIGGER_COUNT/4 key terms (need >= 3)"
fi
if [[ "$DESC_LEN" -le 400 ]]; then
    pass "description length is $DESC_LEN chars (<= 400)"
else
    fail "description is $DESC_LEN chars (> 400, likely keyword-stuffed)"
fi
echo ""

echo "=== Results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
