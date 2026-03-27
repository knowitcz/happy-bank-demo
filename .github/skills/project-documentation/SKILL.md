---
name: 'project-documentation'
description: 'Documentation taxonomy and navigation guide. Helps agents locate relevant documentation areas by domain, role, or topic. Maintained exclusively by the Documentation Specialist. USE FOR: finding the right docs area before making decisions, checking prior decisions, verifying alignment with project direction. DO NOT USE FOR: writing documentation (invoke the Documentation Specialist agent instead).'
---

# Project Documentation

This skill helps agents find the right documentation area and propagate findings for documentation. The **Documentation Specialist** maintains this taxonomy — do not modify it yourself.

## When to Use

- You need to check if a topic is already documented before making decisions
- You need context about prior decisions, analyses, or conventions
- You want to verify your approach aligns with documented project direction
- You have a finding, decision, or conclusion that should be recorded

## Documentation Structure

```
docs/
├── <domain>/                  # Business domain groupings (e.g., HB-9/)
│   ├── <topic>.md             # Single-topic files, ≤400 lines
│   ├── analysis-developers.md # Role-scoped analysis
│   └── analysis-testers.md    # Role-scoped analysis
├── pending-decisions/         # Items awaiting human input
│   └── <decision>.md          # One file per undecided item
├── lessons-learned/           # Post-mortems and prevention notes
│   └── <topic>.md
├── simplification-backlog/    # Future improvement opportunities with triggers
│   └── <area>.md
├── bug-reporting/             # Bug reporting guides
└── test-strategy/             # Testing strategy docs

.github/instructions/
├── <scope>.instructions.md    # Coding rules with applyTo frontmatter
└── ...
```

### Structure Principles

1. **Same domain nearby** — related knowledge lives in the same folder
2. **Same role nearby** — role-specific views of a topic are adjacent files in the domain folder
3. **Undecided items isolated** — anything agents cannot resolve goes to `docs/pending-decisions/` for human decision
4. **AI-friendly sizing** — 300–500 lines per file, single topic, clear heading hierarchy
5. **Cross-linked, not duplicated** — content exists in exactly one place; related docs link to each other

## How to Find Documentation

This is a **dispatcher table** — it maps what you need to where to look. Use workspace tools (directory listing, file search) to discover specific files within each area.

| Looking for… | Look in… | File conventions |
|---|---|---|
| Project fundamentals (stack, architecture, domain models) | `docs/project-overview/` | One file per topic |
| Feature/issue analysis (business + technical) | `docs/<issue-id>/` (e.g., `docs/HB-9/`) | `analysis-developers.md`, `analysis-testers.md` |
| Pending decisions awaiting human input | `docs/pending-decisions/` | One file per decision |
| Lessons learned, post-mortems | `docs/lessons-learned/` | One file per incident/lesson |
| Future simplification opportunities | `docs/simplification-backlog/` | One file per module area, markdown table |
| Bug reporting guidelines | `docs/bug-reporting/` | — |
| Testing strategy | `docs/test-strategy/` | — |
| Agent system design & workflows | `docs/agent-system/` | — |
| Coding conventions & rules (file-scoped) | `.github/instructions/` | `<scope>.instructions.md` with `applyTo` |

### Discovery Steps

1. Identify the **area** from the dispatcher table above
2. **List the directory** to see available files
3. **Read file headings** to confirm relevance — files use clear heading hierarchy
4. **Follow cross-links** — documents link to related docs; content lives in exactly one place

## Propagation Rule — For All Agents

When you discover, decide, or conclude something during your work that could benefit future tasks — **do not write it to docs yourself**. Instead, propagate it upward to the orchestrator:

1. Include a `### Documentation Note` section in your output
2. Describe the finding, decision, or conclusion concisely
3. The orchestrator will batch these and pass them to the **Documentation Specialist**

### What Qualifies as Documentation-Worthy

- Architectural decisions and their rationale
- Business rule interpretations or clarifications from the human
- Edge cases discovered during analysis, implementation, or testing
- Constraint clarifications

### Simplification Notes — Future Improvement Opportunities

When you notice an area that works correctly but could be simplified under a future condition, emit a `### Simplification Note` instead of a `### Documentation Note`:

- **Owner**: your role (e.g., architect, implementor)
- **Scope**: file path + line range, or documentation path
- **Note**: what could be simplified and why
- **Trigger**: condition that makes this actionable (e.g., "when a third transaction type is added")

Only emit when the opportunity is **non-obvious** and has a **clear trigger condition** (not "someday"). The orchestrator routes these to the Documentation Specialist for storage in `docs/simplification-backlog/`.
- Lessons from debugging or failed approaches
- Convention decisions that should apply going forward
- Items that agents could not resolve and need human input
