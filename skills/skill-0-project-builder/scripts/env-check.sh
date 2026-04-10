#!/bin/bash
set -euo pipefail

# 检查项目运行环境：语言、包管理器、外部服务、工具链。
# 特别关注 E2E 测试依赖——自动扫描测试文件中引用的端口和服务。
# 产出 env-report.json，标记每项为 ready/missing/optional。

DRY_RUN=false
PROJECT_ROOT=""
OUTPUT=""

usage() {
    cat <<EOF
Usage: $(basename "$0") --project-root <path> [--output <path>] [--dry-run] [--help]

Check project runtime environment and dependencies.

Options:
  --project-root <path>  Project root directory (required)
  --output <path>        Output path for env-report.json (default: stdout)
  --dry-run              Show what would be checked
  --help                 Show this help message

Checks: language runtimes, package managers, external services, tools.
Also scans test files for port/service references to detect E2E dependencies.
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

if $DRY_RUN; then
    echo "[dry-run] Would check environment for project at $PROJECT_ROOT"
    echo "[dry-run] Checks: runtimes, package managers, tools, project-detected ports/services"
    exit 0
fi

python3 -c "
import json, subprocess, os, re, glob

project_root = '$PROJECT_ROOT'
checks = []

def check_command(name, cmd, optional=False, install_hint=''):
    \"\"\"Check if a command exists and get its version.\"\"\"
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        version = result.stdout.strip().split('\n')[0] if result.stdout else result.stderr.strip().split('\n')[0]
        return {'name': name, 'status': 'ready', 'version': version[:100], 'optional': optional, 'install_hint': install_hint}
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return {'name': name, 'status': 'missing', 'version': None, 'optional': optional, 'install_hint': install_hint}

def check_port(name, port, optional=True, start_hint=''):
    \"\"\"Check if a TCP service is running.\"\"\"
    import socket
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(1)
            result = s.connect_ex(('127.0.0.1', port))
            if result == 0:
                return {'name': f'{name} (port {port})', 'status': 'ready', 'version': f'listening on {port}', 'optional': optional, 'start_hint': start_hint}
            else:
                return {'name': f'{name} (port {port})', 'status': 'missing', 'version': f'not listening on {port}', 'optional': optional, 'start_hint': start_hint}
    except:
        return {'name': f'{name} (port {port})', 'status': 'missing', 'version': None, 'optional': optional, 'start_hint': start_hint}

# ── Standard checks ──

checks.append(check_command('python3', ['python3', '--version']))
checks.append(check_command('node', ['node', '--version'], optional=True, install_hint='apt install nodejs / brew install node'))
checks.append(check_command('uv', ['uv', '--version'], optional=True, install_hint='curl -LsSf https://astral.sh/uv/install.sh | sh'))
checks.append(check_command('pip', ['pip', '--version'], optional=True))
checks.append(check_command('git', ['git', '--version']))
checks.append(check_command('pytest', ['python3', '-m', 'pytest', '--version'], optional=True, install_hint='uv sync --dev'))
checks.append(check_command('tmux', ['tmux', '-V'], optional=True, install_hint='apt install tmux / brew install tmux'))
checks.append(check_command('zellij', ['zellij', '--version'], optional=True, install_hint='cargo install zellij'))
checks.append(check_command('asciinema', ['asciinema', '--version'], optional=True, install_hint='pip install asciinema'))
checks.append(check_command('docker', ['docker', '--version'], optional=True, install_hint='https://docs.docker.com/get-docker/'))

# ── Project-aware: scan test files for port/service references ──

detected_ports = {}  # port -> {'name': ..., 'source': ..., 'start_hint': ...}

# Scan all Python test files for port references
test_patterns = [
    os.path.join(project_root, 'tests', '**', '*.py'),
    os.path.join(project_root, 'test', '**', '*.py'),
]

for pattern in test_patterns:
    for filepath in glob.glob(pattern, recursive=True):
        try:
            with open(filepath) as f:
                content = f.read()
        except:
            continue

        relpath = os.path.relpath(filepath, project_root)

        # Pattern 1: explicit port numbers in connect/socket calls
        for m in re.finditer(r'(?:port|PORT)\s*[=:]\s*(\d{2,5})', content):
            port = int(m.group(1))
            if 1024 < port < 65536 and port not in detected_ports:
                detected_ports[port] = {'name': f'service (detected in {relpath})', 'source': relpath}

        # Pattern 2: connect_ex/connect with port
        for m in re.finditer(r'connect(?:_ex)?\s*\(\s*\(?[\'\"]([\w.]+)[\'\"],\s*(\d+)', content):
            host, port = m.group(1), int(m.group(2))
            if port not in detected_ports:
                detected_ports[port] = {'name': f'service on {host} (detected in {relpath})', 'source': relpath}

        # Pattern 3: is_service_running or similar check functions
        for m in re.finditer(r'is_service_running\s*\(\s*[\'\"]([\w.]+)[\'\"],\s*(\d+)\s*\)', content):
            host, port = m.group(1), int(m.group(2))
            if port not in detected_ports:
                detected_ports[port] = {'name': f'service on {host} (detected in {relpath})', 'source': relpath}

        # Pattern 4: pytest.skip with port/server mentions
        for m in re.finditer(r'pytest\.skip\s*\(\s*[\"\'](.*?port\s*(\d+).*?)[\"\']', content, re.IGNORECASE):
            msg, port = m.group(1), int(m.group(2))
            if port not in detected_ports:
                detected_ports[port] = {'name': f'{msg.strip()} (detected in {relpath})', 'source': relpath}

# Scan for startup scripts / docker-compose for start hints
start_hints = {}
startup_files = {
    'docker-compose.yml': 'docker compose up -d',
    'docker-compose.yaml': 'docker compose up -d',
    'start.sh': 'bash start.sh',
    'Makefile': 'make start (check Makefile)',
}

for fname, hint in startup_files.items():
    fpath = os.path.join(project_root, fname)
    if os.path.exists(fpath):
        try:
            with open(fpath) as f:
                content = f.read()
            # Try to associate ports with startup method
            for port in detected_ports:
                if str(port) in content:
                    start_hints[port] = f'{hint} (references port {port} in {fname})'
        except:
            pass

# Also check README for service startup instructions
for readme in ['README.md', 'README.rst', 'README.txt']:
    rpath = os.path.join(project_root, readme)
    if os.path.exists(rpath):
        try:
            with open(rpath) as f:
                content = f.read()
            for port in detected_ports:
                if str(port) in content:
                    # Extract surrounding context
                    idx = content.find(str(port))
                    context = content[max(0,idx-100):idx+100].replace('\n', ' ').strip()
                    if port not in start_hints:
                        start_hints[port] = f'See {readme}: ...{context}...'
        except:
            pass

# Add detected port checks
for port, info in sorted(detected_ports.items()):
    hint = start_hints.get(port, '')
    checks.append(check_port(
        info['name'],
        port,
        optional=True,  # E2E deps are optional for unit tests to work
        start_hint=hint
    ))

# ── Project dependencies from pyproject.toml ──

pyproject = os.path.join(project_root, 'pyproject.toml')
project_deps = []
if os.path.exists(pyproject):
    with open(pyproject) as f:
        content = f.read()
    in_deps = False
    for line in content.split('\n'):
        if 'dependencies' in line and '=' in line:
            in_deps = True
            continue
        if in_deps:
            if line.strip().startswith(']'):
                in_deps = False
            elif line.strip().startswith('\"') or line.strip().startswith(\"'\"):
                dep = line.strip().strip('\"\\'').split('>=')[0].split('<')[0].split('==')[0].strip()
                if dep:
                    project_deps.append(dep)

report = {
    'project_root': os.path.abspath(project_root),
    'checks': checks,
    'detected_ports': {str(p): info for p, info in detected_ports.items()},
    'project_dependencies': project_deps,
    'summary': {
        'ready': sum(1 for c in checks if c['status'] == 'ready'),
        'missing_required': sum(1 for c in checks if c['status'] == 'missing' and not c.get('optional')),
        'missing_optional': sum(1 for c in checks if c['status'] == 'missing' and c.get('optional')),
        'total': len(checks)
    }
}

print(json.dumps(report, indent=2, ensure_ascii=False))
" | if [[ -n "$OUTPUT" ]]; then
    cat > "$OUTPUT"
    echo "Environment report written to $OUTPUT" >&2
else
    cat
fi
