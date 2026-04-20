# .artifacts/ 目录结构

> init-artifact-space.sh 创建的标准目录布局。

```
.artifacts/
├── registry.json              # artifact 索引（所有 skill 共享）
├── .gitattributes             # git-lfs 配置（*.png, *.gif, *.cast）
│
├── eval-docs/                 # Skill 5 (feature-eval) 产出
│   └── eval-{name}-{seq}.md  # 如 eval-agent-dm-001.md
│
├── code-diffs/                # Phase 2 开发产出
│   └── diff-{name}-{seq}.md  # 如 diff-agent-dm-001.md
│
├── test-plans/                # Skill 2 (test-plan-generator) 产出
│   └── plan-{name}-{seq}.md  # 如 plan-agent-dm-001.md
│
├── test-diffs/                # Skill 3 (test-code-writer) 产出
│   └── diff-e2e-{name}-{seq}.md
│
├── e2e-reports/               # Skill 4 (test-runner) 产出
│   └── report-{name}-{seq}/  # 每个 report 一个子目录
│       ├── report.md         # 正文（evidence 字段引用证据路径）
│       └── evidence/         # Playwright 等产出的二进制证据（按测试分目录）
│           └── {test_id}/
│               ├── *.png     # 截图（显式 + 失败自动）
│               ├── video.webm   # 失败录像
│               └── trace.zip    # Playwright trace
│
├── issues/                    # Skill 5 (feature-eval) 产出
│   └── issue-{name}-{seq}.md
│
└── coverage/                  # Skill 0 (project-builder) / Skill 4 产出
    └── coverage-matrix.md     # 持续更新的覆盖矩阵（只有一份，覆盖更新）
```

## 命名规则

- `{name}` — 描述性短名（kebab-case），如 `agent-dm`、`mention-bug`
- `{seq}` — 三位序号，如 `001`、`002`
- 完整 ID = `{type}-{seq}`，如 `eval-doc-001`
- 文件名中的 `{name}` 是可读标识，`{seq}` 保证唯一性

## 证据文件

证据文件按来源类型分流：

- **Terminal capture / asciinema 录制** — 保留在测试脚本的原始输出位置（如 `tests/pre_release/walkthrough-*.cast`），不进 `.artifacts/`。原因：既有脚本已有固定输出约定，搬运成本高且易出错。
- **Playwright 截图 / 录像 / trace（Web UI 项目）** — 产出到 `.artifacts/e2e-reports/report-{name}-{seq}/evidence/{test_id}/`，和 report 共址。原因：Web 项目没有既有输出约定，直接收敛到 report 目录便于 prd2impl 的 UI-regression 闭环定位。

两种情况下，e2e-report 的 `evidence` 字段都引用实际路径；registry 通过 artifact ID 索引到 report，再由 report 的 evidence 表延伸到具体证据文件。

git-lfs 配置对两种来源都生效（`.artifacts/.gitattributes` 以及仓库根级别的 `.gitattributes`，如有）。

## git-lfs 配置

`init-artifact-space.sh` 在 `.artifacts/.gitattributes` 中配置：

```
*.png filter=lfs diff=lfs merge=lfs -text
*.gif filter=lfs diff=lfs merge=lfs -text
*.cast filter=lfs diff=lfs merge=lfs -text
*.jpg filter=lfs diff=lfs merge=lfs -text
```

虽然当前 `.artifacts/` 下主要是 markdown 文件，但未来接入 Web 项目时可能有截图，提前配置好。
