* Happy Bank: educational FastAPI banking app (Client, Account, Transaction). Python ≥3.10.
* Python project managed by `uv`. Avoid using `pip`.
* Use English for code, docs, commits, and issue comments.
* Lint: `uv run ruff check <touched files>` — scoped to the change; baseline is not ruff-clean, no `ruff format` gate. Tests: `uv run pytest`. Both MUST pass before a change is done.
* GitHub repo `knowitcz/happy-bank-demo`, remote `happy-bank-demo` (never `origin`), base branch `demo` (never `main`). Ignore other remotes and attached IDE/workspace context.
* Formatted text processed via terminal MUST be passed via a file (`--body-file`, `git commit -F`) — inline arguments corrupt the formatting.
* If there is a specialist agent for an area, you MUST run that subagent
  * If running multiple subagents, run them in parallel if that is safe.
  * If you observe a difficulty (missing tool, incomplete task, unclear instructions, etc.), you MUST report it to the user AND run the `report-difficulty` skill, which decides whether it gets tracked.
* If anything (task, communication, etc) is bigger than limits:
  1. Try to reduce it without losing the essence of the message
  2. If that does not work, YOU MUST STOP AND REPORT THAT
* Reference docs in `docs/project-overview/`: `overview.md`, `architecture.md` (layers, dependency rules), `domain-concepts.md`, `coding-conventions.md`, `configuration-files.md`. Read the relevant one before deciding. Task briefs: `docs/HB-*/`.
* The `session-cost` hook posts cost comments on issues automatically — do not post them by hand.

# Design rules
* Single declaration at boundaries: at any boundary between two independently evolving parts (API vs. service, service vs. repository, an agent vs. its skill, a schema vs. its consumer), a shared identifier or contract has exactly one declaration point; every other location derives it programmatically, never restates it.
  * Before adding a cross-boundary value, ask "if this changed, would I have to edit it in two places?" — if yes, fix the duplication before merging. Worked examples: `project-conventions` skill.

# Limits
* Skills are max 120 lines -> read whole skill in one call
* Code files MUST be max 300 lines -> if bigger, restructure
* Test files MUST be max 400 lines -> if bigger, restructure
* Documentation files MUST be max 200 lines -> if bigger, restructure

# Flow commands

Flows are commands, not skills — a human triggers one at a time. A natural-language request maps to its command; run it, do not improvise the flow.

| Ask | Run |
|---|---|
| "refine issue N", "add acceptance criteria", "scope/estimate issue N" | `/refine N` |
| "solve/implement issue N", "ship issue N", "fix bug N" | `/solve N` |

Both require an explicit issue number; without one, ask for it. `/solve` owns commit, push, and issue close.

# Routing table

| Area | Agent | Invoke for |
|---|---|---|
| Business scope, acceptance criteria, GitHub issues | Product Owner | Requirement definition, issue refinement (executes the `/refine` command), sub-issue creation, scope decisions; unclear AC in any change area |
| Code design, architecture review, LOC estimates | Architect | Reviewing every code change (endpoints, services, data model, validation, migrations, CI, `resources/web/`), technical analysis, complexity estimation |
| Test planning and coverage verification | Tester | Test plans during refinement, coverage checks after implementation — required for endpoints, services, data model, validation, bug fixes |
| Writing code and tests | Implementor | Only during implementation, per chunk spec from the `/solve` command's orchestration — never during refinement |
| Documented-intent / rationale completeness | Rationale Reviewer | Every refinement specialist fan-out, every solve chunk review and final gate — unconditional, not routed by area |
