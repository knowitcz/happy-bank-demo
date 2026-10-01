---
name: project-conventions
description: 'Coding conventions for Happy Bank: where code goes in the layered FastAPI app (api → services → repositories → models, standalone validators), dependency direction, cross-cutting design rules (single declaration at boundaries, semantic types), Python rules (3.10 floor, type hints, int money, SQLModel, ValidationResult, logging) and the checks to run (ruff, pytest; no type checker). Load before writing, reviewing, or estimating code in app/, migrations/, or tests. Triggers on "what are the coding conventions", "does this follow project conventions", "where does this code go", "can a service import X", "which Python version / typing style", "how to lint", "how to run the tests", "logging standards". DO NOT USE FOR: file/function size limits or decomposition (structural-discipline), test design and test conventions (test-strategy), documentation placement (documentation).'
---

# Project Conventions – Happy Bank Coding Rules

Signpost to the conventions every code change in this repo follows, and keeper of the rules that have no other home. Consumed by `implementor` and `architect`, and by `/refine` and `/solve`. Where `docs/` already declares a rule, this skill links to it instead of restating it.

## When to Use

- Writing or reviewing code under `app/` or `migrations/`
- Deciding which layer new code belongs to, or whether an import is allowed
- Estimating a change (lint and test scope count toward the estimate)
- Checking a change is ready to report done (Checks section)

## Where the Rules Live

| Topic | Declared in |
|---|---|
| Purpose, technology stack | `docs/project-overview/overview.md` |
| Layer map, dependency rules (strict), key directories, DI wiring via `app/api/dependencies.py` | `docs/project-overview/architecture.md` |
| Language, style, money as `int`, SQLModel, `ValidationResult`, test placement and naming, database/Alembic | `docs/project-overview/coding-conventions.md` |
| Client / Account / Transaction, derived transaction type | `docs/project-overview/domain-concepts.md` |
| `pyproject.toml`, database, seed data, Copilot config files | `docs/project-overview/configuration-files.md` |
| Logging standards for every `.py` file | `.github/instructions/python-log.instructions.md` |
| Size limits | `structural-discipline` skill (the docs mention `.github/skills/` — in Claude Code it is `.claude/skills/structural-discipline/`) |
| Test conventions, HTSM checklist | `test-strategy` skill |

Read the matching doc before the change; do not rely on this table's one-line summaries.

## Code Organization

The repo is one FastAPI app under `app/`, layered top-down: `api/` → `services/` → `repository/` → `models/`, with `validator/` standalone. The one rule everything else rests on: **a layer depends only on layers below it** (full rules: `architecture.md`, Dependency Rules).

- Business logic lives in `services/`, never in routers or repositories.
- Data access lives in `repository/` — one repository per model.
- Expected invalid input returns a `ValidationResult`; exceptions are for unexpected failures.
- Schema changes go through an Alembic migration in `migrations/`, never ad-hoc DDL.
- Tests live next to the code they test (`app/services/test_bank_service.py`).

## Single Declaration at Boundaries

Every value that crosses a boundary is declared once; everything else derives from it.

| Boundary | The single declaration | Everything else |
|---|---|---|
| Model ↔ schema / consumer | The SQLModel definition in `app/models/` | Read schemas, repositories, routers import or derive field names/types |
| Domain rule ↔ code | The service (or validator) that owns the rule | Routers call it; never re-implement the check |
| DI ↔ routers | `app/api/dependencies.py` | Routers take dependencies via `Depends()`, never construct services themselves |
| Config ↔ code | `pyproject.toml` (Python floor, ruff rules) | Never restate a different version or lint rule elsewhere |
| Agent ↔ skill | The skill's own file | The agent names the skill and section, never copies its rules |
| Docs ↔ this skill | The `docs/` file that declares a rule | This skill links to it |

Check before adding any cross-boundary value: *if this changed, would I have to edit it in two places?* If yes, fix the duplication before merging.

## Semantic Types Over Primitives

When the domain has a concept, give it a named type instead of a raw primitive. Introduce one when any answer is yes:

1. Is the concept used in more than one place?
2. Could the value be confused with another value of the same primitive (e.g. `client_id` vs `account_id`)?
3. Does the value have a unit (money in the smallest currency unit)?
4. Does the value carry constraints (non-negative amount, bounded)? → model it with validation

Keep the raw primitive for a one-off local, a counter/index, or a well-named boolean flag. Never use `float` for money. Introduce improvements incrementally during feature work, not as a big-bang refactor; the Architect flags them in review.

## Python Rules With No Other Home

- Python `>=3.10` — the floor is declared once, in `pyproject.toml` (`requires-python`); ruff targets `py310`. Do not use syntax newer than 3.10.
- Managed by `uv`; run tools through `uv run`.
- Modern typing: `X | None`, `list[...]` / `dict[...]` — never `Optional`, `typing.List` / `Dict`.
- Explicit imports only, never `from x import *`.

## Checks

Run before reporting done; both must pass on the touched code.

| Check | Command | Config |
|---|---|---|
| Lint | `uv run ruff check` (add `--fix` only for auto-fixable findings, then re-run) | `[tool.ruff]` in `pyproject.toml` |
| Tests | `uv run pytest` (targeted: `uv run pytest <path>` or `-k "<pattern>"`) | — |

No type checker is configured — do not run or add mypy/pyright. Type hints are still required on every function signature (`coding-conventions.md`, Style).

When estimating, run the same commands on the affected files; pre-existing lint findings or failing tests in touched files are chunk work and count toward the estimate.
