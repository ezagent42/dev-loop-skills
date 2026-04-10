#!/bin/bash
set -euo pipefail

# 查询 registry.json 中的 artifact。
# 支持按类型、状态、ID 查询，以及全局概览。

DRY_RUN=false
PROJECT_ROOT=""
TYPE=""
STATUS=""
ID=""
SUMMARY=false

usage() {
    cat <<EOF
Usage: $(basename "$0") --project-root <path> [--type <type>] [--status <status>]
       [--id <id>] [--summary] [--dry-run] [--help]

Query artifacts from the registry.

Options:
  --project-root <path>  Project root directory (required)
  --type <type>          Filter by artifact type
  --status <status>      Filter by status
  --id <id>              Look up a specific artifact by ID
  --summary              Show overview: count by type and status
  --dry-run              Show what query would be executed
  --help                 Show this help message

Output: JSON array of matching artifacts (or summary table with --summary).
Multiple filters are AND-combined.
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project-root) PROJECT_ROOT="$2"; shift 2 ;;
        --type) TYPE="$2"; shift 2 ;;
        --status) STATUS="$2"; shift 2 ;;
        --id) ID="$2"; shift 2 ;;
        --summary) SUMMARY=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        --help) usage ;;
        *) echo "Error: unknown option '$1'. Use --help for usage." >&2; exit 1 ;;
    esac
done

if [[ -z "$PROJECT_ROOT" ]]; then
    echo "Error: --project-root is required." >&2
    exit 1
fi

REGISTRY="$PROJECT_ROOT/.artifacts/registry.json"
if [[ ! -f "$REGISTRY" ]]; then
    echo "Error: registry not found at $REGISTRY. Run init-artifact-space.sh first." >&2
    exit 1
fi

if $DRY_RUN; then
    echo "[dry-run] Would query $REGISTRY with filters:"
    [[ -n "$TYPE" ]] && echo "  type=$TYPE"
    [[ -n "$STATUS" ]] && echo "  status=$STATUS"
    [[ -n "$ID" ]] && echo "  id=$ID"
    $SUMMARY && echo "  mode=summary"
    [[ -z "$TYPE" && -z "$STATUS" && -z "$ID" && "$SUMMARY" == "false" ]] && echo "  (no filters, return all)"
    exit 0
fi

if $SUMMARY; then
    python3 -c "
import json
from collections import Counter

with open('$REGISTRY') as f:
    data = json.load(f)

by_type = Counter()
by_status = Counter()
by_type_status = Counter()

for a in data['artifacts']:
    by_type[a['type']] += 1
    by_status[a['status']] += 1
    by_type_status[(a['type'], a['status'])] += 1

print('=== Artifact Registry Summary ===')
print(f'Total: {len(data[\"artifacts\"])} artifacts')
print()

if not data['artifacts']:
    print('(empty registry)')
else:
    print('By type:')
    for t, c in sorted(by_type.items()):
        print(f'  {t}: {c}')
    print()
    print('By status:')
    for s, c in sorted(by_status.items()):
        print(f'  {s}: {c}')
    print()
    print('Detail:')
    for (t, s), c in sorted(by_type_status.items()):
        print(f'  {t} [{s}]: {c}')
"
else
    python3 -c "
import json

with open('$REGISTRY') as f:
    data = json.load(f)

results = data['artifacts']

type_filter = '$TYPE'
status_filter = '$STATUS'
id_filter = '$ID'

if id_filter:
    results = [a for a in results if a['id'] == id_filter]
if type_filter:
    results = [a for a in results if a['type'] == type_filter]
if status_filter:
    results = [a for a in results if a['status'] == status_filter]

print(json.dumps(results, indent=2, ensure_ascii=False))
"
fi
