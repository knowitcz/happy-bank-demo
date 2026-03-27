# Configuration Files

Overview of configuration and data files used by the Happy Bank project.

## Project Configuration

| File | Purpose | When to update |
|---|---|---|
| `pyproject.toml` | Project metadata, dependencies, `ruff` linter settings, Python version target | When adding/removing dependencies or changing linter rules |
| `alembic.ini` | Alembic migration framework settings (DB URL, script location) | Rarely — only if migration infrastructure changes |

## Database

| File | Purpose | When to update |
|---|---|---|
| `migrations/env.py` | Alembic environment — connects models to migration engine | When changing DB connection logic or adding new model bases |
| `migrations/versions/*.py` | Individual migration scripts (auto-generated or hand-written) | Each schema change gets a new migration file |

## Seed Data

| File | Purpose | When to update |
|---|---|---|
| `resources/data/default_clients.sql` | SQL seed data for initial clients | When the default test/demo dataset changes |
| `resources/data/default_accounts.sql` | SQL seed data for initial accounts | When the default test/demo dataset changes |

## Copilot Configuration

| File / Directory | Purpose | When to update |
|---|---|---|
| `.github/copilot-instructions.md` | Project-wide conventions for all agents | When generic rules change (requires human confirmation) |
| `.github/instructions/*.instructions.md` | Scoped coding rules with `applyTo` frontmatter | When file-type-specific conventions change |
| `.github/skills/*/SKILL.md` | Domain knowledge packaged for agent consumption | When domain knowledge evolves |
| `.github/agents/*.agent.md` | Agent role definitions and behaviour rules | When agent responsibilities change |
