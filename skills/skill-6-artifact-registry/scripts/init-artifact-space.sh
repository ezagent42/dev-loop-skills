#!/bin/bash
set -euo pipefail

# 初始化项目的 .artifacts/ 目录结构和 registry.json。
# 如果已存在则跳过，避免覆盖已有数据。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=false
PROJECT_ROOT=""

usage() {
    cat <<EOF
Usage: $(basename "$0") --project-root <path> [--dry-run] [--help]

Initialize .artifacts/ directory structure for the dev-loop pipeline.

Options:
  --project-root <path>  Project root directory (required)
  --dry-run              Show what would be done without making changes
  --help                 Show this help message

Creates:
  .artifacts/registry.json         Empty artifact index
  .artifacts/.gitattributes        git-lfs config for binary files
  .artifacts/eval-docs/            Skill 5 output directory
  .artifacts/code-diffs/           Phase 2 output directory
  .artifacts/test-plans/           Skill 2 output directory
  .artifacts/test-diffs/           Skill 3 output directory
  .artifacts/e2e-reports/          Skill 4 output directory
  .artifacts/issues/               Skill 5 output directory
  .artifacts/coverage/             Skill 0/4 output directory
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

if ! git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree &>/dev/null; then
    echo "Error: '$PROJECT_ROOT' is not inside a git repository. Run 'git init' first." >&2
    exit 1
fi

ARTIFACTS_DIR="$PROJECT_ROOT/.artifacts"

if [[ -f "$ARTIFACTS_DIR/registry.json" ]]; then
    echo "Artifact space already initialized at $ARTIFACTS_DIR. Skipping."
    exit 0
fi

DIRS=(
    "$ARTIFACTS_DIR/eval-docs"
    "$ARTIFACTS_DIR/code-diffs"
    "$ARTIFACTS_DIR/test-plans"
    "$ARTIFACTS_DIR/test-diffs"
    "$ARTIFACTS_DIR/e2e-reports"
    "$ARTIFACTS_DIR/issues"
    "$ARTIFACTS_DIR/coverage"
)

if $DRY_RUN; then
    echo "[dry-run] Would create directories:"
    for d in "${DIRS[@]}"; do echo "  $d"; done
    echo "[dry-run] Would create $ARTIFACTS_DIR/registry.json"
    echo "[dry-run] Would create $ARTIFACTS_DIR/.gitattributes"
    echo "[dry-run] Would run: git add .artifacts/ && git commit"
    exit 0
fi

# 创建目录
for d in "${DIRS[@]}"; do
    mkdir -p "$d"
done

# 创建空 registry
cat > "$ARTIFACTS_DIR/registry.json" <<'REGISTRY'
{
  "version": 1,
  "artifacts": []
}
REGISTRY

# 配置 git-lfs
cat > "$ARTIFACTS_DIR/.gitattributes" <<'GITATTR'
*.png filter=lfs diff=lfs merge=lfs -text
*.gif filter=lfs diff=lfs merge=lfs -text
*.cast filter=lfs diff=lfs merge=lfs -text
*.jpg filter=lfs diff=lfs merge=lfs -text
GITATTR

# Git commit
cd "$PROJECT_ROOT"
git add .artifacts/
git commit -m "artifact: init artifact space"

echo "Artifact space initialized at $ARTIFACTS_DIR"
