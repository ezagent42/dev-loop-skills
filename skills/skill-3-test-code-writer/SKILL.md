---
name: "test-code-writer"
description: "Converts a confirmed test-plan into runnable pytest E2E code that integrates with the project's existing test suite. Handles fixture reuse, file placement (append vs. new), and naming conventions. Trigger: 'write tests from plan', 'implement test-plan', 'add e2e cases', 'generate test code', 'test-diff', or Phase 4 of the dev-loop pipeline."
---

# test-code-writer

> Phase 4 of the dev-loop pipeline: turn a confirmed test-plan into real, runnable E2E test code that lives permanently in the project's test suite.

## Why this skill exists

A confirmed test-plan is a design document -- it describes what to test, not how. Translating plans into working pytest code requires understanding the project's existing test infrastructure: which fixtures exist, how evidence is collected, where files live, and what naming conventions the team follows. This skill bridges that gap by reading the plan, querying the project's Skill 1 for infrastructure details, and producing test code that fits seamlessly into the existing suite.

The tests this skill writes are not throwaway scaffolding. They become permanent members of the project's E2E test suite, subject to the same quality standards as hand-written tests.

## When to trigger

**Good triggers:**
- A test-plan in `.artifacts/test-plans/` has status `confirmed` and needs implementation
- User says "write tests from plan", "implement test-plan", "add e2e cases"
- Phase 4 of the dev-loop pipeline is next
- User wants to add E2E test cases to an existing suite
- A test-diff needs to be generated

**Not this skill:**
- Running existing tests (that is Skill 4, test-runner)
- Generating a test plan from eval-docs (that is Skill 2, test-plan-generator)
- Unit tests (this skill focuses on E2E)
- Debugging test failures (that is Skill 1 discussion + Skill 5 eval)

## Input

| Source | Content |
|--------|---------|
| `.artifacts/test-plans/` | Confirmed test-plan markdown (YAML frontmatter with `status: confirmed`) |
| Skill 1 (project-discussion) | Test pipeline info: framework, E2E directory, fixture list, naming conventions, evidence collection |
| Project test suite | Existing `conftest.py`, test files, shared helpers -- the code to integrate with |

## Execution flow

### Step 1: Read the confirmed test-plan

Find the target test-plan in `.artifacts/test-plans/`. If Skill 6 (artifact-registry) is available，通过 `query.sh --type test-plan --status confirmed` 查询，详见 `references/artifact-commands.md`。Without Skill 6, scan `.artifacts/test-plans/` for files whose frontmatter has `status: confirmed`.

Read the plan fully. Extract:
- **Test cases**: each case's ID, description, preconditions, steps, expected outcome
- **Domain**: which functional area the tests cover (agent lifecycle, IRC messaging, project management, etc.)
- **Dependencies**: which fixtures or services each case needs

### Step 2: Query Skill 1 for test infrastructure

Load the project's Skill 1 (project-discussion) to understand how E2E tests work in this project. The key information lives in Skill 1's "Test Pipeline Info" section:

- **Framework**: e.g., pytest + pytest-order + pytest-asyncio
- **E2E directory**: e.g., `tests/e2e/`
- **conftest location**: e.g., `tests/e2e/conftest.py`
- **Existing fixtures**: names, scopes, what they provide
- **Naming convention**: file names (`test_{domain}.py`), function names (`test_{action}_{target}`)
- **Evidence tools**: IrcProbe, zellij helpers, how they work
- **Markers**: `@pytest.mark.e2e`, ordering via `@pytest.mark.order(N)`
- **Shared helpers**: `tests/shared/` directory contents

Also read the actual conftest.py and existing test files to understand current patterns firsthand. The Skill 1 summary is a starting point; the code is the source of truth.

### Step 3: Plan the code changes

First, **classify the test surface**:

- If the test exercises a **Web UI** (browser navigation, DOM assertions, visual checkpoints) → follow `references/playwright-pattern.md`. Evidence (screenshot/video/trace) is produced automatically via `pytest-playwright` flags; do not hand-roll.
- If the test exercises a **terminal / CLI / IRC** surface → follow `references/pytest-pattern.md`. Evidence is terminal captures via zellij/asciinema.
- If the test exercises an **HTTP API only** → plain `pytest` + `httpx`/`requests`; evidence is saved response JSON.

Signals that suggest a Web UI test: eval-doc mentions "page", "screen", "button", "form"; coverage-matrix flags the feature as `web`; the project already has `pytest-playwright` installed.

For each test case in the plan, decide:

1. **Which file?** -- Follow the rules in `references/append-rules.md`:
   - If the case's domain matches an existing test file and that file is under 300 lines, append there
   - If the domain is new or the existing file is large, create a new `test_{domain}.py`
   - Never split a single logical test across files

2. **Which fixtures?** -- Check if existing fixtures cover the case's needs:
   - Reuse `e2e_context`, `ergo_server`, `zchat_cli`, `irc_probe`, `bob_probe`, `weechat_tab`, `zellij_send` when they match
   - If a new fixture is needed (e.g., a third IRC user, a second project), define it in conftest.py
   - Prefer session-scoped fixtures for infrastructure (servers, sessions) and function-scoped for per-test state

3. **What order?** -- If the test depends on state from earlier tests (e.g., "agent must already be created"), use `@pytest.mark.order(N)` with a number that slots into the existing sequence. Check `references/pytest-pattern.md` for ordering guidance.

4. **What evidence?** -- Decide how to verify each step:
   - IRC presence: `irc_probe.wait_for_nick()` / `wait_for_nick_gone()`
   - IRC messages: `irc_probe.wait_for_message(pattern)`
   - Terminal output: `zellij_helpers.wait_for_content(session, tab, pattern)`
   - CLI exit code: `result.returncode == 0`
   - File existence: `os.path.isfile(path)`

### Step 4: Write the test code

Generate the actual Python code following the pattern reference matching the classification from Step 3:
- Terminal/CLI/API surface → `references/pytest-pattern.md`
- Web UI surface → `references/playwright-pattern.md` (Playwright + auto-screenshot/video/trace)

Common rules (all patterns):

- Every test function gets `@pytest.mark.e2e`
- Every test function gets a docstring explaining what user flow it validates
- Assertion messages are specific ("agent0 not on IRC after create" not just "assertion failed")
- Timeouts are explicit in wait calls, not implicit
- No bare `time.sleep()` for verification -- always poll with a deadline

For each test case, the structure is:

```python
@pytest.mark.e2e
@pytest.mark.order(N)
def test_{action}_{target}(fixture1, fixture2):
    """Phase N: {user action} -> {expected outcome}."""
    # Arrange: any setup not covered by fixtures
    # Act: perform the user action
    # Assert: collect evidence and verify
```

When adding fixtures to conftest.py:
- Place new fixtures after existing ones, maintaining the dependency order
- Add a docstring that explains what the fixture provides and when to use it
- Use `yield` for cleanup, `return` for pure data

### Step 5: Validate locally

Before declaring done, verify the generated code:

1. **Syntax check**: `python -c "import ast; ast.parse(open('test_file.py').read())"` for each modified file
2. **Import check**: ensure all imports resolve (IrcProbe, zellij, pytest markers, etc.)
3. **Fixture graph**: ensure no circular dependencies and all referenced fixtures exist
4. **Naming**: verify function names follow `test_{action}_{target}` convention
5. **Ordering**: verify `@pytest.mark.order(N)` numbers don't conflict with existing tests

Do NOT run the actual E2E tests -- that is Skill 4's job, and E2E tests require live infrastructure (ergo, zellij, etc.).

### Step 6: Produce the test-diff artifact

Create a test-diff document in `.artifacts/test-diffs/` that records what was added:

```markdown
---
type: test-diff
id: test-diff-NNN
status: draft
producer: skill-3
created_at: "YYYY-MM-DD"
updated_at: "YYYY-MM-DD"
related:
  - <test-plan-id>
evidence: []
---

# Test Diff: <brief description>

## Source
- Test plan: <test-plan-id> (<path>)

## Changes

### New test cases
| File | Function | Order | Domain | Validates |
|------|----------|-------|--------|-----------|
| tests/e2e/test_project.py | test_create_local_project | 10 | project | `zchat project create local` |
| ... | ... | ... | ... | ... |

### New fixtures
| File | Name | Scope | Provides |
|------|------|-------|----------|
| tests/e2e/conftest.py | third_irc_user | session | Third IRC probe for multi-user tests |
| ... | ... | ... | ... |

### Modified files
- `tests/e2e/conftest.py`: added N new fixtures
- `tests/e2e/test_project.py`: new file, M test cases

## Validation
- Syntax: all files pass `ast.parse()`
- Imports: all resolve
- Fixture graph: no circular deps
- Naming: follows convention
- Ordering: no conflicts
```

Register the artifact if Skill 6 is available: 通过 `register.sh` 注册 test-diff，然后通过 `update-status.sh` 将源 test-plan 状态更新为 `executed`。详见 `references/artifact-commands.md`。

## Adapting to project types

This skill works with different project types by querying Skill 1. The core flow is the same; what changes is the evidence collection tooling.

### Terminal applications (zchat pattern)
- **Fixtures**: session-scoped ergo server, zellij session, IRC probes
- **Evidence**: IrcProbe for IRC state, `zellij_helpers.wait_for_content()` for terminal output
- **Ordering**: tests are ordered because later phases depend on earlier state (agent must exist before sending messages)
- **CLI invocation**: through `zchat_cli` fixture that injects `ZCHAT_HOME`

### Web applications (Playwright pattern)
- **Fixtures**: `page`, `browser_context_args` (from pytest-playwright), project-specific `live_server`, custom `evidence_dir` for per-step screenshots
- **Evidence**: auto via `--screenshot=only-on-failure --video=retain-on-failure --tracing=retain-on-failure`; explicit `page.screenshot(path=...)` for positive-path checkpoints
- **Ordering**: typically independent tests; less need for `pytest-order`
- **Invocation**: `page.goto(...)`, role-/text-based locators, `expect(...)` auto-waiting
- **Full reference**: `references/playwright-pattern.md`

The skill does not hardcode either pattern. It reads Skill 1's test pipeline info and the actual conftest.py to understand which pattern the project uses.

## Reference files

| File | Purpose | When to read |
|------|---------|-------------|
| `references/pytest-pattern.md` | Terminal/CLI/API pytest E2E: fixtures, markers, ordering, zellij/IRC evidence | Step 4, non-UI tests |
| `references/playwright-pattern.md` | Web UI pytest E2E: Playwright fixtures, auto screenshot/video/trace, selector rules | Step 4, UI tests |
| `references/append-rules.md` | When to append to existing files vs. create new ones | Step 3 (planning) |
| `references/naming-convention.md` | File and function naming rules | Steps 3-4 |
| `references/artifact-commands.md` | Skill 6 artifact-registry interaction commands | Step 6 (register) |

## Artifact interaction

| Direction | Type | Location |
|-----------|------|----------|
| Read | test-plan (confirmed) | `.artifacts/test-plans/` |
| Write | test-diff (draft) | `.artifacts/test-diffs/` |
| Update | test-plan status | `confirmed` -> `executed` |

Skill 6 path: `/home/yaosh/.claude/skills/artifact-registry`

## Quality checklist

Before marking a test-diff as complete, verify:

- [ ] Every test case from the plan has a corresponding test function
- [ ] All test functions have `@pytest.mark.e2e` and a docstring
- [ ] Assertion messages are specific and actionable
- [ ] No hardcoded ports, paths, or credentials -- use fixtures
- [ ] New fixtures added to conftest.py, not inline in test files
- [ ] File and function names follow the project's convention
- [ ] `@pytest.mark.order(N)` numbers don't collide with existing tests
- [ ] Syntax and import validation passed
- [ ] Test-diff artifact registered in `.artifacts/test-diffs/`
- [ ] Source test-plan status updated to `executed`
