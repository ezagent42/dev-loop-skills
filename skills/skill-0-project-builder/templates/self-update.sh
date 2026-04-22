#!/bin/bash
set -euo pipefail

# Skill 1 self-update: drift detection (Layer 1).
#
# Run this every time before answering — it's cheap. It reports how far
# the working tree has moved from the baseline recorded in SKILL.md's
# frontmatter and flags anything that looks stale. It does NOT rewrite
# artifacts; that's `refresh-index.sh`'s job (Layer 2).
#
# Three layers of "update":
#
#   Layer 1 (this script, --check mode)
#     Cheap drift report. Run in Step 0 of every Q&A.
#
#   Layer 2 (refresh-index.sh --all / --with-baseline)
#     Re-run test-runners, rewrite test-baseline.json. Use after a PR merges.
#
#   Layer 3 (full Skill 0 re-bootstrap)
#     Re-scan, re-analyse, re-generate. Use after large refactors or
#     switching to a very different base branch.
#
# This script's --refresh and --rebootstrap modes print guidance, they
# do not actually do Layer 2/3 work (they're orchestration hints).

MODE="check"
PROJECT_ROOT=""
SKILL_DIR=""

usage() {
    cat <<EOF
Usage: $(basename "$0") [--check | --refresh | --rebootstrap] \\
       [--project-root <path>] [--skill-dir <path>] [--help]

Options:
  --check         (default) Report drift; no writes
  --refresh       Print refresh-index.sh invocation hints (Layer 2)
  --rebootstrap   Print Skill 0 re-bootstrap guidance (Layer 3)
  --project-root  Override project root (default: git toplevel of CWD)
  --skill-dir     Override skill dir (default: auto-detect from script location)
  --help          Show this message
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check) MODE="check"; shift ;;
        --refresh) MODE="refresh"; shift ;;
        --rebootstrap) MODE="rebootstrap"; shift ;;
        --project-root) PROJECT_ROOT="$2"; shift 2 ;;
        --skill-dir) SKILL_DIR="$2"; shift 2 ;;
        --help) usage ;;
        *) echo "Error: unknown option '$1'. Use --help." >&2; exit 1 ;;
    esac
done

# Project root: git toplevel, fallback to pwd
if [[ -z "$PROJECT_ROOT" ]]; then
    PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

# Skill dir: parent of this script (scripts/ is inside the skill dir)
if [[ -z "$SKILL_DIR" ]]; then
    SKILL_DIR="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"
fi

ARTIFACTS="$PROJECT_ROOT/.artifacts"
SKILL_MD="$SKILL_DIR/SKILL.md"

if [[ ! -f "$SKILL_MD" ]]; then
    echo "Error: SKILL.md not found at $SKILL_MD" >&2
    echo "       Use --skill-dir to point at the skill directory." >&2
    exit 1
fi

echo "=== Skill 1 self-update (mode: $MODE) ==="
echo "Project: $PROJECT_ROOT"
echo "Skill:   $SKILL_DIR"
echo ""

# ---------------------------------------------------------------
# Section 1: Branch / baseline drift
# ---------------------------------------------------------------

cur_branch="$(git -C "$PROJECT_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
cur_head="$(git -C "$PROJECT_ROOT" rev-parse --short HEAD 2>/dev/null || echo '?')"
echo "Current branch:  $cur_branch ($cur_head)"

# Extract baseline_commit from SKILL.md frontmatter
# Frontmatter is the first YAML block between `---` lines
claimed_commit="$(awk '
    /^---$/ {
        count++
        if (count == 2) exit
        next
    }
    count == 1 && /^baseline_commit:/ {
        sub(/^baseline_commit:[[:space:]]*/, "")
        gsub(/["\x27]/, "")
        gsub(/[[:space:]]/, "")
        print
        exit
    }
' "$SKILL_MD")"

if [[ -z "$claimed_commit" ]]; then
    echo "Baseline commit: (none — SKILL.md frontmatter lacks 'baseline_commit')"
    drift="?"
else
    echo "Baseline commit: $claimed_commit (from SKILL.md)"
    if git -C "$PROJECT_ROOT" cat-file -e "${claimed_commit}^{commit}" 2>/dev/null; then
        drift="$(git -C "$PROJECT_ROOT" rev-list --count "${claimed_commit}..HEAD" 2>/dev/null || echo '?')"
    else
        drift="baseline not in history"
    fi
fi
echo "Drift from baseline: $drift commits"

if [[ "$claimed_commit" != "" ]] && git -C "$PROJECT_ROOT" cat-file -e "${claimed_commit}^{commit}" 2>/dev/null; then
    changed_dirs="$(git -C "$PROJECT_ROOT" diff --name-only "${claimed_commit}..HEAD" 2>/dev/null | awk -F/ 'NF>0 {print $1}' | sort -u)"
    if [[ -n "$changed_dirs" ]]; then
        echo ""
        echo "Changed top-level paths since baseline:"
        echo "$changed_dirs" | sed 's/^/  /'
    fi
fi

# ---------------------------------------------------------------
# Section 2: New module source dirs that may lack a module-report
# ---------------------------------------------------------------
#
# Heuristic: we look at `.artifacts/bootstrap/module-file-lists.json`
# (produced by Skill 0 Step 3) for the authoritative list of modules at
# baseline time, and compare it against currently-existing source dirs
# that look like module boundaries. This is a best-effort heuristic —
# false positives are OK (they're just warnings).

echo ""
echo "=== Module coverage ==="
reports_dir="$ARTIFACTS/bootstrap/module-reports"
if [[ -d "$reports_dir" ]]; then
    report_count="$(find "$reports_dir" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l | tr -d ' ')"
    echo "  module-reports:  $report_count files at $reports_dir"
else
    echo "  module-reports:  (missing — Skill 0 Step 3 output not found)"
fi

# Check every known source-dir root for new subdirs not represented as
# a module-report. This is optional — only triggers a warning if there's
# clear evidence a new subsystem appeared.
# We look at common module-root patterns: {src,lib,app,cmd,pkg}/*/
if [[ -d "$reports_dir" ]]; then
    # Concatenate every module-report's content to search against. We grep
    # the module_path field — if a candidate dir is mentioned anywhere in
    # any report's module_path, consider it covered.
    reports_content="$(cat "$reports_dir"/*.json 2>/dev/null || true)"

    new_dirs=""
    for root in src lib app cmd pkg runtime/lib py/src adapters handlers; do
        [[ -d "$PROJECT_ROOT/$root" ]] || continue
        for d in "$PROJECT_ROOT/$root"/*/; do
            [[ -d "$d" ]] || continue
            name="$(basename "$d")"
            # Skip egg-info / build artifacts / hidden
            case "$name" in .*|*.egg-info|__pycache__|build|dist) continue ;; esac
            # Is "${root}/${name}" mentioned in any module-report's module_path?
            if ! printf '%s' "$reports_content" | grep -q "${root}/${name}"; then
                # Also accept report whose name matches the dir name (e.g. handler-feishu-app.json covers handlers/feishu_app)
                # by stripping common prefixes/suffixes and trying again
                norm="${name//_/-}"
                if ! find "$reports_dir" -maxdepth 1 \( -name "*${name}*.json" -o -name "*${norm}*.json" \) -print -quit 2>/dev/null | grep -q .; then
                    new_dirs="${new_dirs}  ⚠️  ${root}/${name} may lack a module-report\n"
                fi
            fi
        done
    done
    if [[ -n "$new_dirs" ]]; then
        printf "%b" "$new_dirs"
    else
        echo "  No obvious new subdirs without module-reports."
    fi
fi

# ---------------------------------------------------------------
# Section 3: Test runner inventory
# ---------------------------------------------------------------

echo ""
echo "=== Test runners ==="
if [[ -d "$SKILL_DIR/scripts" ]]; then
    runner_count="$(find "$SKILL_DIR/scripts" -maxdepth 1 -name 'test-*.sh' -not -name 'test-all.sh' 2>/dev/null | wc -l | tr -d ' ')"
    echo "  $runner_count test-*.sh scripts in $SKILL_DIR/scripts/"
fi

# ---------------------------------------------------------------
# Section 4: Artifact registry
# ---------------------------------------------------------------

if [[ -f "$ARTIFACTS/registry.json" ]]; then
    echo ""
    echo "=== Artifact registry ==="
    count="$(grep -c '"id"' "$ARTIFACTS/registry.json" 2>/dev/null || true)"
    echo "  Registered artifacts: $count"
    for t in eval-doc test-plan test-diff e2e-report code-diff issue coverage-matrix bootstrap-report; do
        n="$(grep -c "\"type\": \"$t\"" "$ARTIFACTS/registry.json" 2>/dev/null || true)"
        [[ "$n" -gt 0 ]] && printf "    %-20s %s\n" "$t:" "$n"
    done
fi

# ---------------------------------------------------------------
# Action / recommendation
# ---------------------------------------------------------------

echo ""
echo "=== Recommendation ==="

case "$MODE" in
  check)
    if [[ "$drift" == "?" || "$drift" == "0" ]]; then
        echo "No action needed — baseline is current."
        echo "If you added 'baseline_commit:' to SKILL.md frontmatter recently,"
        echo "subsequent --check calls will start showing drift."
    elif [[ "$drift" =~ ^[0-9]+$ ]] && [[ "$drift" -lt 10 ]]; then
        echo "Light drift ($drift commits)."
        echo "Consider:"
        echo "  bash $(basename "$0") --refresh   # get Layer 2 guidance"
    elif [[ "$drift" =~ ^[0-9]+$ ]]; then
        echo "Heavy drift ($drift commits)."
        echo "Check 'Changed top-level paths' above. If new module dirs appeared,"
        echo "the baseline may be structurally out of date."
        echo ""
        echo "Options:"
        echo "  bash $(basename "$0") --refresh        # Layer 2: rerun tests + baseline"
        echo "  bash $(basename "$0") --rebootstrap    # Layer 3: full Skill 0 re-run"
    else
        echo "Baseline commit not in current git history ($drift)."
        echo "You may have switched branches or rewritten history. Consider --rebootstrap."
    fi
    ;;
  refresh)
    echo "Layer 2 — rerun test-runners + refresh test-baseline.json"
    echo ""
    echo "Invoke refresh-index.sh:"
    echo "  bash $SKILL_DIR/scripts/refresh-index.sh --all --with-baseline"
    echo ""
    echo "After it finishes, update SKILL.md manually:"
    echo "  1. Self-Verification Record table (latest run column)"
    echo "  2. baseline_commit in frontmatter (if advancing the reference)"
    echo "  3. baseline_date in frontmatter"
    ;;
  rebootstrap)
    echo "Layer 3 — full Skill 0 re-bootstrap"
    echo ""
    echo "When: after mass rename/split/merge, new top-level language, or"
    echo "      switching to a fundamentally different base branch."
    echo ""
    echo "Steps:"
    echo "  1. Back up artifacts:   cp -r .artifacts .artifacts.bak-\$(date +%Y%m%d)"
    echo "  2. Invoke Skill 0:      dev-loop-skills:skill-0-project-builder"
    echo "  3. Let it re-run scan / env / module analysis / test baseline"
    echo "  4. Review diffs before committing"
    echo ""
    echo "For targeted work (one new module only):"
    echo "  Spawn a subagent using references/subagent-prompt.md from Skill 0's"
    echo "  templates to produce a single module-report."
    ;;
esac
