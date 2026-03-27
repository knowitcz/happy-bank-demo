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
| `docs/` | Project documentation (managed by documentation-specialist) |
| `.github/instructions/` | Copilot instruction files with `applyTo` scoping |
| `.github/skills/` | Copilot skill directories for agent-consumable domain knowledge |
| `migrations/` | Alembic migration scripts |
| `resources/` | Static assets, SQL seed data, web frontend |

## Related Documentation

- Project overview → [overview.md](overview.md)
- Domain concepts → [domain-concepts.md](domain-concepts.md)
- Pending: data flow diagram → [../pending-decisions/data-flow-diagram.md](../pending-decisions/data-flow-diagram.md)
