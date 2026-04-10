# Coverage Matrix 格式规范

> 三层覆盖矩阵，区分代码测试、操作 E2E 和环境受限覆盖。

## 格式

```markdown
---
type: coverage-matrix
id: coverage-matrix-001
status: draft
producer: skill-0
created_at: "2026-04-09"
---

# Coverage Matrix: {project_name}

## 概览

| 指标 | 值 |
|------|-----|
| 总模块数 | N |
| 代码测试覆盖模块 | X/N |
| 操作 E2E 覆盖流程 | Y/M |
| 环境受限测试 | Z |

## 代码测试覆盖

已有的单元/集成/API 测试覆盖了哪些模块。

| 模块 | 测试文件 | 测试命令 | 结果 | 覆盖状态 |
|------|---------|---------|------|---------|
| agent | tests/unit/test_agent.py | uv run pytest tests/unit/test_agent.py -v | 5/5 passed | ✅ covered |
| auth | tests/unit/test_auth.py | uv run pytest tests/unit/test_auth.py -v | 3/3 passed | ✅ covered |
| irc | (无测试文件) | - | - | ❌ no tests |

## 操作 E2E 覆盖

符合 pipeline E2E 标准（通过 UI/终端实际操作 + 证据采集）的测试覆盖了哪些用户流程。

| 用户流程 | E2E 测试 | 证据类型 | 覆盖状态 |
|---------|---------|---------|---------|
| 创建 agent | tests/e2e/test_e2e.py::phase_3 | terminal capture | ✅ covered |
| 私聊 DM | (无) | - | ❌ not covered |
| 系统消息渲染 | (无) | - | ❌ not covered |

**用户流程粒度**：操作级别。"在 WeeChat 输入 @agent 消息并收到回复" 是一个流程，不是"消息功能"。

## 环境受限覆盖

测试存在但因环境缺失无法运行。

| 测试 | 所需环境 | 状态 | 说明 |
|------|---------|------|------|
| tests/e2e/test_e2e.py | ergo IRC server | ⚠️ skipped | 需要运行中的 ergo 实例 |
| tests/pre_release/walkthrough.sh | 完整环境 | ⚠️ skipped | 需要 ergo + zellij + asciinema |

## E2E 缺口清单

操作 E2E 未覆盖的用户流程列表。这是 Skill 2 (test-plan-generator) 的第一批输入。

1. 私聊 DM：agent A 给 agent B 发私信
2. 系统消息渲染：__zchat_sys: 消息在 WeeChat 中显示
3. ...（按优先级排序）
```

## 用户流程识别规则

从模块分析中提取用户流程时，粒度要求：

- **操作级**：描述具体的用户操作和预期结果
- **可测试**：每个流程都能写成 E2E 测试（有明确的操作步骤和断言）
- **不重叠**：每个流程测试独立的功能路径

**好的粒度**：
- "在 WeeChat 中输入 `/agent create helper` 并验证 agent 出现在在线列表"
- "在 #general 中发送 `@alice-agent0 hello` 并验证 agent 回复"

**太粗的粒度**：
- "消息功能"
- "agent 管理"
