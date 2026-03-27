# Happy Bank — Coding Conventions

## Language

- **Code identifiers**: English
- **User-facing text for the human** (issue descriptions, business specs): the language the human uses
- **Structured formats consumed by agents** (review reports, chunk specs): English

## Style

- Follow `ruff` configuration from `pyproject.toml` (line length 88, Python 3.10 target)
- Use Python type hints on all function signatures
- Use `int` for monetary amounts (no `float`) — amounts are in the smallest currency unit
- Use `SQLModel` for both table definitions and read schemas
- Validation returns `ValidationResult`, never raises exceptions for expected invalid input

## File and Function Size Limits

Size limits for files, classes, and functions are defined by the **structural-discipline** skill
(`.github/skills/structural-discipline/SKILL.md`). All agents must consult that skill before
submitting or reviewing code changes.

Key thresholds (summary only — canonical source is the skill):

| Category | Function | Class | File |
|---|---|---|---|
| Logic | ~25 lines | ~150 lines | ~300 lines |
| Orchestration | ~50 lines | ~200 lines | ~400 lines |
| Declarative | ~300 lines | — | ~500 lines |

Exceeding a limit by more than ~20% is **BLOCKED**.

## Testing

- Framework: `pytest`
- Test files live **next to** the code they test (e.g., `app/services/test_bank_service.py`)
- Test naming: `test_{what}_{condition}_{expected_outcome}`
- Run targeted tests: `pytest app/services/test_bank_service.py` or `pytest -k "pattern"`
- Run full suite: `pytest`
- Detailed testing conventions and HTSM checklist → **test-strategy** skill
  (`.github/skills/test-strategy/SKILL.md`)

## Database

- SQLite for development (`app.db`)
- Migrations via Alembic (`alembic upgrade head`)
- Session management: `app/db.py` provides `get_session()`

## Related Documentation

- Project overview → [overview.md](overview.md)
- Architecture → [architecture.md](architecture.md)
- Test strategy (full) → [../test-strategy/test-strategy.md](../test-strategy/test-strategy.md)
