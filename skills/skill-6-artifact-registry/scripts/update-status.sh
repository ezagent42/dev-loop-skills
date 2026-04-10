#!/bin/bash
set -euo pipefail

# 更新 artifact 的生命周期状态。
# 验证状态流转方向（只能前进，不能倒退）。

DRY_RUN=false
PROJECT_ROOT=""
ID=""
NEW_STATUS=""

usage() {
    cat <<EOF
Usage: $(basename "$0") --project-root <path> --id <id> --status <status>
       [--dry-run] [--help]

Update an artifact's lifecycle status.

Options:
  --project-root <path>  Project root directory (required)
  --id <id>              Artifact ID to update (required)
  --status <status>      New status (required)
  --dry-run              Show what would be done without making changes
  --help                 Show this help message

Valid status transitions (forward only):
  draft → confirmed → executed → archived
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project-root) PROJECT_ROOT="$2"; shift 2 ;;
        --id) ID="$2"; shift 2 ;;
        --status) NEW_STATUS="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        --help) usage ;;
        *) echo "Error: unknown option '$1'. Use --help for usage." >&2; exit 1 ;;
    esac
done

for param in PROJECT_ROOT ID NEW_STATUS; do
    if [[ -z "${!param}" ]]; then
        echo "Error: --$(echo "$param" | tr '[:upper:]' '[:lower:]' | tr '_' '-') is required." >&2
        exit 1
    fi
done

REGISTRY="$PROJECT_ROOT/.artifacts/registry.json"
if [[ ! -f "$REGISTRY" ]]; then
    echo "Error: registry not found at $REGISTRY." >&2
    exit 1
fi

if $DRY_RUN; then
    echo "[dry-run] Would update artifact '$ID' status to '$NEW_STATUS'"
    echo "[dry-run] Would update $REGISTRY"
    echo "[dry-run] Would run: git add .artifacts/ && git commit"
    exit 0
fi

python3 -c "
import json, sys

STATUS_ORDER = ['draft', 'confirmed', 'executed', 'archived']

with open('$REGISTRY') as f:
    data = json.load(f)

new_status = '$NEW_STATUS'
target_id = '$ID'

if new_status not in STATUS_ORDER:
    print(f'Error: invalid status \"{new_status}\". Valid: {STATUS_ORDER}', file=sys.stderr)
    sys.exit(1)

found = False
for a in data['artifacts']:
    if a['id'] == target_id:
        found = True
        current = a['status']
        cur_idx = STATUS_ORDER.index(current)
        new_idx = STATUS_ORDER.index(new_status)
        if new_idx <= cur_idx:
            print(f'Error: cannot transition from \"{current}\" to \"{new_status}\" (status can only move forward).', file=sys.stderr)
            sys.exit(1)
        a['status'] = new_status
        from datetime import datetime, timezone
        a['updated_at'] = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
        break

if not found:
    print(f'Error: artifact \"{target_id}\" not found in registry.', file=sys.stderr)
    sys.exit(1)

with open('$REGISTRY', 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
"

cd "$PROJECT_ROOT"
git add .artifacts/
git commit -m "artifact: update-status $ID $NEW_STATUS"

echo "Updated $ID → $NEW_STATUS"
