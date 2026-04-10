# dev-loop-skills

开发闭环 skill 包 — 7 个 skill 组成完整的测试驱动开发流水线。

## Skill 概览

| # | Skill | 阶段 | 功能 |
|---|-------|------|------|
| 0 | **project-builder** | Phase 0 — Bootstrap | 扫描代码仓库、跑全部测试、生成知识库、初始化 `.artifacts/` |
| 1 | **project-discussion-\*** | Phase 1 — Knowledge | 基于 `.artifacts/` 知识库回答项目问题（代码结构、模块关系、测试状态等） |
| 2 | **test-plan-generator** | Phase 2-3 — Plan | 从 code-diff / coverage-gap / eval-doc 生成结构化测试计划（TC-ID + 优先级） |
| 3 | **test-code-writer** | Phase 4 — Write | 将 confirmed test-plan 转为可运行的 pytest E2E 代码 |
| 4 | **test-runner** | Phase 5 — Execute | 执行 E2E 测试套件，生成报告（区分 new vs regression） |
| 5 | **feature-eval** | Phase 1,7 — Evaluate | simulate（探索功能想法）+ verify（记录 bug、创建 issue） |
| 6 | **artifact-registry** | Cross-phase | 管理 `.artifacts/` 目录 — 注册、查询、关联、追踪生命周期 |

## Phase 0-8 流程

```
Phase 0: Bootstrap ──────────── Skill 0 (project-builder)
  │  扫描代码 → 跑测试 → 生成 Skill 1 → 初始化 .artifacts/
  ▼
Phase 1: Simulate / Explore ── Skill 5 (feature-eval simulate)
  │  探索功能想法 → 产出 eval-doc
  ▼
Phase 2: Plan (from eval-doc) ─ Skill 2 (test-plan-generator)
  │  eval-doc → 结构化测试计划
  ▼
Phase 3: Plan (from code-diff) ─ Skill 2 (test-plan-generator)
  │  code-diff → 结构化测试计划
  ▼
Phase 4: Write Tests ────────── Skill 3 (test-code-writer)
  │  test-plan → pytest E2E 代码
  ▼
Phase 5: Run Tests ──────────── Skill 4 (test-runner)
  │  执行测试 → 生成报告
  ▼
Phase 6: Implement Feature ──── (标准编码，无特殊 skill)
  │
  ▼
Phase 7: Verify ─────────────── Skill 5 (feature-eval verify)
  │  对比 expected vs actual → 记录 bug → 创建 issue
  ▼
Phase 8: Feedback Loop
  ├──→ Phase 2 (需要新测试)
  └──→ Phase 6 (需要修复代码)
```

**跨阶段可用：** Skill 1 (Knowledge Q&A) 和 Skill 6 (Artifact Registry) 在任何阶段都可调用。

## 安装

### 方式 1：skill 目录引用

在 `~/.claude/settings.json` 中添加：

```json
{
  "skills": [
    "~/.claude/skills/dev-loop-skills/skills"
  ]
}
```

### 方式 2：作为 plugin（推荐）

将 `dev-loop-skills` 目录放在 `~/.claude/plugins/` 下，或在 `settings.json` 中注册：

```json
{
  "plugins": [
    "~/.claude/skills/dev-loop-skills"
  ]
}
```

## 使用

所有 skill 通过 Claude Code 的 `Skill` tool 调用：

```
# Bootstrap 新项目
Skill tool → "project-builder"

# 问项目问题
Skill tool → "project-discussion-zchat"

# 生成测试计划
Skill tool → "test-plan-generator"

# 写测试代码
Skill tool → "test-code-writer"

# 跑测试
Skill tool → "test-runner"

# 功能评估（simulate / verify）
Skill tool → "feature-eval"

# 管理 artifact
Skill tool → "artifact-registry"
```

路由 skill `using-dev-loop` 会自动判断用户意图并触发对应 skill。

## 目录结构

```
dev-loop-skills/
├── .claude-plugin/
│   └── plugin.json          # Plugin 注册信息
├── package.json             # 包元数据
├── README.md                # 本文件
└── skills/
    ├── using-dev-loop/      # 路由 skill（判断触发哪个 skill）
    ├── skill-0-project-builder/
    ├── skill-1-project-discussion-zchat/
    ├── skill-2-test-plan-generator/
    ├── skill-3-test-code-writer/
    ├── skill-4-test-runner/
    ├── skill-5-feature-eval/
    └── skill-6-artifact-registry/
```
