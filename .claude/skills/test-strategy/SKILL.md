---
name: 'test-strategy'
description: 'Testing conventions, HTSM checklist, fixture patterns, and bug reporting protocol for the Happy Bank project. Triggers on "test plan", "test coverage", "write tests", "HTSM", "test specification", "file a bug". Used by the tester agent when designing test plans and verifying coverage, and by the implementor when writing test code. DO NOT USE FOR: production code conventions (see CLAUDE.md and the project-conventions skill), file size limits (see structural-discipline skill).'
---

# Test Strategy – Happy Bank

Testing conventions and domain knowledge for Happy Bank. See [references/fixture-patterns.md](references/fixture-patterns.md) for reusable test doubles and helpers. See [references/htsm-applied.md](references/htsm-applied.md) for the applied HTSM checklist.

## When to Use

Use this skill when:
- Designing test plans for new or changed features
- Writing or reviewing test code
- Verifying test coverage against acceptance criteria
- Producing test specifications for the implementor
- Filing a bug report (see bug reporting protocol below)

## 1. Framework & Commands

- **pytest** via uv (no pytest-cov configured yet — use `--cov=app` when needed). Always `uv run pytest`, never bare `pytest`/`pip`
- Run all: `uv run pytest app/ -v --tb=short`
- Run specific file: `uv run pytest app/services/test_account_service.py -v`
- Run by keyword: `uv run pytest app/ -k "transfer" -v`

## 2. Test File Organization

Tests live **next to the code they test** (co-located), not in a separate `tests/` directory.

| Test file | Tests for | Layer |
|---|---|---|
| `app/repository/test_account_repository.py` | Account get, withdraw, deposit | Repository |
| `app/repository/test_health_repository.py` | Database health check | Repository |
| `app/services/test_account_service.py` | Account service orchestration | Service |
| `app/services/test_bank_service.py` | Bank service variants (Branch, ATM, Online) | Service |
| `app/services/test_health_service.py` | Health service | Service |
| `app/validator/test_amount_validator.py` | ValidationResult, amount rules | Validator |

New API tests (FastAPI `TestClient`) go in `app/api/test_<name>_routes.py`; none exist yet. Models: `app/models/account.py`.

## 3. Test Naming Convention

Every test function MUST encode the scenario it verifies:

**Pattern**: `test_{what}_{condition}_{expected_outcome}`

Examples from the codebase:
- `test_withdraw_money_insufficient_balance` — what + condition (outcome implied: raises)
- `test_check_health_propagates_repository_errors` — what + condition + outcome
- `test_branchbankservice_deposit` — what + variant (happy path implied)

## 4. Hard Rules

1. **Explicit imports** — import from the actual source module, not through `__init__.py`
2. **File size limits** — test files follow the same limits as production code (see `structural-discipline` skill). Split by business concept, not test type
3. **No production DB in tests** — use `Mock`/`MagicMock` or test doubles for repositories
4. **Test doubles over deep mocking** — prefer `DummyAccount`, `AccountServiceDouble` classes (see fixture patterns)
5. **Dependency injection via FastAPI overrides** — for API tests, override dependencies with `app.dependency_overrides`; always clear in `finally`

## 5. Test Specification Format

When the tester identifies coverage gaps, it produces specifications in this format for the implementor:

```markdown
## Test Specification — [Gap Name]

| Field | Value |
|---|---|
| Test name | `test_{what}_{condition}_{expected_outcome}` |
| Test file | [path to existing or new test file] |
| Module under test | [source module path] |
| Setup | [fixtures, test doubles needed] |
| Action | [function call with inputs] |
| Assertion | [expected output / side effect / exception] |
| Teardown | [cleanup if needed, e.g. `app.dependency_overrides.clear()`] |
```

## 6. HTSM Checklist

> See [references/htsm-applied.md](references/htsm-applied.md) for the full applied Heuristic Test Strategy Model.

Use this checklist during test plan design to ensure systematic coverage.

## 7. Bug Reporting Protocol

When a defect is found during testing, use the structured questionnaire in `docs/bug-reporting/report-helper.md`. Key questions:
1. What is the problem? What exactly happened?
2. Steps to reproduce — what was done before the issue?
3. Specific inputs/data used
4. Is it reproducible? With variant inputs? On other platforms?
5. Version and environment where the issue was found

## Error Handling

| Situation | Action |
|---|---|
| Test file exceeds size limit | Split by business concept; shared fixtures go to `conftest.py` |
| No existing test doubles for a model | Create a `Dummy*` class in the test file (see fixture patterns) |
| API test leaks dependency overrides | Always wrap in `try/finally` with `app.dependency_overrides.clear()` |
| Tester finds gap but cannot write code | Produce a test specification and hand it to the implementor |
| Test gap reveals a design problem (untestable structure) | Escalate to the architect; do not work around it in tests |
| Unclear whether unit or integration test | Default to unit test with mocked dependencies; add integration only if cross-layer behavior is the concern |
