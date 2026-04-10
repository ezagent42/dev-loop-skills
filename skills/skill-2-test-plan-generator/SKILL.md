---
name: test-plan-generator
description: "Generates structured test plans from code diffs, coverage gaps, and eval docs. ALWAYS use this skill — not freeform test lists — when creating a test plan, deciding what to test after code changes, analyzing test coverage gaps, converting bug reports into test cases, or planning E2E test scenarios. Triggers on: 'test plan', 'what should we test', 'coverage gap', 'test cases for this change', 'Phase 3', 'plan tests for this diff', 'which tests are missing', or when a new code-diff or eval-doc artifact appears in .artifacts/. This skill produces structured, traceable test plans with unique TC-IDs, priority levels, and source annotations — the standard input format that test-code-writer (Skill 3) consumes."
---

# test-plan-generator

> 从代码改动、覆盖缺口和评估文档中提取测试需求，生成结构化测试计划。

## 为什么需要这个 skill

代码改动后，需要判断哪些场景需要新增测试、哪些已有覆盖可以复用。这个判断依赖三类信息的交叉比对：code-diff 说明了改了什么，coverage-matrix 说明了已有什么，eval-doc 和 issue 说明了期望什么。手动做这个交叉比对容易遗漏边界场景，也难以追溯每个用例的来源。

test-plan-generator 将三类信息统一为结构化的测试用例，每个用例标注来源和优先级，输出一份可供人 review 的测试计划。review 确认后，下游 Skill 3 (test-code-writer) 读取这份计划来编写实际的测试代码。

## 触发条件

**应该触发：**
- 代码改动完成，需要确定测试范围（Phase 3 入口）
- 新的 code-diff artifact 出现在 `.artifacts/code-diffs/`
- 用户要求"生成测试计划"、"分析改动影响"、"创建 E2E test plan"
- eval-doc 中的 testcase 需要转换为可执行的测试用例
- 需要对比改动范围与已有覆盖

**不应该触发：**
- 编写测试代码（Skill 3 的职责）
- 运行测试（Skill 4 的职责）
- 评估功能预期与实际（Skill 5 的职责）
- 日常开发、修 bug（除非需要判断测试影响范围）

## 输入

从 `.artifacts/` 读取以下 artifact，全部通过 Skill 6 (artifact-registry) 查询获取路径：

| 来源 | artifact 类型 | 说明 | 是否必须 |
|------|--------------|------|----------|
| Phase 2 开发产出 | `code-diff` | 代码改动摘要：文件列表、改动类型、影响模块 | 必须（至少一个触发源） |
| Skill 0/4 产出 | `coverage-matrix` | 已有 E2E 覆盖矩阵：哪些场景有覆盖 | 推荐 |
| Skill 5 产出 | `eval-doc` | 预期 vs 实际对比，含 testcase 列表 | 可选 |
| Skill 5 产出 | `issue` | GitHub issue 引用，含 bug 复现步骤 | 可选 |
| Skill 4 产出 | `e2e-report` | 历史测试报告，含回归信息 | 可选 |

查询示例：通过 Skill 6 的 `query.sh` 按 type 和 status 过滤，详见 `references/artifact-commands.md`。

## 执行流程

### Step 1: 收集输入 artifact

从 `.artifacts/` 读取所有相关 artifact。优先处理 `confirmed` 状态的（已经过人 review），`draft` 状态的也读取但标注为"待确认来源"。

通过 Skill 6 的 `query.sh` 批量查询所有输入来源（code-diff、coverage-matrix、eval-doc、issue），具体命令详见 `references/artifact-commands.md`。

对每个 artifact，读取其 `path` 字段指向的文件内容。如果某类 artifact 不存在，跳过该来源，但在最终报告中标注"缺少 XX 来源"。

### Step 2: 分析代码改动影响范围

对每个 code-diff artifact，参照 `references/diff-analysis-guide.md` 进行分析：

1. **提取文件列表** — 从 code-diff 中读取变更文件路径
2. **分类改动类型** — 每个文件标注为：新增(A)、修改(M)、删除(D)、重命名(R)
3. **定位受影响模块** — 根据文件路径确定所属模块（如 `zchat/cli/` → CLI 模块，`zchat-channel-server/` → Channel Server 模块）
4. **识别用户流程影响** — 判断改动影响了哪些用户可感知的操作（如"创建 agent"、"发送消息"、"重启 agent"）
5. **评估改动风险** — 核心路径改动 > 配置改动 > 文档改动

产出：一份按模块和用户流程组织的影响清单。

### Step 3: 对比覆盖矩阵找缺口

如果有 coverage-matrix artifact，参照 `references/coverage-gap-guide.md` 进行对比：

1. **读取已有覆盖** — coverage-matrix 中标记为"有 E2E 覆盖"的场景列表
2. **映射改动到场景** — Step 2 识别的受影响场景，对照已有覆盖
3. **标注缺口** — 受影响但无覆盖的场景标记为 gap，输出缺口清单
4. **标注回归风险** — 有覆盖但改动可能破坏的场景标记为 regression-risk

如果没有 coverage-matrix，跳过此步，将所有受影响场景都视为"覆盖状态未知"并标注。

### Step 4: 生成测试用例列表

将来自不同来源的测试需求统一为同一种用例格式（见 `templates/test-case.md`）：

**来源 1: code-diff（Step 2 产出）**
- 新增功能 → P0 用例（验证功能正常工作）
- 修改功能 → P0 用例（验证修改后行为正确）+ P1 用例（回归测试）
- 删除功能 → P1 用例（验证相关功能不受影响）

**来源 2: coverage-gap（Step 3 产出）**
- 缺口场景 → P1 用例（补充覆盖）
- 回归风险场景 → P0 用例（确保不回归）

**来源 3: eval-doc**
- eval-doc 中的 testcase 列表直接转换为用例，保持原有优先级
- 来源标注为 `eval-doc`

**来源 4: issue / bug-feedback**
- bug 复现步骤转换为 P0 用例（验证 bug 已修复）
- 来源标注为 `bug-feedback`

每个用例必须包含完整字段：场景名称、来源、优先级、前置条件、操作步骤、预期结果、涉及模块。用例 ID 格式为 `TC-{三位序号}`（如 TC-001）。

### Step 5: 输出 test-plan summary

按 `templates/plan-summary.md` 模板生成完整的测试计划文件：

1. **YAML frontmatter** — 包含 type、id、status(draft)、producer(skill-2)、创建时间、触发原因、关联的输入 artifact ID
2. **触发原因** — 说明为什么需要这个测试计划（哪个 code-diff、哪个 eval-doc）
3. **用例列表** — Step 4 产出的所有用例，按优先级排序（P0 在前）
4. **统计表** — 总用例数、各优先级数量、各来源数量
5. **风险标注** — 高风险区域（核心路径改动）、回归风险（已有覆盖被影响）、未知覆盖（无 coverage-matrix）

文件保存到 `.artifacts/test-plans/` 目录，命名格式 `plan-{描述性短语}-{序号}.md`。

### Step 6: 人 review + 确认

测试计划以 `draft` 状态产出，需要人 review：

1. 输出计划摘要给用户：总用例数、P0/P1/P2 分布、高风险区域
2. 等待用户确认（可能要求增删用例或调整优先级）
3. 用户确认后，通过 Skill 6 的 `update-status.sh` 更新状态为 `confirmed`，详见 `references/artifact-commands.md`。

### Step 7: 注册到 artifact-registry

在 Step 5 保存文件后，立即通过 Skill 6 的 `register.sh` 注册为 draft 状态的 test-plan artifact，并关联输入 artifact ID。详见 `references/artifact-commands.md`。

## 输出

### 测试计划文件

保存在 `.artifacts/test-plans/` 目录。格式见 `templates/plan-summary.md`。

关键特征：
- YAML frontmatter 包含完整元数据和关联信息
- 每个用例有唯一 ID（TC-001, TC-002...）和明确来源
- 统计表便于快速评估工作量
- 风险标注帮助安排执行优先级

### 与下游的交互

测试计划 `confirmed` 后，Skill 3 (test-code-writer) 通过 Skill 6 查询 `--type test-plan --status confirmed` 获取计划，逐个编写测试代码，完成后将状态更新为 `executed`。详见 `references/artifact-commands.md`。

## 模板说明

| 模板文件 | 用途 |
|----------|------|
| `templates/test-case.md` | 单个测试用例的统一格式 |
| `templates/plan-summary.md` | 完整测试计划的输出格式 |

## 参考文档

| 文档 | 用途 |
|------|------|
| `references/diff-analysis-guide.md` | Step 2：如何从 code-diff 提取影响范围 |
| `references/coverage-gap-guide.md` | Step 3：如何对比改动与已有覆盖找缺口 |
| `references/artifact-commands.md` | Skill 6 artifact-registry 交互命令参考 |

## 配套脚本

| 脚本 | 用途 |
|------|------|
| `scripts/self-test.sh` | 验证所有文件存在、模板格式正确 |
