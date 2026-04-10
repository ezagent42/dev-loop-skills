---
type: test-plan
id: {auto-generated}
status: draft
producer: skill-2
created_at: "{date}"
trigger: "{触发原因：code-diff-xxx / eval-doc-xxx / coverage-gap}"
related:
  - {code-diff-id}
  - {coverage-matrix-id}
---

# Test Plan: {title}

## 触发原因

{为什么需要这个测试计划——哪个 code-diff 引入了什么改动，哪个 eval-doc 发现了什么缺口}

## 用例列表

{按优先级排序的测试用例，使用 test-case.md 模板格式}

### TC-001: {场景名称}

- **来源**：{来源}
- **优先级**：P0
- **前置条件**：{前置条件}
- **操作步骤**：
  1. ...
- **预期结果**：{预期结果}
- **涉及模块**：{模块}

### TC-002: {场景名称}

...

## 统计

| 指标 | 值 |
|------|-----|
| 总用例数 | N |
| P0 | X |
| P1 | Y |
| P2 | Z |
| 来源：code-diff | A |
| 来源：eval-doc | B |
| 来源：coverage-gap | C |
| 来源：bug-feedback | D |

## 风险标注

{高风险区域、回归风险、未知覆盖状态的模块}

- **高风险**：{核心路径改动的模块和场景}
- **回归风险**：{已有覆盖但被改动影响的场景}
- **覆盖未知**：{无 coverage-matrix 时标注}
