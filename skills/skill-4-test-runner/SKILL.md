---
name: test-runner
description: "Execute the full E2E test suite and generate a structured report distinguishing new vs regression cases. Use this skill when running E2E tests, executing the test suite, generating a test report, checking for regressions, validating a feature end-to-end, or entering Phase 5 of the dev-loop pipeline. Also trigger when the user says 'run tests', 'run e2e', 'test report', 'regression check', 'phase 5', 'execute tests', 'validate feature', or asks whether new changes broke existing functionality."
---

# test-runner

> Phase 5 of the dev-loop pipeline. Executes the complete E2E test suite, classifies results as new-case or regression, collects evidence at critical checkpoints, and produces a structured e2e-report.

## Why this skill exists

After Skill 3 (test-code-writer) adds new test cases to the suite, someone must run the **entire** suite -- not just the new cases. A passing new case means nothing if the same change silently broke three existing tests. test-runner treats regression failures as high-severity signals: the new feature damaged something that previously worked. The structured report makes this distinction explicit so developers act on regressions before celebrating new passes.

Evidence collection matters because terminal-based E2E tests (Zellij capture, asciinema) and API-based tests produce ephemeral output. Without deliberate capture at the right moment, the proof disappears. This skill codifies when and how to capture evidence so reports are auditable.

## Trigger conditions

**Should trigger:**
- New test-diff artifact arrives from Skill 3 (test-code-writer)
- User requests "run e2e", "run tests", "regression check"
- Pipeline reaches Phase 5
- User wants to validate a feature end-to-end
- User asks "did my changes break anything"

**Should not trigger:**
- Writing test code (Skill 3's job)
- Generating a test plan (Skill 2's job)
- Registering/querying artifacts (Skill 6's job, though this skill calls Skill 6)
- Pure unit test runs (not E2E)

## Input

| Source | Content |
|--------|---------|
| Skill 3 artifact | `test-diff-xxx` in `.artifacts/test-diffs/` listing new E2E cases |
| User | `--project-root` path, optional `--test-diff-id` to scope the run |
| Environment | Running services (IRC server, Zellij, etc.) verified by env-check |
| Coverage matrix | `.artifacts/coverage/coverage-matrix.md` for baseline comparison |

## Execution flow

### Step 1: Environment pre-check

Run the env-check script to verify all E2E dependencies are available:

```bash
bash scripts/env-check.sh --project-root /path/to/project
```

This checks:
- Test framework (pytest, uv) installed and callable
- External services alive (IRC server port, Zellij session, tmux)
- Terminal evidence tools (zellij, asciinema) available
- E2E test directory exists and contains test files

The script outputs structured JSON to stdout (for programmatic use) and human-readable check results to stderr. Parse the JSON `overall` field: `"ready"`, `"ready_with_warnings"`, or `"blocked"`.

If any **hard** dependency is missing (`"blocked"`), stop and report the issue. Do not run tests against an incomplete environment -- the results would be misleading.

### Step 2: Identify new cases

Determine which test cases are "new" (added by the latest test-diff) vs "regression" (pre-existing):

1. Check if `--test-diff-id` was provided, or find the latest `test-diff` artifact in `.artifacts/test-diffs/`
2. Parse the test-diff to extract new test function names (e.g., `test_agent_dm_flow`, `test_mention_routing`)
3. Everything else in the suite is a regression case

If no test-diff exists (manual trigger or regression-only run), treat **all** cases as regression.

How to parse a test-diff: the artifact is a markdown file with a frontmatter `type: test-diff`. The body contains a section listing new test functions with their file paths. Extract function names matching `test_*` patterns.

### Step 3: Execute the full E2E suite

Run the unified entry point:

```bash
bash scripts/run-e2e.sh \
  --project-root /path/to/project \
  --test-diff-id test-diff-001
```

This script:
1. Discovers all E2E test files under the project's test directory
2. Runs the full suite via `uv run pytest tests/e2e/ -v --tb=long -q` (or the project-specific command)
3. Captures raw output (stdout + stderr + exit code)
4. Outputs a JSON result structure to stdout

Do **not** run only the new cases. The whole point is catching regressions.

### Step 4: Collect evidence

At critical verification points during test execution, capture evidence. The rules are defined in `references/evidence-rules.md`. Summary:

**Terminal applications (Zellij/tmux):**
- `zellij action dump-screen` or `zellij action dump-layout` for pane state
- `asciinema rec` for full session recording
- Capture timing: after each major state transition (service started, message sent, response received)

**Web applications (Playwright — preferred for UI projects):**
- Pass these flags on the pytest invocation (runner adds them automatically when the suite uses `pytest-playwright`):
  ```
  --screenshot=only-on-failure \
  --video=retain-on-failure \
  --tracing=retain-on-failure \
  --output=.artifacts/e2e-reports/report-{name}-{seq}/evidence/
  ```
- Explicit `page.screenshot(path=...)` inside tests produces positive-path evidence too.
- No manual capture scripts required — pytest-playwright writes per-test subdirs under `--output`.

**API tests:**
- Save response body as `{date}-{test-id}-{step}.json`
- Include status code, headers, and body

**Evidence location rule (updated):**
- Terminal/CLI/asciinema evidence stays in the project's original test output directory (e.g., `tests/e2e/evidence/`). The report references them by path.
- Playwright evidence lands under `--output=.artifacts/e2e-reports/report-{name}-{seq}/evidence/` — colocated with the report so the closed-loop iteration in prd2impl can find it deterministically.
- Either way, the runner scans the relevant directories after the pytest run completes and populates the report's evidence manifest automatically (see Step 7).

### Step 5: Classify results

Split test outcomes into two categories using the new-case list from Step 2:

| Category | Test function in test-diff? | Meaning |
|----------|---------------------------|---------|
| New case | Yes | Validates the newly implemented feature |
| Regression case | No | Validates previously working functionality |

For each test, record:
- **name**: test function name
- **file**: test file path
- **status**: passed / failed / error / skipped
- **duration**: execution time
- **evidence**: list of evidence file paths
- **failure_detail**: traceback or error message (if failed)

### Step 6: Collect failure context

For every failed or errored test, automatically gather:

1. **Traceback**: full Python traceback from pytest output
2. **Log snippets**: last 50 lines of relevant logs (IRC server log, agent log, etc.)
3. **Process state**: `ps aux | grep` for relevant services, port checks
4. **Environment info**: Python version, key package versions, OS info
5. **Recent git changes**: `git log --oneline -5` and `git diff --stat HEAD~1`

This context is included in the report under each failed test, so debugging doesn't require reproducing the environment.

### Step 7: Generate e2e-report

Read the template from `templates/e2e-report.md` and fill in:

1. Basic info: date, branch, trigger source
2. Result summary table: new-case vs regression counts
3. **Regression failures highlighted** -- these are high-priority. If a regression case fails, it means the new feature broke existing functionality. The report calls this out prominently.
4. Detailed per-test results with evidence references
5. Newly discovered issues (unexpected behavior noticed during testing)
6. Evidence manifest (all captured file paths) — **auto-populated, not hand-written**

**Evidence manifest auto-population**:

After the pytest run completes, scan two roots and emit one row per file into the manifest table:

1. The Playwright `--output` root (if the project uses pytest-playwright):
   `.artifacts/e2e-reports/report-{name}-{seq}/evidence/`
   - `*.png` → `type=screenshot`, `tool=playwright`
   - `video.webm` → `type=video`, `tool=playwright`
   - `trace.zip` → `type=trace`, `tool=playwright`
   - Extract `{test-id}` from the parent subdirectory name; `{step}` from the file stem (`01-loaded.png` → `loaded`, `test-failed-1.png` → `failure`).

2. The project's original terminal evidence directory (e.g., `tests/e2e/evidence/`):
   - `*.txt` → `type=terminal-capture`, `tool=zellij|tmux` (decide by filename hint)
   - `*.cast` → `type=session-recording`, `tool=asciinema`
   - Extract `{test-id}` and `{step}` from the `{date}-{test-id}-{step}.{ext}` convention.

For each failed test, cross-link the evidence rows into that test's "Evidence" sub-section of Step 5's detailed-results — the same file path appears both in the per-test section and in the global manifest.

Write the report to `.artifacts/e2e-reports/report-{name}-{seq}/report.md`.

Example naming: `report-agent-dm-001/report.md` for the first report about agent DM feature.

### Step 8: Register in artifact registry

If Skill 6 (artifact-registry) is available,通过 `register.sh` 注册 e2e-report artifact，详见 `references/artifact-commands.md`。

If Skill 6 is not available, write the report file directly and `git add && git commit`.

### Step 9: Update coverage matrix

Update `.artifacts/coverage/coverage-matrix.md`:
- Mark newly covered user flows as "E2E covered" (if new cases passed)
- Flag any regressions (previously covered flows now broken)
- Update pass/fail counts
- Timestamp the update

If Skill 6 is available, use `update-status.sh` to advance the coverage-matrix artifact status if needed.

## Output

| Artifact | Location | Description |
|----------|----------|-------------|
| e2e-report | `.artifacts/e2e-reports/report-{name}-{seq}/report.md` | Structured test report |
| Evidence files | Test output directories (referenced by path) | Screenshots, captures, JSON responses |
| Updated coverage-matrix | `.artifacts/coverage/coverage-matrix.md` | Reflects latest test results |

## Report structure

The e2e-report uses the template at `templates/e2e-report.md`. Key sections:

1. **Result summary table** -- at-a-glance pass/fail by category
2. **Regression failures** -- called out in a dedicated section, never buried in details
3. **Detailed results** -- per-test: steps, expected, actual, evidence
4. **Failure context** -- auto-collected debugging info for each failure
5. **Evidence manifest** -- all captured files with paths

## Decision: regression failure severity

A regression failure is more severe than a new-case failure because:
- New-case failure: the new feature doesn't work yet (expected during development)
- Regression failure: something that **used to work** is now broken (unexpected damage)

The report uses this hierarchy. If any regression case fails, the report's top-level status is `regression-failure` rather than just `partial-pass`. This signals that the developer should fix regressions before iterating on the new feature.

## Script reference

| Script | Purpose | Key params |
|--------|---------|------------|
| `scripts/run-e2e.sh` | Unified E2E entry point | `--project-root`, `--test-diff-id`, `--dry-run` |
| `scripts/env-check.sh` | Pre-flight dependency check | `--project-root`, `--dry-run` |
| `scripts/self-test.sh` | Verify all scripts work | `--dry-run` |

All scripts: `#!/bin/bash` + `set -euo pipefail`, support `--help` and `--dry-run`.

## Artifact interaction

| Direction | Artifact type | Location |
|-----------|--------------|----------|
| Read | test-diff | `.artifacts/test-diffs/` |
| Read | coverage-matrix | `.artifacts/coverage/` |
| Write | e2e-report | `.artifacts/e2e-reports/` |
| Update | coverage-matrix | `.artifacts/coverage/` |

Skill 6 path: `/home/yaosh/.claude/skills/artifact-registry`

## Reference files

| File | Purpose |
|------|---------|
| `references/evidence-rules.md` | Evidence collection rules (naming, timing, storage) |
| `references/artifact-commands.md` | Skill 6 artifact-registry interaction commands |

## Evidence reference

Detailed evidence collection rules are in `references/evidence-rules.md`. The rules cover:
- Naming conventions for captured files
- Content requirements (must independently prove the test result)
- Timing of captures (when during test execution to take them)
- Storage location (stay in test output dirs, referenced by path)

## Anti-hallucination rules

1. **Run, don't simulate**: actually execute `pytest` and capture real output. Never fabricate test results.
2. **Evidence or it didn't happen**: every pass/fail claim must have a traceback, stdout snippet, or captured file.
3. **Classification is mechanical**: new vs regression is determined by test-diff content, not by judgment.
4. **Failure context is automated**: collect logs/process state via scripts, not from memory.
5. **Report reflects reality**: if 3 tests failed, report 3 failures. Do not round, summarize, or omit.
