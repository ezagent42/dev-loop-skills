---
type: bootstrap-report
id: bootstrap-report-001
status: executed
producer: skill-0
created_at: "{date}"
---

# Bootstrap Report: {project_name}

## 环境问题与解决

- 发现了什么缺失
- 自动修复了哪些（Step 2.5）
- 手动修复了哪些
- 无法修复的 soft dependency 及跳过理由

## 测试执行结果

- 每个测试套件的运行结果（passed/failed 统计）
- failed 的测试：根因分类（代码 bug / 测试本身的问题）
- 环境导致 error/skip 的诊断和修复过程（Step 4 的循环记录）

## 覆盖分析

- 覆盖矩阵摘要
- E2E 缺口及原因（没实现 / 无测试 / 待补）

## 决策记录

- bootstrap 过程中做的判断及理由
- 已知问题和已知边界
