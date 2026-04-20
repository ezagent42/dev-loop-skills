# Evidence collection rules

> 证据采集规范：确保每个测试结果都有可独立验证的证据。

## 命名规范

所有证据文件遵循统一命名：

```
{date}-{test-id}-{step}.{ext}
```

- `{date}` — `YYYYMMDD-HHMMSS` 格式，如 `20260410-143022`
- `{test-id}` — 测试函数名（kebab-case），如 `test-agent-dm-flow`
- `{step}` — 步骤标识（kebab-case），如 `after-join`, `response-received`, `final-state`
- `{ext}` — 文件类型决定：`.png`, `.json`, `.txt`, `.cast`

示例：
- `20260410-143022-test-agent-dm-flow-after-join.txt`
- `20260410-143022-test-mention-routing-response-received.json`
- `20260410-143022-test-weechat-plugin-final-state.png`

## 证据类型

### Terminal capture（终端应用）

适用场景：IRC 客户端、agent 进程、终端 UI 测试。

**Zellij:**
```bash
# 捕获当前 pane 的屏幕内容
zellij action dump-screen /path/to/{date}-{test-id}-{step}.txt

# 捕获整个 layout 信息
zellij action dump-layout > /path/to/{date}-{test-id}-{step}-layout.txt
```

**Asciinema:**
```bash
# 录制完整 session（用于 pre-release walkthrough 级别的验证）
asciinema rec /path/to/{date}-{test-id}-full.cast

# 回放验证
asciinema play /path/to/{date}-{test-id}-full.cast
```

**tmux capture-pane (fallback):**
```bash
tmux capture-pane -t {session}:{window} -p > /path/to/{date}-{test-id}-{step}.txt
```

采集时机：
- 服务启动完成后
- 发送消息/命令后
- 收到响应/状态变更后
- 测试结束前（final state）

### Screenshot / Video / Trace（Web 应用 — pytest-playwright）

适用场景：Web UI 测试、浏览器自动化。

**推荐路径：pytest-playwright 内置采集**

在 runner 调用 pytest 时追加：

```
--screenshot=only-on-failure \
--video=retain-on-failure \
--tracing=retain-on-failure \
--output=.artifacts/e2e-reports/report-{name}-{seq}/evidence/
```

产出目录结构（`--output` 下由 pytest-playwright 自动生成）：

```
.artifacts/e2e-reports/report-{name}-{seq}/evidence/
  {test_id}/
    test-failed-1.png     # 失败时截图
    video.webm            # 失败时完整录像
    trace.zip             # Playwright trace（playwright show-trace 可回放）
    01-loaded.png         # 测试内 page.screenshot 显式产出
    02-submitted.png
```

绿色运行时，`only-on-failure` / `retain-on-failure` 不保留自动证据；显式 `page.screenshot()` 仍会保留（用于 happy-path 证明）。

**显式截图（测试代码内）：**

```python
# 在 page 所在步骤之后
page.screenshot(path=f"{evidence_dir}/01-checkout-loaded.png", full_page=True)
```

`evidence_dir` 由 skill-3 `references/playwright-pattern.md` 中定义的 fixture 提供，会解析为当前测试的证据子目录。

内容要求：
- 截图必须包含足够上下文，独立查看即可判断测试是否通过
- 对于表单操作：截图应包含输入值和提交后的反馈
- 对于列表/表格：截图应包含完整数据区域
- 视口尺寸固定（见 playwright-pattern.md 中的 `browser_context_args`），否则跨环境截图漂移

采集时机：
- 页面加载完成后
- 表单填写完成后
- 操作执行后（点击按钮、提交等）
- 错误/成功提示出现时

### API response（API 测试）

适用场景：REST API、gRPC、GraphQL 测试。

```bash
# 保存完整 response
curl -s -w "\n---HTTP_STATUS:%{http_code}---" \
  http://localhost:8080/api/endpoint | tee /path/to/{date}-{test-id}-{step}.json
```

JSON 文件结构：
```json
{
  "timestamp": "2026-04-10T14:30:22Z",
  "test_id": "test-agent-list",
  "step": "after-create",
  "request": {
    "method": "GET",
    "url": "/api/agents",
    "headers": {}
  },
  "response": {
    "status_code": 200,
    "headers": {},
    "body": {}
  }
}
```

采集时机：
- 每个 API 调用后（不只是最终断言的那个）
- 错误 response 必须采集
- 包含 request + response 完整对，方便重现

## 内容要求

证据必须满足**独立证明**标准：

1. **自证性**：仅查看证据文件（不看测试代码），即可判断测试结果是 pass 还是 fail
2. **完整性**：包含判断所需的全部信息（不能只截半个屏幕）
3. **时间标记**：文件名包含时间戳，内容中也应有时间信息
4. **可追溯**：文件名中的 test-id 和 step 能唯一定位到测试流程中的具体位置

反例（不合格的证据）：
- 只截了终端的最后一行输出（缺少上下文）
- API response 只保存了 body 没保存 status code（无法判断是否成功）
- 截图分辨率过低，文字无法辨认

## 存储位置

证据文件**按来源类型分流**：

**终端/CLI/asciinema 证据** — 保留在测试脚本的原始输出位置（历史约定，避免搬运）：

```
tests/
├── e2e/
│   └── evidence/              # E2E 测试证据
│       ├── 20260410-143022-test-agent-dm-flow-after-join.txt
│       └── 20260410-143022-test-agent-dm-flow-final-state.txt
├── pre_release/
│   └── walkthrough-20260410-143022.cast   # asciinema 录制
```

**Playwright 证据（新增）** — 和 e2e-report 共存于 `.artifacts/` 下，方便 prd2impl 闭环迭代查找：

```
.artifacts/e2e-reports/report-{name}-{seq}/
├── report.md
└── evidence/
    └── {test_id}/
        ├── 01-loaded.png
        ├── test-failed-1.png
        ├── video.webm
        └── trace.zip
```

原因差异：asciinema/zellij 的工具链已经有固定输出位置，强行迁移会破坏既有脚本；pytest-playwright 没有既有约定，直接指定 `--output` 放到 report 目录下最省事，也让 [skill-6-continue-task (prd2impl)](../../../../prd2impl/skills/skill-6-continue-task/SKILL.md) 的 UI-regression 闭环可以基于一个稳定路径定位截图。

e2e-report 中通过 `evidence` 字段引用这些路径：

```yaml
evidence:
  - path: tests/e2e/evidence/20260410-143022-test-agent-dm-flow-after-join.txt
    type: terminal-capture
    tool: zellij
  - path: tests/e2e/evidence/20260410-143022-test-agent-dm-flow-final-state.txt
    type: terminal-capture
    tool: zellij
```

这样做的原因：不破坏已有测试脚本的输出约定，避免文件搬运的复杂性。

## 失败时的额外证据

测试失败时，除了常规证据，还需采集：

1. **完整 traceback**：pytest 输出中的完整错误堆栈
2. **相关日志**：失败发生前后 50 行的服务日志
3. **进程快照**：`ps aux | grep {service}` 确认相关进程是否存活
4. **端口状态**：`ss -tlnp | grep {port}` 确认端口是否监听
5. **环境快照**：Python 版本、关键包版本、OS 信息

这些保存为 `{date}-{test-id}-failure-context.txt`，文本格式，方便快速查阅。
