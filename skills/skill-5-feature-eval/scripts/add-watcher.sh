#!/bin/bash
set -euo pipefail

# 为 GitHub issue 添加 watcher（通过 @mention 在评论中通知）。
# GitHub API 没有原生 "watcher" 概念用于 issue，
# 通过添加评论 @mention 用户来实现通知。
# 需要 gh CLI 并已登录。

DRY_RUN=false
ISSUE_URL=""
WATCHER=""

usage() {
    cat <<EOF
Usage: $(basename "$0") --issue-url <url> --watcher <username> [--dry-run] [--help]

Add a watcher to a GitHub issue by @mentioning them in a comment.

Required:
  --issue-url <url>      Full GitHub issue URL
                         (e.g. https://github.com/owner/repo/issues/123)
  --watcher <username>   GitHub username to notify (without @)

Optional:
  --dry-run              Show what would be done without making changes
  --help                 Show this help message

Note:
  GitHub does not have a native "watch issue" API. This script adds a comment
  that @mentions the user, which subscribes them to the issue's notifications.

Prerequisites:
  - gh CLI installed and authenticated (gh auth status)
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --issue-url) ISSUE_URL="$2"; shift 2 ;;
        --watcher) WATCHER="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        --help) usage ;;
        *) echo "Error: unknown option '$1'. Use --help for usage." >&2; exit 1 ;;
    esac
done

# 参数验证
if [[ -z "$ISSUE_URL" ]]; then
    echo "Error: --issue-url is required." >&2
    exit 1
fi

if [[ -z "$WATCHER" ]]; then
    echo "Error: --watcher is required." >&2
    exit 1
fi

# 验证 URL 格式
if [[ ! "$ISSUE_URL" =~ ^https://github\.com/.+/.+/issues/[0-9]+$ ]]; then
    echo "Error: invalid issue URL format. Expected: https://github.com/owner/repo/issues/NUMBER" >&2
    exit 1
fi

# 检查 gh CLI
if ! command -v gh &> /dev/null; then
    echo "Error: gh CLI not found. Install from https://cli.github.com/" >&2
    exit 1
fi

# 去掉 @ 前缀（如果用户带了 @）
WATCHER="${WATCHER#@}"

COMMENT="Adding @${WATCHER} as watcher for this issue.

_Auto-added by feature-eval (skill-5)_"

if $DRY_RUN; then
    echo "[dry-run] Would add watcher to issue:"
    echo "  Issue: $ISSUE_URL"
    echo "  Watcher: @$WATCHER"
    echo "[dry-run] Would run: gh issue comment $ISSUE_URL --body <comment>"
    exit 0
fi

# 添加评论
gh issue comment "$ISSUE_URL" --body "$COMMENT"

echo "Added @$WATCHER as watcher on $ISSUE_URL"
