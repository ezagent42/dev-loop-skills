# pytest E2E Pattern Reference

How to write E2E test cases that integrate with the project's existing pytest infrastructure.

## Test function structure

Every E2E test follows a consistent shape:

```python
@pytest.mark.e2e
@pytest.mark.order(N)
def test_{action}_{target}(fixture1, fixture2):
    """Phase N: {user action} -> {expected outcome}."""
    # Arrange
    # Act
    # Assert with evidence
```

The `@pytest.mark.e2e` marker lets the runner select E2E tests specifically (`-m e2e`). The `@pytest.mark.order(N)` controls execution order when tests depend on shared state.

## Using existing fixtures

### Session-scoped infrastructure

These fixtures start once per test session and are shared across all tests. They handle servers, sessions, and long-lived connections:

```python
# e2e_port -- random high port for this session
# ergo_server -- starts ergo IRC on e2e_port, tears down after session
# zellij_session -- headless zellij session name
# e2e_context -- dict with home, project, zellij_session, port
# zchat_cli -- callable: zchat_cli("agent", "create", "agent0")
# irc_probe -- IrcProbe connected to #general as "e2e-probe"
# bob_probe -- second IrcProbe as "bob"
# weechat_tab -- WeeChat running in zellij tab
# zellij_send -- callable: zellij_send("tab_name", "text to type")
```

Requesting a fixture in your test's parameter list is enough -- pytest handles dependency resolution. If your test needs `irc_probe`, pytest ensures `ergo_server` starts first (because `irc_probe` depends on it).

### Choosing the right fixture

| Need | Fixture | Notes |
|------|---------|-------|
| Run a CLI command | `zchat_cli` | Returns `subprocess.CompletedProcess` with stdout/stderr |
| Check if IRC nick exists | `irc_probe` | `irc_probe.wait_for_nick("alice-agent0", timeout=30)` |
| Check nick disappeared | `irc_probe` | `irc_probe.wait_for_nick_gone("name", timeout=10)` |
| Wait for IRC message | `irc_probe` | `irc_probe.wait_for_message("pattern", timeout=15)` |
| Send IRC message as bob | `bob_probe` | `bob_probe.privmsg("#general", "text")` |
| Type in WeeChat | `zellij_send` | `zellij_send(weechat_tab, "/msg #general hello")` |
| Check terminal content | (import zellij_helpers) | `zellij_helpers.wait_for_content(session, tab, "pattern")` |

### When to use shared helpers directly

The `tests/shared/` directory has helpers that are not fixtures but importable modules:

```python
from zellij_helpers import send_keys, capture_pane, wait_for_content
from irc_probe import IrcProbe
from cli_runner import make_cli_runner
```

Use these when you need more control than the fixture provides (e.g., creating a custom IrcProbe with a specific nick).

## Adding new fixtures to conftest.py

Place new fixtures **after** the existing ones, respecting the dependency chain:

```
e2e_port -> ergo_server -> irc_probe
                        -> bob_probe
e2e_port -> e2e_context -> ergo_server
         -> zellij_session -> e2e_context
                           -> weechat_tab
e2e_context -> zchat_cli
```

A new fixture that needs ergo_server goes after `ergo_server`'s definition.

### Fixture scope selection

- **`scope="session"`** for anything expensive to create/destroy: server processes, zellij sessions, IRC connections. This is the default for E2E infrastructure because restarting ergo between every test would be slow and fragile.

- **`scope="function"`** for per-test isolation: temporary files, fresh state objects, test-specific configuration. Use this when the fixture's state must not leak between tests.

- **`scope="module"`** is rarely used in E2E. Prefer session (shared) or function (isolated).

### Fixture template

```python
@pytest.fixture(scope="session")
def new_fixture_name(dependency1, dependency2):
    """One-line description of what this provides.

    Used by: test_action_target, test_other_action
    """
    # Setup
    resource = create_resource(dependency1)
    yield resource
    # Teardown
    resource.cleanup()
```

## Evidence collection patterns

### IRC presence verification

```python
# Wait for nick to appear (agent joined)
assert irc_probe.wait_for_nick("alice-agent0", timeout=30), \
    "alice-agent0 not on IRC after agent create"

# Wait for nick to disappear (agent stopped)
assert irc_probe.wait_for_nick_gone("alice-agent0", timeout=10), \
    "alice-agent0 still on IRC after agent stop"
```

### IRC message verification

```python
# Wait for a message matching a pattern
msg = irc_probe.wait_for_message("Hello from agent0", timeout=30)
assert msg is not None, "agent0 message not received in #general"
assert msg["nick"] == "alice-agent0"
assert msg["channel"] == "#general"
```

### CLI output verification

```python
result = zchat_cli("agent", "list")
assert result.returncode == 0, f"agent list failed: {result.stderr}"
assert "agent0" in result.stdout, "agent0 not in list output"
```

### Terminal content verification

```python
from zellij_helpers import wait_for_content

found = wait_for_content(
    e2e_context["zellij_session"],
    "agent-tab",
    r"Session started",
    timeout=15,
)
assert found, "Agent session did not start within 15s"
```

## Ordering rules

### When ordering matters

Tests that modify shared state need explicit ordering. In the zchat E2E suite, tests follow a lifecycle:

1. WeeChat connects
2. Agent created
3. Agent sends messages
4. Agent interactions
5. Agent stopped
6. Shutdown

If your new test depends on an agent existing, it must run after the "agent create" test.

### Choosing order numbers

- Read existing `@pytest.mark.order(N)` values in the test file
- Pick a number that slots your test into the right position
- Leave gaps (e.g., 10, 20, 30 instead of 1, 2, 3) so future tests can insert between them
- If adding to an existing file with sequential numbering (1, 2, 3...), continue the sequence
- For new files: start at 1 or use 10-based gaps

### When ordering does NOT matter

Tests that are fully independent (each sets up and tears down its own state) don't need ordering. The `test_zellij_lifecycle.py` tests use an `autouse` session fixture and don't use `@pytest.mark.order` because each test is self-contained.

## Assertion messages

Every `assert` gets a message that helps debug failures without reading the code:

```python
# Good: tells you what happened and what was expected
assert irc_probe.wait_for_nick("alice-agent0", timeout=30), \
    "alice-agent0 not on IRC 30s after 'agent create agent0'"

# Bad: requires reading code to understand
assert irc_probe.wait_for_nick("alice-agent0", timeout=30)
```

For CLI failures, include the captured output:

```python
result = zchat_cli("agent", "create", "agent0")
if result.returncode != 0:
    raise RuntimeError(
        f"agent create failed (rc={result.returncode}): "
        f"stdout={result.stdout}, stderr={result.stderr}"
    )
```

## Imports

Standard imports for an E2E test file:

```python
import os
import time
import pytest

# Shared helpers (when needed beyond fixtures)
# from zellij_helpers import wait_for_content, capture_pane
# from irc_probe import IrcProbe
```

Fixtures are requested by parameter name, not imported. The conftest.py's `sys.path` insertion makes shared helpers available.

## Complete example: a new test file

Here is what a complete new test file looks like when generated from a test-plan with two cases:

```python
"""E2E tests for project management commands."""

import os

import pytest


@pytest.mark.e2e
@pytest.mark.order(10)
def test_create_local_project(zchat_cli, e2e_context):
    """Phase 10: zchat project create local -> project dir + config.toml created."""
    result = zchat_cli("project", "create", "local")
    assert result.returncode == 0, f"project create failed: {result.stderr}"

    config_path = os.path.join(
        e2e_context["home"], "projects", "local", "config.toml"
    )
    assert os.path.isfile(config_path), (
        f"config.toml not found at {config_path} after project create"
    )


@pytest.mark.e2e
@pytest.mark.order(11)
def test_list_projects_shows_local(zchat_cli):
    """Phase 11: zchat project list -> shows 'local' project."""
    result = zchat_cli("project", "list")
    assert result.returncode == 0, f"project list failed: {result.stderr}"
    assert "local" in result.stdout, (
        "project 'local' not in list output after create"
    )
```

This file demonstrates:
- Module-level docstring describing the domain
- Standard imports (stdlib then third-party)
- `@pytest.mark.e2e` on every test
- `@pytest.mark.order(N)` with 10-based gaps
- Docstrings mapping phase number to user action and outcome
- Specific assertion messages referencing what was attempted
