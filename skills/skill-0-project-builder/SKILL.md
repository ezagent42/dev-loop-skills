---
name: project-builder
description: "Pipeline bootstrapper that converts a 60%+ codebase into a working dev-loop. Use this skill when onboarding a new project, setting up the dev-loop pipeline, bootstrapping a project for testing, or when the user says 'bootstrap', 'onboard project', 'set up dev-loop', 'generate skill 1', 'scan project', or wants to establish a testing baseline for an existing codebase."
---

# project-builder

> 将一个 60%+ 的代码仓库转化为可运转的开发闭环：扫描全部代码、跑全部测试、生成 Skill 1、建立 artifact 空间。

## 为什么需要这个 skill

接手一个已有项目后，需要完整理解代码结构、测试现状和覆盖缺口，才能有效推进开发。手动做这些耗时且容易遗漏。project-builder 通过脚本枚举 + subagent 并行分析，保证不遗漏任何文件，不编造任何结论——每个断言都有 file:line 或测试输出作为证据。

最终产出的 Skill 1 可以分发给任何新人/新 session，让他们立即获得有实证支撑的项目知识。

## 触发条件

**应该触发：**
- 接手新项目，需要建立开发闭环
- 用户说"bootstrap"、"接入项目"、"扫描项目"、"生成 Skill 1"
- 需要建立测试基线或覆盖矩阵

**不应该触发：**
- 日常开发、写代码、修 bug
- 运行已有测试（那是 Skill 4 的职责）
- 已经有 Skill 1 且不需要重新生成

## 输入

| 来源 | 内容 |
|------|------|
| 用户 | 项目根目录路径 |
| 用户（可选） | 项目简要描述、主要语言、已知的外部依赖 |

## 执行流程

整个 bootstrap 分 8 步。每步完成后报告进度，失败时给出明确原因。

### Step 1: 扫描项目文件

运行 `scripts/scan-project.sh` 生成 manifest：

```bash
bash scripts/scan-project.sh --project-root /path/to/project
```

产出 `manifest.json`：项目中所有源文件的路径、大小、行数。这是后续所有步骤的基础——脚本枚举，不是 LLM 猜测。

### Step 2: 检查运行环境

运行 `scripts/env-check.sh` 检查依赖：

```bash
bash scripts/env-check.sh --project-root /path/to/project --output env-report.json
```

检查重点（**特别关注 E2E 测试依赖**）：
- 语言运行时、包管理器
- **外部服务**（IRC server、数据库、消息队列等——E2E 测试通常依赖这些）
- **终端工具**（zellij、tmux、asciinema——操作 E2E 需要这些采集证据）
- **端口占用**（E2E 测试需要的服务端口是否在线）

产出 `env-report.json`，每项标记为：
- **ready** — 就绪
- **missing-hard** — 缺失且为硬依赖（测试无法执行），必须在 Step 2.5 修复
- **missing-soft** — 缺失但为软依赖（不影响测试执行），可标注跳过

**如何判断 hard 还是 soft**：如果缺少这个依赖会导致任何测试 ERROR 或因环境原因 skip，就是 hard。E2E 测试所需的外部服务（IRC server、终端复用器等）通常是 hard dependency。仅影响可选功能的（如 asciinema 录制）是 soft。

### Step 2.5: 尝试自动配置环境

运行 `scripts/env-setup.sh` 尝试修复缺失依赖：

```bash
bash scripts/env-setup.sh --project-root /path/to/project --env-report env-report.json
```

能自动解决的（Python 包、uv 安装、启动服务等）直接处理。

**hard dependency 处理**：必须全部解决才能继续。如果自动修复失败，暂停 bootstrap 并明确告诉用户需要手动处理什么、为什么必须处理。不能跳过 hard dependency 继续执行——否则后续测试会因环境问题 ERROR，产出的 Skill 1 基线数据不可靠。

**soft dependency 处理**：无法自动解决的标注原因，不阻断流程。

### Step 3: 按模块并行分析（subagent 架构）

这是核心步骤。根据 manifest 将文件按目录分组为模块，然后为每个模块 spawn 一个 subagent。

**为什么用 subagent**：每个 subagent 有独立的上下文窗口，可以完整读取该模块的全部文件，不会因为上下文不够而跳过或概括。多个 subagent 并行运行，加速分析。

**每个 subagent 的任务**（详见 `references/subagent-prompt.md`）：
1. 读取该模块的**全部**文件（manifest 中列出的，逐个读完）
2. 为每个文件记录：关键函数/类、公开接口、依赖关系
3. 识别该模块对应的测试文件
4. 运行该模块的测试，捕获原始输出（exit code + stdout + stderr）
5. 产出 `module-report.json`：结构化的模块描述 + 测试结果 + file:line 引用

**产出持久化**：每个 subagent 必须将 module-report.json 写入 `.artifacts/bootstrap/module-reports/{module_name}.json`。主 agent 在所有 subagent 完成后：
1. 创建 `.artifacts/bootstrap/module-reports/` 目录
2. 将每个 subagent 返回的 JSON 保存为独立文件（如果 subagent 未直接写盘，主 agent 从返回结果中提取并写入）
3. 比对 manifest 确认每个文件都被某个 subagent 处理过，有遗漏则补充分析
4. 这些文件在 Step 7 用于生成 `references/module-details.md`，也作为 bootstrap 的永久记录

### Step 4: 运行完整测试基线

运行 `scripts/run-full-tests.sh` 执行项目的所有测试：

```bash
bash scripts/run-full-tests.sh --project-root /path/to/project
```

捕获完整输出作为基线。区分：
- **passed** — 测试通过
- **failed** — 代码 bug 导致测试失败（可接受，记录到 coverage-matrix）

**不可接受的结果**：
- **error (env)** — 因环境缺失导致测试无法执行
- **skipped (env)** — 因依赖缺失跳过

如果出现 error 或 skip 且原因是环境/依赖问题（不是代码层面的 pytest.skip），必须：
1. 诊断具体原因（哪个依赖缺失、哪个服务没启动、哪个端口不通）
2. 回到 Step 2.5 修复环境
3. 重新运行受影响的测试套件
4. 循环直到所有测试都正常执行完毕（passed 或 failed，不能有环境性的 error/skip）

这样做是因为 Skill 1 的基线必须反映**代码的真实测试状态**，而不是被环境问题污染的数据。一个 test fail 说明代码有 bug（有价值的信息），一个 test error 说明环境没搭好（没有信息量）。

这个基线用于后续 Skill 1 自验证。

### Step 5: 生成覆盖矩阵

基于 Step 3 的模块分析和 Step 4 的测试结果，生成 `coverage-matrix.md`：

三层覆盖：
- **代码测试覆盖**：哪些模块有单元/集成测试
- **操作 E2E 覆盖**：哪些用户流程有操作级 E2E 测试（通常初始大面积空白）
- **soft-dependency 受限覆盖**：因 soft dependency 缺失而无法运行的测试（如 pre-release 录制需要 asciinema）。注意：Step 4 已确保所有 hard dependency 的测试正常执行，此层仅记录 soft dependency 的影响

覆盖矩阵格式详见 `references/coverage-matrix-format.md`。

### Step 6: 初始化 artifact 空间

检测 Skill 6 (artifact-registry) 是否可用，然后分路径处理：

**有 Skill 6 时**：

```bash
# 初始化
bash <skill6-path>/scripts/init-artifact-space.sh --project-root /path/to/project

# 将 coverage-matrix 写入 .artifacts/coverage/coverage-matrix.md
# 然后注册到 registry
bash <skill6-path>/scripts/register.sh \
  --project-root /path/to/project \
  --type coverage-matrix \
  --name "初始覆盖矩阵" \
  --producer skill-0 \
  --path .artifacts/coverage/coverage-matrix.md \
  --status draft
```

**无 Skill 6 时**：

```bash
bash scripts/init-artifact-space.sh --project-root /path/to/project
```

Then write coverage-matrix directly to `.artifacts/coverage/` and commit.

生成 Skill 1 时需要记录 Skill 6 的可用状态和路径，以便 Skill 1 知道如何与 artifact 空间交互。

### Step 6.5: Bootstrap 完成性验证

在生成 Skill 1 之前，运行 `scripts/verify-bootstrap.sh` 检查所有前置步骤的产出是否完整：

```bash
bash scripts/verify-bootstrap.sh --project-root /path/to/project
```

这个脚本会检查 manifest、env-report、module-reports、测试执行证据、coverage-matrix、artifact 空间等 26 个检查项。任何 BLOCKING 级别的失败都必须修复后才能继续——它确保 Skill 1 的数据来源完整可靠，不会因为前面跳过了某个步骤而产出不完整的 Skill 1。

### Step 7: 生成 Skill 1

Skill 1 是一个**轻量行为引擎**——行为指令在 SKILL.md 中，数据在 `.artifacts/` 中。不嵌入大量内容到 SKILL.md。

生成时遵循 skill-creator 的写作指导：
- SKILL.md **< 500 行**，超出部分放 references/
- Description 要 **"pushy"**——明确列出触发场景，确保该触发时触发
- 用**解释 why** 代替堆砌 MUST/ALWAYS
- 用**示例**说明预期行为

1. 读取 `templates/skill1-skeleton.md`
2. 填入项目特定数据（来自 module-report.json 汇总）：
   - **模块索引**：模块→路径→职责→测试命令→结果→用户流程
   - **用户流程映射**：流程→操作步骤→模块→入口 file:line→E2E 覆盖状态
   - **测试 pipeline 信息**：框架、E2E 目录、fixture 模式、命名规范、证据采集方式（供 Skill 3 查询）
   - **环境依赖**：E2E 测试所需的外部服务和工具
3. 填入 Skill 6 交互指令：
   - 有 Skill 6：填入具体的 query/register/update-status 命令路径
   - 无 Skill 6：填入直接读写 `.artifacts/` 的指导
4. 为每个模块生成 `scripts/test-{module}.sh`（封装 Step 4 中验证通过的测试命令）
5. 从 `templates/` 复制通用脚本到 Skill 1 的 `scripts/`：
   - `self-update.sh`（drift 检测，供 Step 0 调用）
   - `refresh-index.sh`（Layer 2 refresh）
   - `close-issue.sh`（Step 6 triage rejection 关 GH issue 用）
6. **填入 SKILL.md frontmatter**：
   - `baseline_commit`: 当前 HEAD 的短 SHA（`git rev-parse --short HEAD`）
   - `baseline_branch`: 当前分支名（`git rev-parse --abbrev-ref HEAD`）
   - `baseline_date`: 今天日期（YYYY-MM-DD）
7. 输出完整的 Skill 1 目录：

```
project-discussion-{name}/
├── SKILL.md              # 行为引擎（带 baseline_commit frontmatter）
├── references/
│   └── module-details.md # 从 module-reports/*.json 汇总
└── scripts/
    ├── test-auth.sh      # 每个模块一个 test-runner
    ├── test-agent.sh
    ├── test-e2e.sh       # 全局 E2E runner
    ├── self-update.sh    # drift 检测（Layer 1，Step 0 用）
    ├── refresh-index.sh  # 测试基线刷新（Layer 2）
    └── close-issue.sh    # GH issue 关闭（Step 6 用）
```

**引用制**：模块索引中每行必须有 file:line 引用或测试命令输出。不允许未验证的描述。

**引用完整性检查**：SKILL.md 生成后，扫描文件中所有对 `references/`、`scripts/` 的引用路径，验证每个被引用的文件都实际存在。特别注意：
- `references/module-details.md` — 必须从 Step 3 持久化的 module-report.json 文件汇总生成
- 每个 `scripts/test-*.sh` — 必须实际生成并可执行
- `scripts/self-update.sh`、`scripts/refresh-index.sh`、`scripts/close-issue.sh` — 必须从 `templates/` 拷过来并 `chmod +x`
- `baseline_commit` frontmatter — 必须存在且是有效的 git 短 SHA
- 引用了不存在的文件 → 要么生成该文件，要么删除引用。不能留下死链接。

**Skill 1 必须包含的行为指令**（检查清单）：
- [ ] 问答流程：问题→定位模块→读代码→跑测试→证据回答
- [ ] Step 0 调用 `scripts/self-update.sh --check` 做 drift 检测
- [ ] 反馈处理：接收 Skill 5 驳回结论→更新 eval-doc 状态为 archived→追加 rejection_reason
- [ ] 自我演进：3 层更新机制（Layer 1 自动 / Layer 2 refresh / Layer 3 rebootstrap）
- [ ] 测试 pipeline：供 Skill 3 查询的完整信息
- [ ] Artifact 交互：with/without Skill 6 两种路径
- [ ] 环境依赖：E2E 测试所需的外部服务列表

### Step 7.5: 生成 bootstrap 执行报告

整个 bootstrap 过程中遇到的问题、决策和解决方案必须记录为结构化报告。

1. 读取 `templates/bootstrap-report.md` 获取报告模板
2. 填入本次 bootstrap 的实际数据（环境问题、测试结果、覆盖分析、决策记录）
3. 写入 `.artifacts/bootstrap/bootstrap-report.md`
4. 注册到 artifact registry（如有 Skill 6）

这个报告是 Skill 1 的"出生证明"——后续有人问"为什么 X 测试失败"，Skill 1 可以引用此报告回答。

### Step 8: 自验证

生成 Skill 1 后立即验证两方面：

**8a. Test-runner 基线比对**：

1. 运行 Skill 1 的**每一个** test-runner 脚本（不是抽查几个，是全部）
2. 比对输出与 Step 4 的基线
3. 如果结果不一致 → 定位差异 → 修正 Skill 1 → 重新验证
4. **立即将实际运行结果填入 SKILL.md 的自验证记录表**——不能留"待验证"占位符
5. 全部一致后进入 8b

```bash
bash scripts/verify-skill1.sh \
  --skill1-path /path/to/generated/skill1 \
  --baseline /path/to/test-baseline.json
```

**8b. 结构合规检查**：

验证生成的 Skill 1 符合 skill-creator 标准：
- SKILL.md 有 YAML frontmatter（name + description）
- 目录结构：SKILL.md + scripts/
- 所有脚本支持 `--help` 和 `--dry-run`
- 不通过则修正后重新检查

### Step 9: 加载 skill-creator 完整审查

自验证通过后，**必须调用 Skill tool 加载 `skill-creator:skill-creator` skill**（不是自己模拟流程，必须实际执行 `Skill(skill: "skill-creator:skill-creator", args: "...")`）。将生成的 Skill 1 路径和上下文作为参数传入。

skill-creator 加载后，**必须完成以下 checklist 中的每一项**（不能跳过）：

**必须完成 — 结构审查**：
- [ ] SKILL.md 符合 skill-creator anatomy（frontmatter + markdown body）
- [ ] 目录组织正确（SKILL.md + scripts/ + references/）
- [ ] progressive disclosure 合理（SKILL.md < 500 行）

**必须完成 — 内容审查**：
- [ ] description 足够 "pushy"（确保正确触发）
- [ ] 写作风格解释了 why（而非堆砌 MUST/ALWAYS）

**必须完成 — eval 流程**：
- [ ] 创建至少 3 个 test prompts 并保存到 evals/evals.json，覆盖三类场景：
  - prompt 1：**项目知识问答** — 问一个具体的代码结构/流程问题
  - prompt 2：**bug 分流讨论** — 模拟带着一个问题来讨论"这是不是 bug"
  - prompt 3：**pipeline 信息查询** — 询问测试框架、fixture、证据采集方式等
- [ ] spawn subagent with-skill 运行每个 test prompt
- [ ] 验证每个输出都包含：file:line 引用 + 测试运行输出
- [ ] 没有 file:line 引用或测试输出的回答 → 说明 Skill 1 的问答流程有缺陷，必须修正

**可选 — 描述优化**：
- skill-creator 的 description optimization loop
- 生成 trigger eval queries → 测试触发准确率 → 迭代改进 description

**可选 — 迭代**：
- 根据 eval 结果和用户反馈修正 Skill 1
- 重跑 eval 直到用户满意

这一步确保生成的 Skill 1 不仅数据正确（Step 8 保证），而且**作为 skill 的行为正确**——问问题时真的会查代码、跑测试、给出实证回答，而不是凭记忆编造。

## 输出

| 产出 | 位置 | 说明 |
|------|------|------|
| Skill 1 目录 | 用户指定或 `.claude/skills/` | 完整的项目知识 skill，可直接使用和分发 |
| coverage-matrix | `.artifacts/coverage/coverage-matrix.md` | 三层覆盖分析 |
| bootstrap-report | `.artifacts/bootstrap/bootstrap-report.md` | 执行报告（环境、测试、决策记录） |
| module-reports | `.artifacts/bootstrap/module-reports/*.json` | subagent 产出的结构化模块描述（持久化） |
| manifest.json | `.artifacts/bootstrap/manifest.json` | 项目全部文件清单 |
| test-baseline.json | `.artifacts/bootstrap/test-baseline.json` | 全部测试的基线结果 |

## 配套脚本说明

| 脚本 | 用途 |
|------|------|
| `scripts/scan-project.sh` | 枚举项目全部源文件 → manifest.json |
| `scripts/env-check.sh` | 检查运行环境依赖（重点 E2E 依赖）→ env-report.json |
| `scripts/env-setup.sh` | 尝试自动配置缺失依赖 |
| `scripts/run-full-tests.sh` | 运行全部测试 → test-baseline.json |
| `scripts/init-artifact-space.sh` | 初始化 .artifacts/ 目录（无 Skill 6 时的 fallback） |
| `scripts/verify-bootstrap.sh` | Step 6.5: 验证所有前置步骤产出完整（26 项检查） |
| `scripts/verify-skill1.sh` | 验证 Skill 1 的 test-runner 与基线一致 |
| `scripts/self-test.sh` | 验证所有脚本正常工作 |

所有脚本：`#!/bin/bash` + `set -euo pipefail`，支持 `--help` 和 `--dry-run`。

## 参考文件

| 文件 | 何时读取 |
|------|---------|
| `references/subagent-prompt.md` | Step 3 spawn subagent 时，作为 subagent 的指令模板 |
| `references/coverage-matrix-format.md` | Step 5 生成覆盖矩阵时 |
| `templates/skill1-skeleton.md` | Step 7 生成 Skill 1 的 SKILL.md 时（带 baseline_commit frontmatter）|
| `templates/self-update.sh` | Step 7 拷入 Skill 1 的 `scripts/` 目录（Layer 1 drift 检测，Step 0 引用）|
| `templates/refresh-index.sh` | Step 7 拷入 Skill 1 的 `scripts/`（Layer 2 测试基线刷新）|
| `templates/close-issue.sh` | Step 7 拷入 Skill 1 的 `scripts/`（Step 6 triage rejection 用）|
| `templates/bootstrap-report.md` | Step 7.5 生成执行报告时 |

## 反幻觉规则

这些规则贯穿整个 bootstrap 流程，确保产出的 Skill 1 绝对准确：

1. **脚本枚举，不是 LLM 猜测**：文件清单由 `scan-project.sh` 用 find/glob 产生，不允许 LLM 自己列文件
2. **全量读取验证**：Step 3 完成后比对已分析文件 vs manifest，有遗漏就补
3. **测试结果是原始输出**：捕获 exit code + stdout + stderr，不允许 LLM 总结为"大概通过了"
4. **引用制**：Skill 1 的每个技术断言必须有 file:line 或测试输出作为证据
5. **自验证**：Skill 1 生成后立即跑它的 test-runner，与基线比对不通过就不交付
6. **不确定就标 unverified**：比编造一个错误答案好得多
