# Artifact 交互命令参考

本文档列出 Skill 3 (test-code-writer) 与 artifact-registry (Skill 6) 交互时使用的具体命令。

Skill 6 路径：`/home/yaosh/.claude/skills/artifact-registry`

## 查询 confirmed test-plan

```bash
bash /home/yaosh/.claude/skills/artifact-registry/scripts/query.sh \
  --project-root <project-root> --type test-plan --status confirmed
```

## 注册 test-diff artifact

```bash
bash /home/yaosh/.claude/skills/artifact-registry/scripts/register.sh \
  --project-root <project-root> \
  --type test-diff \
  --name "<brief description>" \
  --producer skill-3 \
  --path .artifacts/test-diffs/test-diff-NNN.md \
  --status draft \
  --related "<test-plan-id>"
```

## 更新 test-plan 状态为 executed

```bash
bash /home/yaosh/.claude/skills/artifact-registry/scripts/update-status.sh \
  --project-root <project-root> \
  --id <test-plan-id> \
  --status executed
```
