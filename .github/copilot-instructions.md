# Happy Bank — Project Conventions

This file contains project-wide conventions, architecture rules, and domain knowledge that all agents must follow. Agent-specific behavior is defined in each `.agent.md` file — do not duplicate it here.

## Git Organization

This project uses several git remotes and it is necessary to show which remote is operating on. When the remote is specified in the prompt, use that and **ignore any attached workspace/IDE context**.

## Project Knowledge

Full project knowledge lives in `docs/project-overview/`. Read the relevant file before making decisions:

| Topic | File |
|---|---|
| Project overview (stack, Python version) | `docs/project-overview/overview.md` |
| Architecture layers, dependency rules, key directories | `docs/project-overview/architecture.md` |
| Domain concepts (Client, Account, Transaction) | `docs/project-overview/domain-concepts.md` |
| Coding conventions, style, testing, DB | `docs/project-overview/coding-conventions.md` |

Use the `project-documentation` skill to locate documentation beyond these files.

## Specialist Agents

| Agent | Role |
|---|---|
| `product-owner` | Business requirements, acceptance criteria, issue management |
| `architect` | Code quality, clean architecture, SOLID/DRY/KISS review |
| `implementor` | Writes production code and test code (TDD) |
| `tester` | Test plan design, coverage analysis, test specifications |
| `reviewer` | Final review gate — synthesizes all specialist feedback |
| `documentation-specialist` | Maintains all persistent project documentation |
| `post-mortem-analyst` | Retrospective root-cause analysis after bug fixes |

## Routing by Change Area

Orchestrators (Refiner, Executor) use this table to decide which specialists to invoke.

| Change area | Required specialists | Optional |
|---|---|---|
| New API endpoint | architect, tester | product-owner (if AC unclear) |
| Business logic (services) | architect, tester | product-owner |
| Data model change | architect, tester | product-owner |
| Validation rules | architect, tester | — |
| Database migration | architect | tester |
| Documentation only | documentation-specialist | — |
| CI/CD pipeline | architect | — |
| Frontend (resources/web/) | architect | tester |
| Bug fix | architect, tester | post-mortem-analyst (after fix shipped), documentation-specialist (lessons learned) |

## Documentation Ownership

The **documentation-specialist** is the sole writer of persistent documentation. No other agent may create or modify files in `docs/` or `.github/instructions/`. All agents may **read** documentation — use the `project-documentation` skill to locate relevant files.

When any agent discovers, decides, or clarifies something worth recording, it must include a `### Documentation Note` section in its output. Orchestrators batch these and delegate to the documentation-specialist.

When any agent notices an area that works correctly now but could be simplified under a future condition, it must include a `### Simplification Note` section in its output. Orchestrators batch these and route to the documentation-specialist for storage in `docs/simplification-backlog/`. During refinement, specialists check this backlog for entries whose trigger condition is met by the current issue.

## Definition of Done

A feature or bug fix is considered done only when **all** of the following are met:

1. **Code implemented** — all changes follow the project's coding conventions and architecture rules.
2. **Tests passing** — the full test suite passes with no failures; new/changed logic has adequate test coverage.
3. **Documentation propagated** — any documentation-worthy findings include a `### Documentation Note` in the agent output.
4. **Changes committed** — all modified files are committed to Git with a descriptive English commit message referencing the issue number (e.g., `fix: brief description (#12)`).
5. **Commit pushed** — the commit is pushed to the appropriate remote and branch.
6. **Issue closed** — the GitHub issue is closed with a summary comment describing what was done.

Changes **must be committed before** the corresponding GitHub issue is closed. Never close an issue with uncommitted work in the working tree.

## Keeping These Instructions Up to Date

Whenever a change introduces a new architectural rule, layer, module, convention, or significant behavioural constraint, this document must be updated accordingly.

- New section of the codebase → add a corresponding row or paragraph
- Existing rule refined or superseded → update rather than leaving contradictions
- Uncovered area → add a new section

This document **MUST** remain under 300 lines. Only stable, project-wide rules belong here. Context-specific guidance belongs in skills or `.github/instructions/` files. Project-specific knowledge belongs in `docs/`.

**Any modifications to this file require explicit confirmation from the human before being applied.**
