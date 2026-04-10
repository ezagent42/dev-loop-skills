# Naming Convention Reference

Consistent naming makes the test suite navigable. These conventions come from the zchat project's existing patterns and extend them for new domains.

## File names

Pattern: `test_{domain}.py`

The domain is the functional area being tested, expressed as a noun or noun phrase:

| Domain | File name | Covers |
|--------|-----------|--------|
| Core lifecycle | `test_e2e.py` | Agent create/send/stop, WeeChat connect, shutdown |
| Zellij operations | `test_zellij_lifecycle.py` | Tab create/close, pane send/read |
| Project management | `test_project.py` | Project create/list/remove/use |
| Authentication | `test_auth.py` | OIDC login, local login, token refresh |
| IRC daemon | `test_irc_daemon.py` | Daemon start/stop, port binding |
| Configuration | `test_config.py` | Config get/set/list |
| Template management | `test_template.py` | Template list/show/set/create |

When a domain has sub-areas that warrant separate files, use `test_{domain}_{subdomain}.py`:

```
test_agent_messaging.py    # agent-to-agent and agent-to-channel messaging
test_agent_lifecycle.py    # agent create/stop/restart/focus/hide
```

## Function names

Pattern: `test_{action}_{target}`

The action is a verb describing what the user does. The target is what they act on:

| Action | Target | Function | User flow |
|--------|--------|----------|-----------|
| create | local_project | `test_create_local_project` | `zchat project create local` |
| list | projects | `test_list_projects` | `zchat project list` |
| remove | project | `test_remove_project` | `zchat project remove local` |
| start | irc_daemon | `test_start_irc_daemon` | `zchat irc daemon start` |
| stop | irc_daemon | `test_stop_irc_daemon` | `zchat irc daemon stop` |
| login | oidc | `test_login_oidc` | `zchat auth login` |
| login | local | `test_login_local` | `zchat auth login --method local` |
| restart | agent | `test_restart_agent` | `zchat agent restart helper` |
| focus | agent | `test_focus_agent` | `zchat agent focus helper` |
| send | agent_text | `test_send_agent_text` | `zchat agent send agent0 "..."` |

### Compound actions

When a test verifies a multi-step flow, name it after the most significant step:

```python
# Tests: create project -> verify config.toml -> verify directory structure
def test_create_local_project(...)

# Tests: stop agent -> verify IRC quit -> verify tab closed
def test_stop_agent_cleans_up(...)
```

### Negative cases

Prefix with the expected behavior, not "fail" or "error":

```python
# Good: describes the expected behavior
def test_create_duplicate_project_rejected(...)
def test_stop_nonexistent_agent_returns_error(...)

# Avoid: ambiguous about what "fails" means
def test_create_project_fails(...)
```

## Fixture names

Fixtures are named by what they **provide**, not how they work:

| Provides | Name | Scope |
|----------|------|-------|
| IRC port for this session | `e2e_port` | session |
| Running ergo server | `ergo_server` | session |
| Zellij session name | `zellij_session` | session |
| Test context dict | `e2e_context` | session |
| CLI runner callable | `zchat_cli` | session |
| IRC probe on #general | `irc_probe` | session |
| Second IRC user (bob) | `bob_probe` | session |
| WeeChat tab name | `weechat_tab` | session |
| Key sender callable | `zellij_send` | session |

New fixtures should follow the same pattern:

```python
# Good: named by what it provides
@pytest.fixture(scope="session")
def charlie_probe(ergo_server):
    """Third IRC client (charlie) for multi-user tests."""

# Good: named by what it provides
@pytest.fixture(scope="function")
def temp_project(e2e_context):
    """Fresh project directory, cleaned up after each test."""

# Avoid: named by implementation detail
@pytest.fixture
def setup_third_user(...)
```

## Marker and docstring conventions

### Markers

Every E2E test gets `@pytest.mark.e2e`. Add `@pytest.mark.order(N)` only when ordering matters (see `pytest-pattern.md`).

```python
@pytest.mark.e2e
@pytest.mark.order(10)
def test_create_local_project(zchat_cli, e2e_context):
```

### Docstrings

The docstring is a one-liner that maps the test to a user flow:

```python
"""Phase 10: zchat project create local -> project dir + config.toml created."""
```

The format is: `Phase N: {user action} -> {observable outcome}`. The phase number matches the `@pytest.mark.order` value when present. For unordered tests, omit "Phase N:".

## Import ordering

Follow standard Python convention:

```python
# stdlib
import os
import time

# third-party
import pytest

# project (only when needed beyond fixtures)
# from zellij_helpers import wait_for_content
```
