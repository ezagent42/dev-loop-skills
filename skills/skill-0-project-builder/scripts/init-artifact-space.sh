#!/bin/bash
set -euo pipefail

# Initialize .artifacts/ directory when Skill 6 is not available.
# When Skill 6 is available, use its init-artifact-space.sh instead.

DRY_RUN=false
PROJECT_ROOT=""

usage() {
    cat <<EOF
Usage: $(basename "$0") --project-root <path> [--dry-run] [--help]

Initialize .artifacts/ directory structure (fallback when Skill 6 is unavailable).

Options:
  --project-root <path>   Project root directory (required)
  --dry-run               Show what would be done
  --help                  Show this help message
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

if [[ -z "$PROJECT_ROOT" ]]; then
    echo "Error: --project-root is required." >&2
    exit 1
fi

ARTIFACTS_DIR="$PROJECT_ROOT/.artifacts"

if $DRY_RUN; then
    echo "[dry-run] Would create: $ARTIFACTS_DIR/{eval-docs,code-diffs,test-plans,test-diffs,e2e-reports,issues,coverage,bootstrap}"
    echo "[dry-run] Would create: $ARTIFACTS_DIR/registry.json"
    echo "[dry-run] Would create: $ARTIFACTS_DIR/.gitattributes (git-lfs config)"
    exit 0
fi

mkdir -p "$ARTIFACTS_DIR"/{eval-docs,code-diffs,test-plans,test-diffs,e2e-reports,issues,coverage,bootstrap/module-reports}
echo '{"version":1,"artifacts":[]}' > "$ARTIFACTS_DIR/registry.json"

cat > "$ARTIFACTS_DIR/.gitattributes" <<'EOF'
*.png filter=lfs diff=lfs merge=lfs -text
*.gif filter=lfs diff=lfs merge=lfs -text
*.cast filter=lfs diff=lfs merge=lfs -text
EOF

echo "Artifact space initialized at $ARTIFACTS_DIR"
