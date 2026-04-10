# Subagent 指令模板：模块分析

> 每个 subagent 收到此模板 + 该模块的文件列表，产出 module-report.json。

## 你的任务

你负责分析一个代码模块。你会收到该模块的全部文件路径列表。你需要：

1. **读取每一个文件**——不跳过，不概括，逐个读完
2. 为每个文件记录结构化信息
3. 识别并运行该模块的测试
4. 产出 module-report.json

## 执行步骤

### 1. 逐文件阅读

对于文件列表中的**每一个文件**：
- 用 Read 工具读取完整内容
- 记录：文件路径、行数、关键函数/类名（含行号）、公开接口、依赖的其他模块
- 读完后在清单中标记已读

读完所有文件后，检查清单是否 100% 完成。有遗漏就补读。

### 2. 模块描述

基于阅读内容写模块描述：
- 模块职责（一句话）
- 核心流程（关键函数的调用链）
- 对外接口（其他模块/用户会调用什么）
- 依赖关系（依赖哪些其他模块或外部服务）

每个描述都必须有 file:line 引用。例如：
> AgentManager.create() (zchat/cli/agent_cmd.py:42) 负责创建 agent workspace 和 IRC 连接。

### 3. 测试执行

识别该模块的测试文件（通常在 tests/ 下，文件名包含模块名）。然后：

```bash
# 运行该模块的测试，捕获完整输出
<test-command> 2>&1
echo "EXIT_CODE=$?"
```

记录：
- 测试命令
- exit code
- 通过/失败/跳过数量
- 失败测试的错误信息（前 500 字符）
- 跳过测试的原因

如果找不到该模块的测试文件，标记为 `no_tests_found`。

### 4. 产出 module-report.json

```json
{
  "module_name": "agent",
  "module_path": "zchat/cli/",
  "description": "Agent 生命周期管理：创建、停止、重启、列表",
  "files_analyzed": [
    {
      "path": "zchat/cli/agent_cmd.py",
      "lines": 142,
      "key_symbols": [
        {"name": "create", "type": "function", "line": 42, "description": "创建 agent workspace + IRC 连接"},
        {"name": "stop", "type": "function", "line": 89, "description": "停止指定 agent"}
      ]
    }
  ],
  "interfaces": [
    {"name": "create(name, project)", "file": "zchat/cli/agent_cmd.py", "line": 42}
  ],
  "dependencies": ["irc_manager", "layout", "paths"],
  "test_results": {
    "command": "uv run pytest tests/unit/test_agent.py -v",
    "exit_code": 0,
    "passed": 5,
    "failed": 0,
    "skipped": 0,
    "raw_output_first_500": "..."
  },
  "user_flows": [
    {"name": "创建 agent", "steps": ["zchat agent create <name>"], "entry_point": "agent_cmd.py:42"}
  ]
}
```

## 重要规则

- **不要编造**：如果不确定某个函数的行为，写 "unverified" 而不是猜测
- **不要跳过文件**：文件列表中的每一个都必须读取
- **保留原始测试输出**：不要总结为"测试通过"，保留 exit code 和输出片段
- **file:line 引用**：每个技术断言必须有引用

将最终的 module-report.json 保存到指定的输出目录。
