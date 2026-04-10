---
name: using-dev-loop
description: "Dev-loop pipeline router. Use when starting a conversation in a dev-loop enabled project — determines which skill(s) to invoke based on user intent. Covers project onboarding, knowledge Q&A, test planning, test writing, test execution, feature evaluation, and artifact management."
---

<SUBAGENT-STOP>
If you were dispatched as a subagent to execute a specific task, skip this skill.
</SUBAGENT-STOP>

# dev-loop-skills Router

This plugin provides a 7-skill development loop pipeline. When a user's request maps to one of the phases below, invoke the corresponding skill via the `Skill` tool before responding.

## Instruction Priority

1. **User's explicit instructions** (CLAUDE.md, direct requests) — highest priority
2. **Dev-loop skills** — override default behavior where they conflict
3. **Default system prompt** — lowest priority

## Skill Inventory

| Skill | Name | Phase | Purpose |
|-------|------|-------|---------|
| Skill 0 | `project-builder` | Phase 0 — Bootstrap | Onboard a new project: scan code, run tests, generate Skill 1, initialize `.artifacts/` |
| Skill 1 | `project-discussion-*` | Phase 1 — Knowledge | Answer project questions with evidence from `.artifacts/` knowledge base |
| Skill 2 | `test-plan-generator` | Phase 2-3 — Plan | Generate structured test plans (TC-IDs, priorities, sources) from diffs/gaps/eval-docs |
| Skill 3 | `test-code-writer` | Phase 4 — Write | Convert confirmed test-plans into runnable pytest E2E code |
| Skill 4 | `test-runner` | Phase 5 — Execute | Run E2E suite, generate report, distinguish new vs regression failures |
| Skill 5 | `feature-eval` | Phase 1,7 — Evaluate | Simulate (explore before coding) or Verify (record bug, create issue) |
| Skill 6 | `artifact-registry` | Cross-phase | Manage `.artifacts/` — register, query, link, track lifecycle |

## Routing Rules

Match user intent to the correct skill. When in doubt, invoke the skill and let it decide relevance.

### Skill 0 — project-builder
**Trigger:** User wants to onboard a new project, bootstrap dev-loop, or says "bootstrap", "onboard", "set up dev-loop", "scan project", "generate skill 1".
```
Invoke: Skill tool → "project-builder"
```

### Skill 1 — project-discussion-*
**Trigger:** User asks a question about the project's code, architecture, modules, test status, CLI commands, feature internals, or anything answerable from the knowledge base.
```
Invoke: Skill tool → "project-discussion-{project}" (e.g. "project-discussion-zchat")
```

### Skill 2 — test-plan-generator
**Trigger:** User wants a test plan, asks "what should we test", mentions coverage gaps, wants test cases for a diff, or says "Phase 3", "test plan".
```
Invoke: Skill tool → "test-plan-generator"
```

### Skill 3 — test-code-writer
**Trigger:** User wants to implement a test plan, write test code from a plan, or says "write tests", "implement test-plan", "Phase 4", "test-diff".
```
Invoke: Skill tool → "test-code-writer"
```

### Skill 4 — test-runner
**Trigger:** User wants to run tests, execute E2E suite, generate a test report, check regressions, or says "run tests", "Phase 5", "test report".
```
Invoke: Skill tool → "test-runner"
```

### Skill 5 — feature-eval
**Trigger:** User wants to explore a feature idea (simulate), report a bug (verify), compare expected vs actual behavior, or says "eval", "simulate", "verify", "found a bug", "create eval doc", "file an issue".
```
Invoke: Skill tool → "feature-eval"
```

### Skill 6 — artifact-registry
**Trigger:** User asks about artifacts, pipeline status, what's pending/confirmed/executed, or needs to register/query/link artifacts. Also invoke when another skill produces output that should be tracked.
```
Invoke: Skill tool → "artifact-registry"
```

## Phase Flow (Dev Loop Cycle)

The full development loop follows this cycle:

```
Phase 0: Bootstrap (Skill 0)
  │  Scan code, run tests, generate knowledge base
  ▼
Phase 1: Simulate / Explore (Skill 5 simulate mode)
  │  Explore a feature idea, produce eval-doc
  ▼
Phase 2: Plan Tests (Skill 2 from eval-doc)
  │  Generate test plan from eval-doc
  ▼
Phase 3: Plan Tests (Skill 2 from code-diff)
  │  Generate test plan from code changes
  ▼
Phase 4: Write Tests (Skill 3)
  │  Convert test-plan → pytest code
  ▼
Phase 5: Run Tests (Skill 4)
  │  Execute suite, generate report
  ▼
Phase 6: Implement Feature
  │  (Standard coding — no special skill)
  ▼
Phase 7: Verify (Skill 5 verify mode)
  │  Record bugs, create issues
  ▼
Phase 8: Feedback Loop
  │  Route issues back to Phase 2 or Phase 6
  └──→ Phase 2 (new tests needed)
  └──→ Phase 6 (code fix needed)
```

Skill 1 (Knowledge Q&A) and Skill 6 (Artifact Registry) are available **cross-phase** — invoke them whenever project questions arise or artifacts need tracking.

## Multi-Skill Collaboration

Some tasks require multiple skills in sequence:

- **"Bootstrap this project"** → Skill 0, then Skill 6 (register generated artifacts)
- **"I found a bug"** → Skill 5 (verify), then Skill 2 (plan tests for the bug), then Skill 6 (register)
- **"What's our test coverage?"** → Skill 1 (query knowledge), then Skill 6 (check artifact status)
- **"Test this feature end-to-end"** → Skill 2 (plan), Skill 3 (write), Skill 4 (run)

## How to Access Skills

**In Claude Code:** Use the `Skill` tool. When you invoke a skill, its content is loaded — follow it directly. Never use the Read tool on skill files.
