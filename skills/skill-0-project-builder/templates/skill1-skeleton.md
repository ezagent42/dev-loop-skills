---
name: "project-discussion-{project_name}"
description: "项目知识问答 skill（{project_name}）。提供有实证支撑的项目知识服务——每个回答都附带测试输出或 file:line 引用。使用此 skill 当你需要了解 {project_name} 的代码结构、模块关系、测试状态，验证某个模块是否正常工作，处理 Skill 5 的反馈分流结果，或查询项目测试 pipeline 格式。即使只是简单的项目问题也应该触发此 skill。"
baseline_commit: {baseline_commit}
baseline_branch: {baseline_branch}
baseline_date: {generated_date}
---

# {project_name} 项目知识库

> 由 Skill 0 (project-builder) 于 {generated_date} 自动生成。
> 这是一个**行为引擎**——指导如何查询和回答，数据存储在 `.artifacts/` 中。

## 项目概览

- **项目根目录**：{project_root}
- **语言/框架**：{languages_and_frameworks}
- **测试框架**：{test_framework}
- **模块数**：{module_count}
- **Artifact 空间**：{project_root}/.artifacts/
- **Skill 6 可用**：{skill6_available}

## 问答流程

被问到项目相关问题时，按以下步骤回答。目标是**每个回答都有实证**，不编造。

### Step 0: 检测更新（drift detection）

每次回答前，跑一次 drift 检测（cheap，不会修改任何东西）：

```bash
bash scripts/self-update.sh --check
```

这会报告：
- 当前 HEAD 距离 SKILL.md `baseline_commit` frontmatter 多少 commit（drift）
- baseline 之后改过的 top-level paths（知道"哪些部分可能需要核查"）
- 是否有新模块目录尚未产生 module-report
- artifact 数量分类

基于 drift 数字决定本次 Q&A 的深度：

- **drift = 0**：用模块索引里的 file:line 直接答，不需要重跑 test-runner
- **drift 1-10**：改动过的 top-level path 涉及本次问题的话，重跑对应 test-runner；否则按缓存答
- **drift > 10 或涉及文件不在索引里**：先跑 `scripts/refresh-index.sh --module <name>` 重建该模块的索引，再答
- **drift > 50 或新模块目录出现**：考虑整体 Layer 2 刷新，见"自我演进机制"

同时查询 `.artifacts/` 中的 `code-diff` 和 `e2e-report`，找出比 baseline_date ({generated_date}) 更新的条目：
- **新 code-diff** → 读 diff 内容 → 用新代码作证据，不依赖索引快照
- **新 e2e-report** → 更新覆盖认知（之前标记 ❌ 的用户流程可能已变 ✅）

如果没有新 artifact 且 drift 可忽略，跳过此步骤直接进入 Step 1。

**异常处理**：如果索引里的文件路径不存在（文件已移动/重命名），运行 `scripts/refresh-index.sh --module <name>` 重建索引。如果 test-runner 执行失败（命令过时），同样触发刷新。

### Step 1: 解析问题 → 定位模块

查阅下方"模块索引"，找到问题涉及的模块。如果不确定涉及哪个模块，查"用户流程→模块映射"表。

如果问题涉及的模块不在索引中（可能是新增模块），运行 `scripts/refresh-index.sh --module <name>` 扫描并添加。

### Step 2: 读取代码

根据索引中的文件路径，用 Read 工具读取**当前**代码（不是 bootstrap 时的快照）。引用具体的 file:line。

如果 Step 0 已刷新了该模块，使用刷新后的路径。

### Step 3: 跑测试验证

运行对应的 test-runner 脚本，捕获**当前**输出作为证据。

```bash
bash scripts/test-{module_name}.sh
```

结果可能与索引中记录的基线不同（代码已变更），以实际运行结果为准。

### Step 4: 查询已有知识

查询 `.artifacts/` 中的相关 artifact，特别是：
- 被驳回的 eval-doc（status=archived）——已知边界/FAQ
- e2e-report——了解最近的测试结果和修复历史
- code-diff——了解最近的代码变更
- coverage-matrix——测试覆盖现状

{skill6_query_instructions}

### Step 5: 组织回答

回答格式：
1. 直接回答问题
2. 附上证据：file:line 引用 + 测试输出
3. 如果在 `.artifacts/` 中找到相关的被驳回 eval-doc，引用它作为已知边界

如果无法确认某个断言，标注为 `[unverified]` 而不是猜测。

### Step 6: 分流判断（自然延伸，非独立模式）

如果本次讨论涉及 `.artifacts/` 中的 eval-doc 或 issue（比如用户带着一个问题报告来讨论"这是不是 bug"），在 Step 5 回答后继续：

1. **明确提出分析结论**：基于代码证据和测试结果，给出判断（确认 bug / 不是 bug / 需要更多信息）
2. **询问人是否确认**结论
3. **人确认后执行对应操作**：

**结论是 bug**：
- Issue 保持 open
- 告知用户：eval-doc 将进入 Phase 3（Skill 2 生成 test-plan）

**结论不是 bug**：
```bash
# 关闭 GitHub issue
bash scripts/close-issue.sh --issue-url <url> --reason "<结论说明>"

# 更新 eval-doc 状态
{skill6_update_status_instructions}
```
同时在 eval-doc 文件的 frontmatter 中追加：
```yaml
rejection_reason: "<具体原因，引用代码证据>"
rejected_at: "{date}"
```
Git commit 追踪变更。

如果讨论**不涉及**任何 eval-doc/issue（只是普通的项目问题），则 Step 5 回答完即结束，不执行 Step 6。

---

## 自我演进机制（3 层）

Skill 1 通过**三层渐进式更新**保持知识最新：

### Layer 1：Drift 检测（每次 Q&A，cheap）

```bash
bash scripts/self-update.sh --check
```

在 Step 0 调用。只报告，不修改。核心机制是 SKILL.md frontmatter 里
的 `baseline_commit` —— 当前 HEAD 与它的距离就是 drift。

何时触发：**每次回答前**（Step 0 的一部分）。

### Layer 2：Refresh（手动，~1 分钟）

```bash
bash scripts/refresh-index.sh --all --with-baseline
```

重跑所有 test-runners + 重建 `test-baseline.json`。然后手动更新
SKILL.md 里的 Self-Verification Record 表和 frontmatter 的
`baseline_commit` / `baseline_date`。

何时触发：
- PR 刚合并，测试计数变了
- 已知 flaky envelope 改变
- 新 test-runner 加入

### Layer 3：完整 Re-bootstrap（手动，~30 分钟）

调用 Skill 0 (`dev-loop-skills:skill-0-project-builder`) 重做扫描、
环境、模块分析、测试基线，全部重新生成。

何时触发：
- 多模块重命名 / 合并 / 拆分
- 新增完全独立的模块（新 top-level language 加入）
- 切换到基础结构差异很大的分支（例如 v0.2 → main with big features）
- Eval 失败显示 Skill 1 答题质量下滑

### 知识层：artifact 积累（自动，不触发刷新）

除了上面三层"同步到代码"的机制，Skill 1 还靠 `.artifacts/` 里逐渐
积累的条目增强能力：

- **驳回结论** → eval-doc archived + rejection_reason → Step 4 查询时自动获取
- **Bug 修复历史** → eval-doc → test-plan → e2e-report 链条 → Step 4 可追溯完整修复过程
- **覆盖变化** → 新 e2e-report 更新 coverage-matrix → 覆盖缺口逐步缩小

这一层的变化**不需要**自身触发，每次 Step 4 查询时自然读到。

### 决策表

| 场景 | 动作 |
|---|---|
| 准备答任何问题 | Layer 1（自动）|
| 刚 merge 了一个 PR | Layer 2 |
| 切到差异很大的分支 | Layer 3 |
| 测试数变了但模块结构没变 | Layer 2 |
| 新源码目录出现（self-update.sh 报警） | Layer 3 或针对性 subagent 分析 |

---

## 模块索引

{module_index_table}

<!-- 格式：
| 模块 | 路径 | 职责 | 测试命令 | 测试结果 | 用户流程 |
|------|------|------|---------|---------|---------|
| agent | zchat/cli/agent_cmd.py | Agent 生命周期管理 | uv run pytest tests/unit/test_agent.py -v | 5/5 passed | 创建agent, 停止agent |
-->

## 详细模块描述

详见 `references/module-details.md`（从 `.artifacts/bootstrap/module-reports/*.json` 汇总生成）。

**生成规则**：Step 7 必须读取 `.artifacts/bootstrap/module-reports/` 下的所有 JSON 文件，汇总为 `references/module-details.md`。如果 module-reports 不存在，说明 Step 3 未正确持久化产出，必须补充。

{module_details}

<!-- 上面的 {module_details} 占位符用于在 SKILL.md 中放置模块摘要（每模块 2-3 行）。
     完整的接口/依赖/引用详情放在 references/module-details.md 中。
     每个模块在 references/module-details.md 中的格式：
### {module_name}

**职责**：（一句话，有 file:line 引用）

**关键接口**：
| 接口 | 位置 | 说明 |
|------|------|------|
| create(name, project) | agent_cmd.py:42 | 创建 agent |

**依赖关系**：
- → irc_manager（IRC 连接）
- → layout（Zellij tab 创建）

**对应用户流程**：
- 创建 agent：`zchat agent create <name>`
- 停止 agent：`zchat agent stop <name>`
-->

## 用户流程 → 模块映射

{user_flow_mapping}

<!-- 格式：
| 用户流程 | 操作步骤 | 涉及模块 | 入口 file:line | E2E 覆盖 | test-runner |
|---------|---------|---------|---------------|---------|------------|
| 创建 agent | zchat agent create helper | agent, irc, layout | agent_cmd.py:42 | ✅ | test-agent.sh |
| 私聊 DM | @agent 发送 DM | channel-server | (未实现) | ❌ | - |
-->

## 测试 Pipeline 信息

供 Skill 3 (test-code-writer) 查询，了解如何在此项目中追加 E2E 测试用例。

- **测试框架**：{test_framework}
- **E2E 测试目录**：{e2e_test_dir}
- **E2E conftest 位置**：{e2e_conftest_path}
- **已有 fixture 列表**：{fixture_list}
- **fixture 模式**：{fixture_pattern_description}
- **测试命名规范**：{naming_convention}
- **证据采集工具**：{evidence_tools}
- **证据采集方式**：{evidence_collection_method}
- **E2E 标记/marker**：{e2e_marker}
- **运行 E2E 的命令**：{e2e_run_command}

## Test Runners

每个模块对应一个 test-runner 脚本，封装了经过验证的测试命令。

{test_runner_list}

<!-- 格式：
| 脚本 | 模块 | 命令 | 基线结果 |
|------|------|------|---------|
| scripts/test-agent.sh | agent | uv run pytest tests/unit/test_agent.py -v | 5/5 passed |
| scripts/test-e2e.sh | (全局) | uv run pytest tests/e2e/ -v -m e2e | 11/13 passed, 2 skipped |
-->

## Artifact 交互

{skill6_artifact_section}

<!-- 根据 Skill 6 是否可用，生成两种内容之一：

### 有 Skill 6 时：
查询 artifact：
```bash
bash <skill6_path>/scripts/query.sh --project-root {project_root} --type eval-doc --status archived
```
注册新 artifact：
```bash
bash <skill6_path>/scripts/register.sh --project-root {project_root} --type eval-doc ...
```
更新状态：
```bash
bash <skill6_path>/scripts/update-status.sh --project-root {project_root} --id eval-doc-001 --status archived
```

### 无 Skill 6 时：
直接读写 .artifacts/ 目录：
- 查询：ls .artifacts/eval-docs/ 并读取 frontmatter 中的 status 字段
- 创建：直接写入 .artifacts/{type}/ 目录，含 YAML frontmatter
- 更新：直接编辑文件的 frontmatter
-->

## 自验证记录

Skill 1 生成后，所有 test-runner 已运行并与基线比对通过。

| test-runner | 基线结果 | 验证结果 | 匹配 |
|-------------|---------|---------|------|
{verification_table}

## 环境依赖

运行 E2E 测试所需的环境：

{env_dependencies}

<!-- 格式：
| 依赖 | 状态 | 说明 |
|------|------|------|
| ergo IRC server (port 6667) | 必需 | E2E 测试需要 IRC 连接 |
| zellij | 必需 | E2E 测试通过 zellij 操作终端 |
| asciinema | 可选 | pre-release 录制 |
-->
