# Artifact 交互命令参考

本文档列出 Skill 4 (test-runner) 与 artifact-registry (Skill 6) 交互时使用的具体命令。

Skill 6 路径：`/home/yaosh/.claude/skills/artifact-registry`

## 注册 e2e-report

```bash
SKILL6_PATH="/home/yaosh/.claude/skills/artifact-registry"

bash "$SKILL6_PATH/scripts/register.sh" \
  --project-root /path/to/project \
  --type e2e-report \
  --name "E2E report for {feature}" \
  --producer skill-4 \
  --path ".artifacts/e2e-reports/report-{name}-{seq}/report.md" \
  --status executed \
  --related "test-diff-xxx"
```

如果 Skill 6 不可用，直接写入报告文件并 `git add && git commit`。

## 更新 coverage-matrix 状态

如需更新 coverage-matrix artifact 状态：

```bash
bash "$SKILL6_PATH/scripts/update-status.sh" \
  --project-root /path/to/project \
  --id <coverage-matrix-id> \
  --status <new-status>
```
