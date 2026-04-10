# Artifact 交互命令参考

本文档列出 Skill 2 (test-plan-generator) 与 artifact-registry (Skill 6) 交互时使用的具体命令。

Skill 6 路径：`/home/yaosh/.claude/skills/dev-loop-skills/skills/skill-6-artifact-registry`

## 查询 artifact

```bash
SKILL6_DIR="/home/yaosh/.claude/skills/dev-loop-skills/skills/skill-6-artifact-registry"

# 获取最新的 confirmed code-diff
bash "$SKILL6_DIR/scripts/query.sh" \
  --project-root "$PROJECT_ROOT" --type code-diff --status confirmed

# 获取当前 coverage-matrix
bash "$SKILL6_DIR/scripts/query.sh" \
  --project-root "$PROJECT_ROOT" --type coverage-matrix

# 获取待处理的 eval-doc
bash "$SKILL6_DIR/scripts/query.sh" \
  --project-root "$PROJECT_ROOT" --type eval-doc --status confirmed

# 获取未关闭的 issue
bash "$SKILL6_DIR/scripts/query.sh" \
  --project-root "$PROJECT_ROOT" --type issue --status confirmed
```

## 收集输入 artifact（Step 1 批量查询）

```bash
SKILL6_DIR="/home/yaosh/.claude/skills/dev-loop-skills/skills/skill-6-artifact-registry"

# 查询所有输入来源
CODE_DIFFS=$(bash "$SKILL6_DIR/scripts/query.sh" \
  --project-root "$PROJECT_ROOT" --type code-diff --status confirmed)
COVERAGE=$(bash "$SKILL6_DIR/scripts/query.sh" \
  --project-root "$PROJECT_ROOT" --type coverage-matrix)
EVAL_DOCS=$(bash "$SKILL6_DIR/scripts/query.sh" \
  --project-root "$PROJECT_ROOT" --type eval-doc --status confirmed)
ISSUES=$(bash "$SKILL6_DIR/scripts/query.sh" \
  --project-root "$PROJECT_ROOT" --type issue --status confirmed)
```

## 注册 test-plan artifact

```bash
SKILL6_DIR="/home/yaosh/.claude/skills/dev-loop-skills/skills/skill-6-artifact-registry"

PLAN_ID=$(bash "$SKILL6_DIR/scripts/register.sh" \
  --project-root "$PROJECT_ROOT" \
  --type test-plan \
  --name "$PLAN_TITLE" \
  --producer skill-2 \
  --path ".artifacts/test-plans/$PLAN_FILENAME" \
  --status draft \
  --related "$RELATED_IDS")
```

`$RELATED_IDS` 是逗号分隔的输入 artifact ID（code-diff-001,coverage-matrix-001 等），建立可追溯的关联链。

## 更新状态

```bash
bash "$SKILL6_DIR/scripts/update-status.sh" \
  --project-root "$PROJECT_ROOT" \
  --id "$PLAN_ID" \
  --status confirmed
```

## 下游查询（Skill 3 消费 test-plan）

```bash
bash "$SKILL6_DIR/scripts/query.sh" \
  --project-root "$PROJECT_ROOT" --type test-plan --status confirmed
```
