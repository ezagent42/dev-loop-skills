# Artifact 交互命令参考

本文档列出 Skill 5 (feature-eval) 与 artifact-registry (Skill 6) 交互时使用的具体命令。

Skill 6 路径：`/home/yaosh/.claude/skills/dev-loop-skills/skills/skill-6-artifact-registry`

## 注册 eval-doc

```bash
bash <skill6-path>/scripts/register.sh \
  --project-root <project> \
  --type eval-doc \
  --name "<feature 名称>评估" \
  --producer skill-5 \
  --path .artifacts/eval-docs/eval-<feature>-<seq>.md \
  --status draft
```

## 注册 issue

```bash
bash <skill6-path>/scripts/register.sh \
  --project-root <project> \
  --type issue \
  --name "<feature 名称> issue" \
  --producer skill-5 \
  --path .artifacts/issues/issue-<feature>-<seq>.md \
  --status draft \
  --related "eval-doc-<seq>"
```

## 确认后更新状态

```bash
bash <skill6-path>/scripts/update-status.sh \
  --project-root <project> \
  --id eval-doc-<seq> \
  --status confirmed
```

**无 Skill 6 时**：直接写入 `.artifacts/` 约定目录并 git commit。
