# Append vs. New File Rules

When adding E2E test cases from a test-plan, the first decision is where the code goes: append to an existing file or create a new one.

## Decision flowchart

```
Is there an existing test file for this domain?
├── No  → Create test_{domain}.py
└── Yes → Is the file under 300 lines?
    ├── Yes → Does the new case share fixtures with existing tests?
    │   ├── Yes → Append to existing file
    │   └── No  → Would adding the case require conflicting fixture changes?
    │       ├── Yes → Create test_{domain}_{subdomain}.py
    │       └── No  → Append to existing file
    └── No  → Create test_{domain}_{subdomain}.py
```

## When to append

Append to an existing file when all three conditions hold:

1. **Same domain**: the new test covers the same functional area as the existing tests in that file. For example, `test_agent_restart` belongs with other agent lifecycle tests in `test_e2e.py`.

2. **File stays manageable**: the file is currently under 300 lines, and adding the new cases won't push it far beyond that. A 280-line file gaining 40 lines of new tests (320 total) is fine. A 290-line file gaining 200 lines should split.

3. **No fixture conflicts**: the new cases can use the existing fixtures without modification, or the needed fixture additions are small (one or two new fixtures in conftest.py). If the new tests need a fundamentally different setup (e.g., a second ergo server on a different port), a new file with its own fixtures is cleaner.

## When to create a new file

Create a new `test_{domain}.py` file when any of these apply:

- **New domain**: the tests cover a functional area that has no existing test file. Examples: `test_project.py` for project CRUD, `test_auth.py` for authentication flows.

- **Large existing file**: the closest matching file is already over 300 lines. Splitting keeps files navigable.

- **Different infrastructure needs**: the tests require a substantially different fixture setup. For example, tests that need two separate IRC servers or a web browser session are better in their own file where the setup intent is clear.

- **Independent lifecycle**: the tests don't depend on state from existing ordered tests. Putting independent tests in a separate file makes it clear they can run in isolation.

## Examples from zchat

| Scenario | Decision | Rationale |
|----------|----------|-----------|
| Add `test_agent_restart` | Append to `test_e2e.py` | Same domain (agent lifecycle), file is under 300 lines, uses existing `zchat_cli` + `irc_probe` |
| Add `test_create_local_project` | New `test_project.py` | New domain (project CRUD), doesn't need ergo/IRC fixtures |
| Add `test_auth_oidc_flow` | New `test_auth.py` | New domain (auth), needs different infrastructure (mock OIDC provider) |
| Add `test_agent_focus_hide` | Append to `test_e2e.py` | Same domain, uses same fixtures, small addition |
| Add 15 IRC messaging tests | New `test_irc_messaging.py` | Would push test_e2e.py well over 300 lines |

## Conftest changes

### Small additions: append

When adding one or two fixtures to support new test cases, append them to the existing `conftest.py`. Place them after the existing fixtures, maintaining dependency order.

### Large additions: consider a domain conftest

If a new test file needs many new fixtures (5+) that are specific to its domain, consider creating a `conftest.py` in a subdirectory:

```
tests/e2e/
├── conftest.py              # shared infrastructure (ergo, zellij, etc.)
├── test_e2e.py              # core lifecycle tests
├── test_zellij_lifecycle.py # zellij-specific tests
└── auth/
    ├── conftest.py          # auth-specific fixtures (mock OIDC, etc.)
    └── test_auth.py
```

This is rare for most projects. Default to adding fixtures to the main conftest.py unless there's a clear separation of concerns.

## Ordering across files

When tests in a new file depend on state from tests in an existing file (e.g., "agent must already be created"), use `@pytest.mark.order(N)` with numbers that slot into the global sequence. pytest-order works across files.

When tests in a new file are fully independent, omit `@pytest.mark.order` entirely. This signals to readers that these tests don't depend on external state.
