#!/bin/bash
set -euo pipefail

# 枚举项目中所有源文件，产出 manifest.json。
# 排除 .git、node_modules、__pycache__、.venv 等。
# 这是 bootstrap 的第一步——脚本枚举，不是 LLM 猜测。

DRY_RUN=false
PROJECT_ROOT=""
OUTPUT=""

usage() {
    cat <<EOF
Usage: $(basename "$0") --project-root <path> [--output <path>] [--dry-run] [--help]

Scan a project and produce a manifest of all source files.

Options:
  --project-root <path>  Project root directory (required)
  --output <path>        Output path for manifest.json (default: stdout)
  --dry-run              Show what would be scanned without producing output
  --help                 Show this help message

Output: JSON manifest with path, size_bytes, lines for each file.

Excluded directories: .git, node_modules, __pycache__, .venv, .tox,
  _build, dist, build, .eggs, *.egg-info, .artifacts, .claude
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project-root) PROJECT_ROOT="$2"; shift 2 ;;
        --output) OUTPUT="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        --help) usage ;;
        *) echo "Error: unknown option '$1'. Use --help for usage." >&2; exit 1 ;;
    esac
done

if [[ -z "$PROJECT_ROOT" ]]; then
    echo "Error: --project-root is required." >&2
    exit 1
fi

if [[ ! -d "$PROJECT_ROOT" ]]; then
    echo "Error: project root '$PROJECT_ROOT' does not exist." >&2
    exit 1
fi

EXCLUDE_DIRS=(
    .git node_modules __pycache__ .venv .tox _build dist build
    .eggs .artifacts .claude .mypy_cache .pytest_cache .ruff_cache
)

# 构建 find 排除参数
FIND_EXCLUDES=""
for d in "${EXCLUDE_DIRS[@]}"; do
    FIND_EXCLUDES="$FIND_EXCLUDES -path '*/$d' -prune -o"
done

if $DRY_RUN; then
    echo "[dry-run] Would scan: $PROJECT_ROOT"
    echo "[dry-run] Excluding: ${EXCLUDE_DIRS[*]}"
    # 统计文件数
    COUNT=$(eval "find '$PROJECT_ROOT' $FIND_EXCLUDES -type f -print" | wc -l)
    echo "[dry-run] Would find approximately $COUNT files"
    exit 0
fi

# 产出 manifest.json
python3 -c "
import json, os, subprocess

project_root = '$PROJECT_ROOT'
exclude_dirs = set('${EXCLUDE_DIRS[*]}'.split())

manifest = {
    'project_root': os.path.abspath(project_root),
    'files': [],
    'summary': {}
}

for root, dirs, files in os.walk(project_root):
    # 排除目录
    dirs[:] = [d for d in dirs if d not in exclude_dirs and not d.endswith('.egg-info')]

    for f in files:
        filepath = os.path.join(root, f)
        relpath = os.path.relpath(filepath, project_root)

        try:
            stat = os.stat(filepath)
            size = stat.st_size
        except:
            size = 0

        # 计算行数（只对文本文件）
        lines = 0
        try:
            with open(filepath, 'r', errors='ignore') as fh:
                lines = sum(1 for _ in fh)
        except:
            pass

        # 检测文件类型
        ext = os.path.splitext(f)[1].lower()

        manifest['files'].append({
            'path': relpath,
            'size_bytes': size,
            'lines': lines,
            'extension': ext
        })

# 统计
by_ext = {}
for f in manifest['files']:
    ext = f['extension'] or '(no ext)'
    by_ext[ext] = by_ext.get(ext, 0) + 1

manifest['summary'] = {
    'total_files': len(manifest['files']),
    'total_lines': sum(f['lines'] for f in manifest['files']),
    'by_extension': dict(sorted(by_ext.items(), key=lambda x: -x[1]))
}

# 按路径排序
manifest['files'].sort(key=lambda f: f['path'])

output = json.dumps(manifest, indent=2, ensure_ascii=False)
print(output)
" | if [[ -n "$OUTPUT" ]]; then
    cat > "$OUTPUT"
    echo "Manifest written to $OUTPUT ($(python3 -c "import json; print(json.load(open('$OUTPUT'))['summary']['total_files'])") files)" >&2
else
    cat
fi
