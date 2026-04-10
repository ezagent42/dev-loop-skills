#!/bin/bash
set -euo pipefail

# 运行项目的全部测试，捕获完整输出作为基线。
# 自动检测测试框架（pytest / npm test / mix test 等）。

DRY_RUN=false
PROJECT_ROOT=""
OUTPUT=""

usage() {
    cat <<EOF
Usage: $(basename "$0") --project-root <path> [--output <path>] [--dry-run] [--help]

Run all project tests and capture results as a baseline.

Options:
  --project-root <path>  Project root directory (required)
  --output <path>        Output path for test-baseline.json (default: stdout)
  --dry-run              Show what test commands would be run
  --help                 Show this help message

Auto-detects test framework from project files (pyproject.toml, package.json, mix.exs).
Runs each test suite separately, captures exit code + stdout + stderr.
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

# 检测测试命令
detect_test_commands() {
    local root="$1"
    local commands=()

    # Python (pytest)
    if [[ -f "$root/pyproject.toml" ]] || [[ -f "$root/setup.py" ]] || [[ -f "$root/pytest.ini" ]]; then
        # 检测测试目录
        for test_dir in "tests/unit" "tests/integration" "tests/e2e" "tests" "test"; do
            if [[ -d "$root/$test_dir" ]]; then
                # 检查是否有 pytest marker 限制
                if [[ "$test_dir" == "tests/e2e" ]]; then
                    commands+=("uv run pytest $test_dir -v -m e2e||true")
                else
                    commands+=("uv run pytest $test_dir -v||true")
                fi
            fi
        done
        # 如果没有找到测试目录，尝试根目录
        if [[ ${#commands[@]} -eq 0 ]]; then
            commands+=("uv run pytest -v||true")
        fi
    fi

    # Node.js
    if [[ -f "$root/package.json" ]]; then
        commands+=("npm test||true")
    fi

    # Elixir
    if [[ -f "$root/mix.exs" ]]; then
        commands+=("mix test||true")
    fi

    # 子模块（检查子目录中的 pyproject.toml）
    for subdir in "$root"/*/; do
        if [[ -f "$subdir/pyproject.toml" ]] && [[ -d "$subdir/tests" ]]; then
            local subname=$(basename "$subdir")
            commands+=("cd $subname && uv run pytest tests/ -v||true")
        fi
    done

    printf '%s\n' "${commands[@]}"
}

COMMANDS=$(detect_test_commands "$PROJECT_ROOT")

if $DRY_RUN; then
    echo "[dry-run] Would run the following test commands in $PROJECT_ROOT:"
    echo "$COMMANDS" | while read -r cmd; do
        echo "  $cmd"
    done
    exit 0
fi

# 运行每个测试命令并捕获结果
python3 -c "
import json, subprocess, os, time

project_root = '$PROJECT_ROOT'
commands_raw = '''$COMMANDS'''
commands = [c.strip() for c in commands_raw.strip().split('\n') if c.strip()]

results = {
    'project_root': os.path.abspath(project_root),
    'timestamp': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
    'test_runs': [],
    'summary': {}
}

total_passed = 0
total_failed = 0
total_skipped = 0

for cmd in commands:
    # 去掉末尾的 ||true
    clean_cmd = cmd.replace('||true', '').strip()

    start = time.time()
    try:
        proc = subprocess.run(
            clean_cmd,
            shell=True,
            capture_output=True,
            text=True,
            cwd=project_root,
            timeout=300  # 5 min per test suite
        )
        duration = time.time() - start

        stdout = proc.stdout[-2000:] if len(proc.stdout) > 2000 else proc.stdout
        stderr = proc.stderr[-1000:] if len(proc.stderr) > 1000 else proc.stderr

        # 尝试从 pytest 输出中提取数量
        passed = failed = skipped = 0
        for line in proc.stdout.split('\n'):
            if 'passed' in line or 'failed' in line:
                import re
                m = re.search(r'(\d+) passed', line)
                if m: passed = int(m.group(1))
                m = re.search(r'(\d+) failed', line)
                if m: failed = int(m.group(1))
                m = re.search(r'(\d+) skipped', line)
                if m: skipped = int(m.group(1))

        total_passed += passed
        total_failed += failed
        total_skipped += skipped

        results['test_runs'].append({
            'command': clean_cmd,
            'exit_code': proc.returncode,
            'duration_seconds': round(duration, 1),
            'passed': passed,
            'failed': failed,
            'skipped': skipped,
            'stdout_tail': stdout,
            'stderr_tail': stderr
        })

    except subprocess.TimeoutExpired:
        results['test_runs'].append({
            'command': clean_cmd,
            'exit_code': -1,
            'duration_seconds': 300,
            'passed': 0,
            'failed': 0,
            'skipped': 0,
            'stdout_tail': '',
            'stderr_tail': 'TIMEOUT after 300 seconds'
        })

results['summary'] = {
    'total_suites': len(results['test_runs']),
    'total_passed': total_passed,
    'total_failed': total_failed,
    'total_skipped': total_skipped,
    'all_passed': total_failed == 0
}

print(json.dumps(results, indent=2, ensure_ascii=False))
" | if [[ -n "$OUTPUT" ]]; then
    cat > "$OUTPUT"
    echo "Test baseline written to $OUTPUT" >&2
else
    cat
fi
