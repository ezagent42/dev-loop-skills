---
name: feature-eval
description: "Generate structured eval-docs that compare expected vs actual behavior. Two modes: simulate (Phase 1 — explore a feature idea before coding) and verify (Phase 7 — record a bug or unexpected behavior and create a GitHub issue). Trigger words: simulate, eval, verify, found a bug, not working as expected, compare expected vs actual, create eval doc, file an issue, report problem."
---

# feature-eval

> 统一的"预期 vs 实际"对比工具。服务两个场景：需求提出时的模拟评估（Phase 1）和问题反馈时的结构化验证（Phase 7）。

## 为什么需要这个 skill

开发流水线中，"预期效果"和"实际效果"的对比贯穿始终。需求阶段需要模拟"如果实现了会怎样"，验收阶段需要结构化地收集"哪里不对"。两者的核心数据结构相同——testcase 表格（场景/预期/实际/差异），只是数据来源不同（AI 模拟 vs 人类观察）。feature-eval 将两者统一，产出标准化的 eval-doc，供下游 skill（test-plan-generator、artifact-registry）消费。

没有这个 skill 时，需求讨论散落在聊天记录中难以追溯，bug 反馈格式不统一导致信息不全。有了它，每个评估都有结构化文档、可追溯的 artifact 和（验证模式下）自动创建的 GitHub issue。

## 触发条件

**应该触发：**
- 用户描述 feature 想法，想了解实现效果（"如果实现了..."、"模拟一下"、"simulate"）
- 用户报告问题（"发现 bug"、"这个不对"、"不符合预期"、"verify"）
- 用户要求创建 eval-doc 或对比文档
- 用户想给非技术人员收集结构化反馈
- 用户说"评估"、"eval"、"验证"、"对比预期和实际"

**不应该触发：**
- 纯代码开发、写测试（那是 Skill 2/3 的职责）
- 运行测试（那是 Skill 4 的职责）
- 项目知识问答（那是 Skill 1 的职责）
- 管理 artifact 索引（那是 Skill 6 的职责）

## 两种模式

### 模拟模式（Simulate）— Phase 1 需求评估

**场景**：产品或开发者有一个 feature 想法，想在编码前了解各 testcase 的预期效果。

**触发信号**：用户描述 feature + 说"模拟"/"simulate"/"如果实现了"/"评估可行性"

**流程**：

1. **提取 feature 描述**
   - 从用户输入中识别 feature 名称和核心需求
   - 如果描述模糊，追问关键细节（目标用户、核心场景、约束条件）

2. **生成 testcase 列表**
   - 分析 feature 涉及的用户场景
   - 为每个场景定义：前置条件、操作步骤、预期效果
   - 覆盖正常路径 + 边界情况 + 错误处理
   - 建议优先级（P0 = 核心功能，P1 = 重要，P2 = 锦上添花）

3. **AI 模拟分析**
   - 读取相关代码，判断 feature 在当前架构下的可行性
   - 对每个 testcase，分析："如果按描述实现，模拟效果是什么"
   - 标注风险点：与现有功能的冲突、技术难点、依赖缺口
   - 差异描述：预期效果 vs 模拟效果的差距，以及原因

4. **生成 eval-doc**
   - 使用 `templates/eval-doc.md` 模板
   - 模式 = simulate
   - 填入 testcase 表格（模拟效果列）
   - 展示给用户确认

5. **用户确认后注册**
   - 用户调整 testcase（增删改优先级）
   - 状态从 draft → confirmed
   - 写入 `.artifacts/eval-docs/`
   - 注册到 artifact-registry（如有 Skill 6）

### 验证模式（Verify）— Phase 7 问题反馈

**场景**：用户（或测试人员）发现了问题，需要结构化地记录并创建 issue。

**触发信号**：用户报告问题 + 说"发现 bug"/"这个不对"/"不符合预期"/"验证"

**流程**：

1. **引导描述问题**
   - 加载 `references/feedback-guide.md` 中的引导模板
   - 按步骤引导用户描述：
     - 你做了什么操作？（具体步骤）
     - 你期望看到什么？（预期行为）
     - 实际发生了什么？（实际行为）
     - 这个问题每次都会出现吗？（复现性）
     - 有没有截图或日志？（证据）
   - 对非技术用户要耐心，用简单语言追问

2. **构建 testcase**
   - 将用户描述转化为结构化 testcase
   - 明确前置条件（环境、版本、配置）
   - 分离操作步骤和观察到的结果

3. **收集证据**
   - 要求用户附上证据：截图、录屏、日志片段、错误信息
   - 证据记录在 eval-doc 的"证据区"
   - 如果没有证据，标注"待补充"但不阻断流程

4. **生成 eval-doc**
   - 使用 `templates/eval-doc.md` 模板
   - 模式 = verify
   - 填入 testcase 表格（实际效果列）
   - 填入证据区

5. **分流建议**
   - 根据问题特征标注分流建议：
     - **疑似 bug** — 行为明确违反文档或预期（程序出错、崩溃、数据丢失）
     - **疑似不合理** — 行为技术上正确但用户体验差（流程繁琐、提示不清）
     - **需要讨论** — 无法判断是 bug 还是设计意图，需要更多上下文
   - 分流建议是给开发者的参考，不是最终裁定

6. **创建 GitHub issue**
   - 运行 `scripts/create-issue.sh --eval-doc <path> --repo <owner/repo>`
   - 从 eval-doc 提取标题（feature 名称 + 模式）和描述（testcase 表格 + 证据）
   - 返回 issue URL

7. **添加 watcher（可选）**
   - 如果用户指定 watcher：`scripts/add-watcher.sh --issue-url <url> --watcher <username>`

8. **注册 artifact**
   - eval-doc 写入 `.artifacts/eval-docs/`
   - issue 引用写入 `.artifacts/issues/`
   - 注册到 artifact-registry（如有 Skill 6）

## Artifact 交互

### 写入路径

| 产出 | 路径 | 说明 |
|------|------|------|
| eval-doc（模拟） | `.artifacts/eval-docs/eval-{feature}-{seq}.md` | 模拟模式产出 |
| eval-doc（验证） | `.artifacts/eval-docs/eval-{feature}-{seq}.md` | 验证模式产出 |
| issue 引用 | `.artifacts/issues/issue-{feature}-{seq}.md` | 验证模式创建的 GitHub issue 引用 |

### 与 Skill 6 (artifact-registry) 交互

Skill 6 路径：`/home/yaosh/.claude/skills/dev-loop-skills/skills/skill-6-artifact-registry`

**有 Skill 6 时**：通过 `register.sh` 注册 eval-doc 和 issue，确认后通过 `update-status.sh` 更新状态。详见 `references/artifact-commands.md`。

**无 Skill 6 时**：直接写入 `.artifacts/` 约定目录并 git commit。

## Eval-doc 格式

使用 `templates/eval-doc.md` 模板。核心结构：

- YAML frontmatter：type、id、status、mode、feature、submitter、related
- Testcase 表格：# / 场景 / 前置条件 / 操作步骤 / 预期效果 / 模拟或实际效果 / 差异描述 / 优先级
- 证据区（仅验证模式）
- 分流建议（仅验证模式）

## 配套脚本

| 脚本 | 用途 | 关键参数 |
|------|------|----------|
| `scripts/create-issue.sh` | 从 eval-doc 创建 GitHub issue | `--eval-doc --repo [--labels] [--dry-run]` |
| `scripts/add-watcher.sh` | 为 issue 添加 watcher | `--issue-url --watcher [--dry-run]` |
| `scripts/self-test.sh` | 验证所有脚本正常工作 | `[--dry-run]` |

所有脚本：`#!/bin/bash` + `set -euo pipefail`，支持 `--help` 和 `--dry-run`。

## 参考文件

| 文件 | 何时读取 |
|------|---------|
| `references/feedback-guide.md` | 验证模式引导用户描述问题时 |
| `references/artifact-commands.md` | Skill 6 artifact-registry 交互命令参考 |
| `templates/eval-doc.md` | 生成 eval-doc 时 |

## 质量要求

1. **模拟模式的模拟效果必须基于代码分析**：不能凭空想象，要实际读相关代码判断可行性
2. **验证模式必须引导出完整信息**：操作步骤、预期、实际、复现性缺一不可
3. **证据优先**：有截图/日志 > 纯文字描述。没有证据要标注"待补充"
4. **分流建议要说理由**：不能只标"疑似 bug"，要解释为什么这么判断
5. **Testcase 覆盖要全面**：模拟模式至少覆盖正常路径 + 2 个边界情况
