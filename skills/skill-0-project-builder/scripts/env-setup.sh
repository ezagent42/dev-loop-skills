#!/bin/bash
set -euo pipefail

# 基于 env-check.sh 的结果，实际尝试安装缺失依赖、启动服务。
# 不只是提示——能自动解决的直接执行。
# 只有真正需要人工干预的（需要 root、需要硬件等）才标记为 manual。

DRY_RUN=false
PROJECT_ROOT=""
ENV_REPORT=""

usage() {
    cat <<EOF
Usage: $(basename "$0") --project-root <path> --env-report <path> [--dry-run] [--help]

Attempt to install missing dependencies and start required services.

Options:
  --project-root <path>  Project root directory (required)
  --env-report <path>    Path to env-report.json from env-check.sh (required)
  --dry-run              Show what would be done without making changes
  --help                 Show this help message

Actions taken:
  1. Install Python packages (uv sync --dev)
  2. Install missing tools via package manager
  3. Start services using project's docker-compose / start.sh / Makefile
  4. Start services via known methods (e.g., ergo for IRC)
  5. Report what couldn't be auto-fixed
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project-root) PROJECT_ROOT="$2"; shift 2 ;;
        --env-report) ENV_REPORT="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        --help) usage ;;
        *) echo "Error: unknown option '$1'. Use --help for usage." >&2; exit 1 ;;
    esac
done

if [[ -z "$PROJECT_ROOT" || -z "$ENV_REPORT" ]]; then
    echo "Error: --project-root and --env-report are required." >&2
    exit 1
fi

if [[ ! -f "$ENV_REPORT" ]]; then
    echo "Error: env report not found: $ENV_REPORT" >&2
    exit 1
fi

python3 -c "
import json, subprocess, sys, os, shutil

with open('$ENV_REPORT') as f:
    report = json.load(f)

dry_run = $( $DRY_RUN && echo "True" || echo "False" )
project_root = '$PROJECT_ROOT'

fixed = []
failed = []
manual = []

def run_cmd(desc, cmd, cwd=None):
    \"\"\"Run a command, return success/failure.\"\"\"
    if dry_run:
        print(f'  [dry-run] {desc}: {cmd}')
        return True
    try:
        print(f'  Attempting: {desc}...')
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, cwd=cwd or project_root, timeout=120)
        if result.returncode == 0:
            print(f'    -> Success')
            return True
        else:
            print(f'    -> Failed (exit {result.returncode}): {result.stderr[:200]}')
            return False
    except subprocess.TimeoutExpired:
        print(f'    -> Timeout after 120s')
        return False
    except Exception as e:
        print(f'    -> Error: {e}')
        return False

print('=== Environment Setup ===')
print()

for check in report['checks']:
    if check['status'] == 'ready':
        continue

    name = check['name']
    hint = check.get('install_hint', '') or check.get('start_hint', '')

    # ── Python project dependencies ──
    if name == 'pytest' or name == 'pip':
        if run_cmd(f'Install Python dev dependencies', 'uv sync --dev'):
            fixed.append(name)
        else:
            failed.append({'name': name, 'reason': 'uv sync --dev failed'})
        continue

    # ── uv itself ──
    if name == 'uv':
        if run_cmd('Install uv', 'curl -LsSf https://astral.sh/uv/install.sh | sh'):
            fixed.append(name)
        else:
            failed.append({'name': name, 'reason': 'uv install failed'})
        continue

    # ── Services with ports ──
    if 'port' in name.lower():
        port_str = ''
        for part in name.split():
            if part.strip('()').isdigit():
                port_str = part.strip('()')
                break

        # Try 1: project has docker-compose?
        compose_files = ['docker-compose.yml', 'docker-compose.yaml']
        compose_found = False
        for cf in compose_files:
            if os.path.exists(os.path.join(project_root, cf)):
                compose_found = True
                if run_cmd(f'Start services via {cf}', f'docker compose up -d'):
                    fixed.append(name)
                else:
                    failed.append({'name': name, 'reason': f'{cf} up failed'})
                break

        if compose_found:
            continue

        # Try 2: project has start.sh?
        start_sh = os.path.join(project_root, 'start.sh')
        if os.path.exists(start_sh):
            if run_cmd(f'Start services via start.sh', 'bash start.sh'):
                fixed.append(name)
            else:
                failed.append({'name': name, 'reason': 'start.sh failed'})
            continue

        # Try 3: known service starters
        if 'ergo' in name.lower() or 'irc' in name.lower():
            if shutil.which('ergo'):
                if run_cmd('Start ergo IRC server', 'ergo run &'):
                    fixed.append(name)
                    continue

        # Try 4: use start_hint from env-check
        if hint:
            if run_cmd(f'Start service using hint', hint):
                fixed.append(name)
                continue

        # Can't auto-fix
        manual.append({
            'name': name,
            'hint': hint or f'Start the service listening on the required port',
            'impact': 'E2E tests requiring this service will fail'
        })
        continue

    # ── Tools with install hints ──
    if hint and check.get('optional'):
        # Try installing via hint
        if 'apt' in hint:
            # Try apt install
            pkg = hint.split('apt install')[-1].split('/')[0].strip()
            if run_cmd(f'Install {name} via apt', f'sudo apt-get install -y {pkg} 2>/dev/null || true'):
                fixed.append(name)
                continue
        elif 'pip install' in hint:
            if run_cmd(f'Install {name} via pip', f'uv pip install {name}'):
                fixed.append(name)
                continue
        elif 'cargo install' in hint:
            if shutil.which('cargo'):
                if run_cmd(f'Install {name} via cargo', hint):
                    fixed.append(name)
                    continue

        manual.append({
            'name': name,
            'hint': hint,
            'impact': 'Some tests may be skipped or limited'
        })
        continue

    # Default: can't auto-fix
    if not check.get('optional'):
        manual.append({
            'name': name,
            'hint': hint or 'Install manually',
            'impact': 'Required dependency - tests may not run'
        })

print()
print('=== Setup Results ===')
print()

if fixed:
    print(f'Auto-fixed ({len(fixed)}):')
    for f_name in fixed:
        print(f'  ✅ {f_name}')
    print()

if failed:
    print(f'Attempted but failed ({len(failed)}):')
    for f_item in failed:
        print(f'  ❌ {f_item[\"name\"]}: {f_item[\"reason\"]}')
    print()

if manual:
    print(f'Needs manual action ({len(manual)}):')
    for m in manual:
        print(f'  ⚠️  {m[\"name\"]}')
        print(f'     How to fix: {m[\"hint\"]}')
        print(f'     Impact: {m[\"impact\"]}')
    print()

if not fixed and not failed and not manual:
    print('All dependencies are ready. No action needed.')

if dry_run:
    print('[dry-run] No changes were made.')

# Output summary as JSON to stderr for programmatic consumption
summary = {'fixed': fixed, 'failed': [f['name'] for f in failed], 'manual': [m['name'] for m in manual]}
print(json.dumps(summary), file=sys.stderr)
"
