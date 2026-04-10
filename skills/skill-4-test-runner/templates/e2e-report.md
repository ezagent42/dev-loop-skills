---
type: e2e-report
id: {auto}
status: executed
producer: skill-4
created_at: "{date}"
trigger: "{test-diff-xxx / manual}"
related:
  - {test-diff-id}
  - {coverage-matrix-id}
evidence: []
---

# E2E Report: {date}

## Basic info
- Date: {date}
- Branch: {git branch}
- Commit: {git short hash}
- Trigger: {test-diff-xxx / manual / regression check}
- Suite: {test directory path}
- Duration: {total execution time}

## Result summary

| Category | passed | failed | error | skipped | total |
|----------|--------|--------|-------|---------|-------|
| New case | | | | | |
| Regression case | | | | | |
| Total | | | | | |

**Overall status**: {all-pass / new-case-failure / regression-failure}

## Regression failures (HIGH PRIORITY)

> If any regression case failed, list them here. These indicate the new feature broke existing functionality.

{If no regression failures: "None -- all regression cases passed."}

{For each regression failure:}

### REGRESSION: {test function name}

- **File**: {test file path}:{line number}
- **Previously**: passed (baseline from coverage-matrix)
- **Now**: failed
- **Impact**: {which user flow / feature is affected}

**Traceback**:
```
{full pytest traceback}
```

**Failure context**:
- Related logs: {log snippet or path to log file}
- Process state: {relevant processes alive/dead}
- Likely cause: {brief analysis based on traceback and context}

**Evidence**:
- {evidence file path and type}

---

## Detailed results

### New cases

{For each new test case:}

#### {test function name} -- {passed/failed/error/skipped}

- **File**: {test file path}:{line number}
- **Source**: {test-diff-id}
- **Duration**: {time}

**Steps**:
1. {step description} -- {result}
2. {step description} -- {result}
3. ...

**Expected**: {what should happen}
**Actual**: {what actually happened}

**Evidence**:
- {evidence file path and type}

{If failed, include traceback and failure context}

---

### Regression cases

{For each regression test case:}

#### {test function name} -- {passed/failed/error/skipped}

- **File**: {test file path}:{line number}
- **Baseline status**: passed
- **Duration**: {time}

**Evidence**:
- {evidence file path and type}

{If failed, include full details as in regression failures section above}

---

## Newly discovered issues

> Problems noticed during testing that are not direct test failures (e.g., slow performance, deprecation warnings, flaky behavior, unexpected log output).

{If none: "No new issues discovered."}

{For each issue:}

### {issue title}

- **Severity**: {low / medium / high}
- **Observed during**: {test function name}
- **Description**: {what was noticed}
- **Evidence**: {relevant file path or log snippet}
- **Suggested action**: {what to do about it}

## Evidence manifest

> All evidence files produced during this test run.

| File | Type | Test | Step | Tool |
|------|------|------|------|------|
| {path} | {terminal-capture/screenshot/api-response} | {test-id} | {step} | {zellij/asciinema/playwright/curl} |

## Environment

- **OS**: {uname -a}
- **Python**: {python --version}
- **pytest**: {pytest --version}
- **Key packages**: {relevant package versions}
- **Services**: {list of external services and their status}
