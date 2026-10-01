# Happy Bank — Architecture

## Layers

```
API routes (app/api/)           ← HTTP interface, depends on services
    ↓
Services (app/services/)        ← Business logic, depends on repositories and validators
    ↓
Repositories (app/repository/)  ← Data access, depends on models
    ↓
Models (app/models/)            ← Data structures (SQLModel), no business logic
    ↓
Validators (app/validator/)     ← Input validation, independent of I/O
```

## Dependency Rules (strict)

- Each layer may only depend on layers **below** it
- Models must **never** import from services, repositories, or API
- Services must **never** import from API routes
- Validators are standalone — they import models but nothing above
- API routes wire dependencies via FastAPI's `Depends()` in `app/api/dependencies.py`

## Key Directories

| Directory | Purpose |
|---|---|
| `app/models/` | SQLModel table definitions + Pydantic read schemas (`schemas.py`) |
| `app/repository/` | Database CRUD — one repository per model |
| `app/services/` | Business logic — one service per domain concept |
| `app/validator/` | Input validation (`ValidationResult` pattern, no exceptions) |
| `app/api/` | FastAPI routers — one router per domain concept |
| `app/api/dependencies.py` | Dependency injection wiring |
| `docs/` | Project documentation |
| `.github/instructions/` | Copilot instruction files with `applyTo` scoping |
| `.github/skills/` | Copilot skill directories for agent-consumable domain knowledge |
| `migrations/` | Alembic migration scripts |
| `resources/` | Static assets, SQL seed data, web frontend |

## Operational endpoints

`GET /health` (`app/api/health_routes.py` → `HealthService` → `HealthRepository`), mounted at the root, not under `/api/v1`.
Returns 200 `{"status":"ok"}`, or 503 `{"status":"unavailable"}` when the database check fails.

- **Combined liveness + DB readiness on one endpoint** — a human product decision on issue #1. Accepted trade-off: an orchestrator using it as a liveness probe will restart the app during a DB outage. Only `SELECT 1` runs; there is no migrations check.
- **Root path, not `/api/v1`** — it is an infrastructure probe, so its URL stays stable across API versions.
- **Follows the normal layers** (route → service → repository) because it performs I/O.

## Related Documentation

- Project overview → [overview.md](overview.md)
- Domain concepts → [domain-concepts.md](domain-concepts.md)
- Pending: data flow diagram → [../pending-decisions/data-flow-diagram.md](../pending-decisions/data-flow-diagram.md)
