---
name: artifact-registry
description: "Unified artifact space manager for the dev-loop pipeline. Manages .artifacts/ directory — registering, querying, linking, and tracking lifecycle of eval-docs, test-plans, test-diffs, e2e-reports, issues, code-diffs, and coverage-matrices. Use this skill whenever you produce a pipeline artifact, need to find an artifact from another skill, update artifact status, check pipeline progress, or initialize a project's artifact space. Also trigger when the user mentions 'registry', 'artifact', '.artifacts/', 'pipeline status', or asks what's pending/confirmed/executed."
---

# artifact-registry

> 统一的 artifact 空间管理器。维护开发流水线中所有中间产物的索引、状态追踪和交叉引用。

## 为什么需要这个 skill

dev-loop pipeline 有 7 个 skill，每个 skill 产出 artifact 并消费其他 skill 的 artifact。没有统一管理时，artifact 散落在约定目录中，无法快速查找、追溯关联链条或判断状态。artifact-registry 提供索引层——其他 skill 产出 artifact 后注册，消费前查询，状态变更时更新。

这个 skill 是可选增强：没有它时，其他 skill 直接读写 `.artifacts/` 约定目录也能工作。有了它，多了快速查询、交叉引用和生命周期追踪。

## 触发条件

**应该触发：**
- 任何 skill 产出了新 artifact（eval-doc、test-plan、e2e-report 等）
- 需要查找特定 artifact（"找到最新的 confirmed test-plan"）
- 需要更新 artifact 状态（draft → confirmed → executed → archived）
- 需要建立 artifact 间的关联（"这个 bug 对应哪个 test-plan"）
- 用户问 pipeline 状态（"当前有哪些待确认的 test-plan"）
- 初始化新项目的 artifact 空间

**不应该触发：**
- 纯代码开发，不涉及 artifact
- 运行测试本身（test-runner 的职责）
- 编写测试代码（test-code-writer 的职责）

## 输入

| 来源 | 内容 |
|------|------|
| 其他 skill 的产出 | artifact 文件（markdown + YAML frontmatter） |
| 用户指令 | 注册/查询/更新/关联操作 |
| 项目根目录 | `--project-root` 参数定位 `.artifacts/` |

## Artifact 类型

pipeline 中流转的 artifact 有 7 种，每种有明确的产出者和消费者：

| 类型 | 说明 | 产出者 | 消费者 |
|------|------|--------|--------|
| `eval-doc` | 预期 vs 实际对比文档 | Skill 5 (feature-eval) | Skill 2 (test-plan-generator) |
| `code-diff` | 代码改动摘要 | Phase 2 开发 | Skill 2 |
| `test-plan` | 测试计划 | Skill 2 | Skill 3 (test-code-writer) |
| `test-diff` | 追加的 E2E 用例清单 + diff | Skill 3 | Skill 4 (test-runner) |
| `e2e-report` | 测试报告（新增 + 回归） | Skill 4 | 人 / Skill 2 |
| `issue` | GitHub issue 引用 | Skill 5 | Skill 2 / Skill 1 |
| `coverage-matrix` | 覆盖矩阵（持续更新） | Skill 0 / Skill 4 | Skill 2 |

## Artifact 生命周期

每个 artifact 有 4 种状态，顺序流转：

```
draft → confirmed → executed → archived
```

- **draft** — 刚创建，待人 review（如 test-plan 待确认）
- **confirmed** — 人已确认，可被下游 skill 消费
- **executed** — 已被执行/处理（如 test-plan 的用例已写入套件）
- **archived** — 历史归档，不再活跃

状态流转由 `scripts/update-status.sh` 处理，每次变更记录时间戳并 git commit。

## 执行流程

### 1. 初始化 artifact 空间

首次接入项目时运行（通常由 Skill 0 调用）：

```bash
bash scripts/init-artifact-space.sh --project-root /path/to/project
```

创建 `.artifacts/` 目录结构、空的 `registry.json`、`.gitattributes`（图片走 git-lfs）。如果 `.artifacts/` 已存在则跳过，避免覆盖。

目录结构详见 `references/directory-structure.md`。

### 2. 注册 artifact

任何 skill 产出新 artifact 后调用：

```bash
bash scripts/register.sh \
  --project-root /path/to/project \
  --type eval-doc \
  --name "agent间私聊评估" \
  --producer skill-5 \
  --path .artifacts/eval-docs/eval-agent-dm-001.md \
  --status draft \
  --related "issue-001,test-plan-003"
```

脚本会：
1. 生成唯一 ID（格式 `{type}-{三位序号}`，如 `eval-doc-001`）
2. 写入 `registry.json`
3. `git add .artifacts/ && git commit`（commit message: `artifact: register {id} ({type})`）

`--related` 是可选的，传入逗号分隔的已有 artifact ID，建立双向关联。

### 3. 查询 artifact

其他 skill 消费 artifact 前查询：

```bash
# 按类型
bash scripts/query.sh --project-root /path/to/project --type test-plan

# 按状态
bash scripts/query.sh --project-root /path/to/project --status confirmed

# 组合查询
bash scripts/query.sh --project-root /path/to/project --type test-plan --status confirmed

# 按 ID
bash scripts/query.sh --project-root /path/to/project --id test-plan-001

# 全局概览：各类型各状态的数量统计
bash scripts/query.sh --project-root /path/to/project --summary
```

输出 JSON 格式，方便脚本消费。`--summary` 输出人可读的概览表。

### 4. 更新状态

```bash
bash scripts/update-status.sh \
  --project-root /path/to/project \
  --id test-plan-001 \
  --status confirmed
```

更新 `registry.json` 中对应条目的 `status` 和 `updated_at`，然后 git commit。

合法的状态流转：draft → confirmed → executed → archived。脚本验证流转方向，防止倒退（如 executed 不能回到 draft）。

### 5. 建立关联

```bash
bash scripts/link.sh \
  --project-root /path/to/project \
  --from eval-doc-001 \
  --to test-plan-003
```

双向更新两个 artifact 的 `related_ids` 字段。用于追溯链条（如从 bug issue 追到 test-plan 再到 e2e-report）。

## 输出

### registry.json 结构

```json
{
  "version": 1,
  "artifacts": [
    {
      "id": "eval-doc-001",
      "name": "agent间私聊评估",
      "type": "eval-doc",
      "status": "draft",
      "producer": "skill-5",
      "consumers": [],
      "path": ".artifacts/eval-docs/eval-agent-dm-001.md",
      "created_at": "2026-04-09T12:00:00Z",
      "updated_at": "2026-04-09T12:00:00Z",
      "related_ids": ["test-plan-003", "issue-012"]
    }
  ]
}
```

完整 schema 见 `schema/registry-schema.json`。

### Artifact 文件格式

所有 artifact 使用 markdown，头部包含 YAML frontmatter：

```markdown
---
type: eval-doc
id: eval-doc-001
status: draft
producer: skill-5
created_at: "2026-04-09"
updated_at: "2026-04-09"
related:
  - test-plan-003
  - issue-012
evidence: []
---

# 文档正文
...
```

e2e-report 的 `evidence` 字段引用证据文件的原始路径（不搬运文件）：

```yaml
evidence:
  - path: tests/pre_release/walkthrough-20260409-163200.cast
    type: asciinema
  - path: tests/e2e/captures/phase1-weechat.txt
    type: terminal-capture
```

### Git 集成

- 每次注册/更新后自动 `git add .artifacts/ && git commit`
- `.gitattributes` 配置：`*.png`、`*.gif`、`*.cast` 走 git-lfs
- Commit message 格式：`artifact: {action} {id} ({type})`

## 配套脚本说明

| 脚本 | 用途 | 关键参数 |
|------|------|----------|
| `scripts/init-artifact-space.sh` | 初始化 `.artifacts/` + git-lfs | `--project-root` |
| `scripts/register.sh` | 注册新 artifact | `--type --name --producer --path --status [--related]` |
| `scripts/query.sh` | 查询 artifact | `--type --status --id --summary` |
| `scripts/update-status.sh` | 更新状态 | `--id --status` |
| `scripts/link.sh` | 建立双向关联 | `--from --to` |
| `scripts/self-test.sh` | 验证所有脚本正常工作 | `--dry-run` |

所有脚本共同规范：
- `#!/bin/bash` + `set -euo pipefail`
- 支持 `--help`（用法说明）和 `--dry-run`（验证逻辑但不产生副作用）
- 路径通过 `--project-root` 参数传入，不硬编码
- 错误时输出有意义的错误信息并返回非零退出码

## .artifacts/ 目录结构

详见 `references/directory-structure.md`。概览：

```
.artifacts/
├── registry.json
├── eval-docs/
├── code-diffs/
├── test-plans/
├── test-diffs/
├── e2e-reports/
│   └── report-{id}/
│       └── report.md
├── issues/
└── coverage/
```

e2e-report 每个 report 一个子目录，因为可能包含多个关联文件。证据文件保留在测试脚本的原始输出位置，report 中通过 `evidence` 字段引用路径。
