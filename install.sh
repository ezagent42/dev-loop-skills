#!/bin/bash
set -euo pipefail

# dev-loop-skills 安装脚本
# 用法: bash <(curl -s https://raw.githubusercontent.com/ezagent42/dev-loop-skills/main/install.sh)
# 或:   bash install.sh

REPO_URL="git@github.com:ezagent42/dev-loop-skills.git"
INSTALL_DIR="$HOME/.claude/plugins/dev-loop-skills"
SETTINGS="$HOME/.claude/settings.json"

echo "=== dev-loop-skills installer ==="

# 1. Clone 或 pull
if [ -d "$INSTALL_DIR/.git" ]; then
    echo "已存在，更新中..."
    git -C "$INSTALL_DIR" pull --ff-only
else
    echo "安装到 $INSTALL_DIR ..."
    mkdir -p "$(dirname "$INSTALL_DIR")"
    git clone "$REPO_URL" "$INSTALL_DIR"
fi

# 2. 注册 plugin 到 settings.json（如果还没注册）
if [ ! -f "$SETTINGS" ]; then
    echo '{}' > "$SETTINGS"
fi

# 检查是否已注册
if grep -q 'dev-loop-skills' "$SETTINGS" 2>/dev/null; then
    echo "plugin 已在 settings.json 中注册"
else
    echo "注册 plugin 到 settings.json ..."
    # 用 python 安全地修改 JSON
    python3 -c "
import json, pathlib
p = pathlib.Path('$SETTINGS')
d = json.loads(p.read_text()) if p.stat().st_size > 0 else {}
hooks = d.setdefault('hooks', {})
# 添加 SessionStart hook 实现自动更新
starts = hooks.setdefault('SessionStart', [])
update_cmd = 'git -C $INSTALL_DIR pull --ff-only 2>/dev/null || true'
if not any(update_cmd in str(h) for h in starts):
    starts.append({
        'type': 'command',
        'command': update_cmd
    })
p.write_text(json.dumps(d, indent=2, ensure_ascii=False))
print('已添加 SessionStart 自动更新 hook')
"
fi

# 3. 验证安装
echo ""
echo "=== 安装完成 ==="
echo "路径: $INSTALL_DIR"
echo "版本: $(cat "$INSTALL_DIR/package.json" | python3 -c "import sys,json;print(json.load(sys.stdin)['version'])" 2>/dev/null || echo unknown)"
echo ""
echo "自动更新: 每次启动 Claude Code 时自动 git pull"
echo ""
echo "Skill 列表:"
for d in "$INSTALL_DIR"/skills/skill-*/; do
    name=$(basename "$d" | sed 's/skill-[0-9]-//')
    echo "  - $name"
done
echo "  - using-dev-loop (路由)"
echo ""
echo "使用方式: 在 Claude Code 中说 '生成测试计划' / 'run e2e' / 'simulate' 等"
