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

### 通过 marketplace 安装（推荐）

```bash
# 1. 注册 marketplace（一次性，告诉 Claude Code 去哪找 plugin）
/plugin marketplace add ezagent42/ezagent42

# 2. 安装 plugin（把代码下载到本地 cache）
/plugin install dev-loop-skills@ezagent42
```

### 通过项目 submodule 自动发现

如果项目已包含 `ezagent42-marketplace` submodule（如 zchat），clone 项目时 marketplace 会自动被发现：

```bash
git clone --recurse-submodules git@github.com:ezagent42/zchat.git
cd zchat
claude
# Claude Code 自动发现 marketplace，但仍需手动安装一次：
/plugin install dev-loop-skills@ezagent42
```

新项目也可以添加同样的 submodule：

```bash
git submodule add https://github.com/ezagent42/ezagent42.git ezagent42-marketplace
```

### 更新

```bash
/plugin update dev-loop-skills@ezagent42
```

## 使用

### 接入项目（每个项目一次）

在项目目录下对 Claude Code 说：

> bootstrap 这个项目

Skill 0 自动扫描代码、跑测试、生成 `.artifacts/` 和项目专属 Skill 1。

### 日常使用

说自然语言即可，路由 skill `using-dev-loop` 自动判断触发哪个 skill：

| 你说 | 触发 |
|------|------|
| "agent_manager 怎么工作的？" | Skill 1 — 项目知识问答 |
| "我想加一个 DM 功能，效果会怎样？" | Skill 5 simulate — 模拟分析 |
| "发现 bug：scoped_name 返回了双前缀" | Skill 5 verify — 记录 bug |
| "这是不是 bug？"（带着 eval-doc） | Skill 1 — 分流判断 |
| "生成测试计划" | Skill 2 — 从 code-diff / gap / eval-doc 生成 |
| "我改了代码，帮我生成 plan" | Skill 2 — 自动从 git diff 生成 code-diff 再生成 plan |
| "确认这个测试计划" | Skill 2 — draft → confirmed |
| "写测试代码" | Skill 3 — 从 confirmed plan 生成 pytest 代码 |
| "跑 E2E 测试" | Skill 4 — 执行 + 生成报告 |
| "这不是 bug，归档" | Skill 1 — archived + rejection_reason |
| "查看 artifact 状态" | Skill 6 — registry 查询 |

### 协作流程

- **产品需求讨论** → Skill 1（讨论需求）→ Skill 5 simulate（正式记录 eval-doc）→ Skill 2（生成 test-plan）
- **Bug 分流** → Skill 5 verify（记录 bug）→ Skill 1（分流判断）→ 确认是 bug 进入 Skill 2，不是则归档
- **完整测试闭环** → Skill 2（plan）→ Skill 3（write）→ Skill 4（run）

## 目录结构

```
dev-loop-skills/
├── .claude-plugin/
│   └── plugin.json          # Plugin 注册信息
├── package.json             # 包元数据
├── install.sh               # 安装脚本（备用）
├── README.md                # 本文件
└── skills/
    ├── using-dev-loop/      # 路由 skill（自动判断触发哪个 skill）
    ├── skill-0-project-builder/
    ├── skill-2-test-plan-generator/
    ├── skill-3-test-code-writer/
    ├── skill-4-test-runner/
    ├── skill-5-feature-eval/
    └── skill-6-artifact-registry/
```

注：Skill 1 (project-discussion-*) 由 Skill 0 bootstrap 时自动生成，是项目专属的，不在本包内。
