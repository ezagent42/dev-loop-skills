# Playwright E2E Pattern Reference

How to write browser-based E2E tests with automatic screenshot, video, and trace evidence. This is the Web counterpart to `pytest-pattern.md` (terminal apps).

## When to use this pattern

Use Playwright + `pytest-playwright` when the task under test is:
- A Web UI (React / Vue / server-rendered HTML)
- A user flow that crosses page navigations
- A visual regression that a terminal capture cannot prove

If the project is a pure CLI / terminal app, use `pytest-pattern.md` instead.

## Baseline install

```
uv add --group test pytest-playwright
uv run playwright install chromium
```

`pytest-playwright` ships with fixtures (`page`, `browser`, `context`, `browser_context_args`) and three evidence flags that cover the common cases without custom code.

## Evidence flags (prefer these)

Always pass these on the test-runner invocation:

```
pytest tests/e2e/ \
  --browser=chromium \
  --screenshot=only-on-failure \
  --video=retain-on-failure \
  --tracing=retain-on-failure \
  --output=.artifacts/e2e-reports/report-{name}-{seq}/evidence/
```

| Flag | Effect | When it writes |
|------|--------|----------------|
| `--screenshot=only-on-failure` | Capture viewport PNG | On any failed assertion |
| `--video=retain-on-failure` | Record test video (webm) | Records every test; keeps only failed ones |
| `--tracing=retain-on-failure` | Record Playwright trace (zip) | Same as video; open with `playwright show-trace` |
| `--output=<dir>` | Where evidence files land | Runner reads this path to fill evidence manifest |

`only-on-failure` and `retain-on-failure` keep CI runs small — green runs leave no evidence. If the task-plan demands positive-path evidence (e.g., a Yellow/Red task that needs visual proof of success), switch to `--screenshot=on` / `--video=on`.

## Explicit per-step screenshots

When a test has internal checkpoints that should be visible even on green runs (e.g., "form validated", "modal opened", "data submitted"), call `page.screenshot()` directly in the test:

```python
@pytest.mark.e2e
def test_order_submission_flow(page, evidence_dir):
    """Happy-path order submission — capture visual proof at each step."""
    page.goto("http://localhost:3000/checkout")
    page.screenshot(path=f"{evidence_dir}/01-checkout-loaded.png", full_page=True)

    page.fill("[name=email]", "buyer@example.com")
    page.click("button[type=submit]")
    page.screenshot(path=f"{evidence_dir}/02-submitted.png", full_page=True)

    expect(page.get_by_text("Order confirmed")).to_be_visible()
    page.screenshot(path=f"{evidence_dir}/03-confirmed.png", full_page=True)
```

`evidence_dir` is a fixture (shown below) that resolves to the per-test folder inside `--output`.

## Fixtures to add to conftest.py

```python
import os
import pathlib
import pytest


@pytest.fixture
def evidence_dir(pytestconfig, request) -> pathlib.Path:
    """Per-test directory under pytest-playwright's --output root.

    Path layout:
      {--output}/{test-id}/
        01-step-name.png
        02-step-name.png
        ...
    """
    root = pathlib.Path(pytestconfig.getoption("--output") or ".artifacts/pw-output")
    test_id = request.node.name.replace("/", "_")
    d = root / test_id
    d.mkdir(parents=True, exist_ok=True)
    return d


@pytest.fixture(scope="session")
def browser_context_args(browser_context_args):
    """Force a consistent viewport so screenshots diff cleanly."""
    return {
        **browser_context_args,
        "viewport": {"width": 1280, "height": 800},
        "locale": "en-US",
    }
```

The fixed viewport is important: without it, headless vs headed runs produce different sizes and screenshots drift across environments.

## Test function structure

Every Playwright E2E test follows this shape:

```python
@pytest.mark.e2e
def test_{action}_{target}(page, evidence_dir):
    """What user flow this validates."""
    # Arrange: navigate / set up state
    page.goto("http://localhost:3000/...")

    # Act: user actions
    page.click("...")
    page.fill("...", "...")

    # Assert with evidence
    expect(page.locator("...")).to_be_visible()
    page.screenshot(path=f"{evidence_dir}/final.png", full_page=True)
```

## Selectors — prefer semantic

| Priority | Selector | Example |
|----------|----------|---------|
| 1 (best) | Role / accessible name | `page.get_by_role("button", name="Submit")` |
| 2 | Test ID | `page.get_by_test_id("order-confirm")` |
| 3 | Text content | `page.get_by_text("Order confirmed")` |
| 4 (last resort) | CSS / XPath | `page.locator("div.modal > button.primary")` |

Role- and text-based selectors survive visual refactors. CSS selectors break when someone adjusts the DOM. Prefer (1)–(3) so `selector-drift` failures (see [skill-5 verify iteration mode](../../skill-5-feature-eval/SKILL.md)) stay rare.

## Waiting — use auto-waiting, not `sleep`

Playwright locators auto-wait for the element to be actionable. Never use `time.sleep()`:

```python
# Good — auto-waits up to default timeout
page.get_by_role("button", name="Submit").click()
expect(page.get_by_text("Order confirmed")).to_be_visible()

# Bad — flaky; no evidence of what went wrong
time.sleep(2)
assert page.locator(".toast").is_visible()
```

If you genuinely need a longer timeout, pass `timeout=30000` (ms) to the specific locator / expect call, not a global sleep.

## Evidence manifest integration

Evidence written under `--output=<dir>` is auto-discovered by
[skill-4 test-runner](../../skill-4-test-runner/SKILL.md) during Step 4 (Collect evidence). The runner scans the directory tree and fills the e2e-report's evidence manifest automatically — do not hand-write `evidence:` entries when Playwright is producing them.

## When UI tests fail

A failed Playwright test automatically produces:
- `{test-id}/test-failed-1.png` — failure viewport
- `{test-id}/video.webm` — full recording
- `{test-id}/trace.zip` — step-by-step trace

[skill-6 continue-task](../../../../prd2impl/skills/skill-6-continue-task/SKILL.md) in prd2impl uses these artifacts as input to the UI-regression closed loop (screenshot → eval-doc verify → re-plan → re-run). Do not delete the `--output` directory between iterations; the loop depends on it.

## Minimal example: a complete Playwright E2E file

```python
"""E2E tests for the order checkout flow."""

import pytest
from playwright.sync_api import expect


@pytest.mark.e2e
def test_checkout_happy_path(page, evidence_dir, live_server):
    """User completes checkout with valid email -> order confirmed."""
    page.goto(f"{live_server.url}/checkout")
    page.screenshot(path=f"{evidence_dir}/01-loaded.png", full_page=True)

    page.get_by_label("Email").fill("buyer@example.com")
    page.get_by_role("button", name="Submit order").click()

    expect(page.get_by_text("Order confirmed")).to_be_visible(timeout=10_000)
    page.screenshot(path=f"{evidence_dir}/02-confirmed.png", full_page=True)


@pytest.mark.e2e
def test_checkout_rejects_invalid_email(page, evidence_dir, live_server):
    """Invalid email -> error toast, no confirmation."""
    page.goto(f"{live_server.url}/checkout")

    page.get_by_label("Email").fill("not-an-email")
    page.get_by_role("button", name="Submit order").click()

    expect(page.get_by_role("alert")).to_contain_text("valid email")
    expect(page.get_by_text("Order confirmed")).not_to_be_visible()
```

`live_server` is a project-specific fixture that boots the app under test — define it in conftest.py following the project's existing pattern (Flask/FastAPI test client, Vite preview, etc.).
