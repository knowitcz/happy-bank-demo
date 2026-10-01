---
name: 'documentation'
description: 'Map of Happy Bank documentation: which file documents what, which agent owns and verifies it, when a code change requires a documentation update, the Rationale Test for non-obvious decisions, and how to decompose a documentation file that reaches the 200-line cap. Use when proposing documentation updates during /refine, applying them during /solve, verifying documentation completeness in reviews, or splitting an at-cap documentation file. Triggers on "update the docs", "where does this go in docs", "who owns this documentation", "this doc is too long", "split architecture.md". DO NOT USE FOR: GitHub issue texts (see github-issues), coding rules themselves (see project-conventions), or splitting an AI-asset .md file under .claude/.'
---

# Documentation – Map, Ownership, and Update Rules

This skill tells any participant where Happy Bank project knowledge lives, who verifies changes to it, and which code changes trigger a documentation update.

## When to Use

- Proposing documentation updates during refinement (specialist analysis in `/refine`)
- Applying documentation changes during implementation (implementor in `/solve`)
- Verifying documentation completeness (owning agent per the map; `/solve` final gate)
- Deciding where a new piece of project knowledge belongs
- A documentation file reaches the 200-line cap

## Documentation Map

| File | Contains | Owner (verifies changes) |
|---|---|---|
| `README.md` | Project purpose, setup, how to run — entry point for humans | product-owner |
| `INSTALL.md` | Installation steps | architect |
| `docs/project-overview/overview.md` | Purpose, technology stack, high-level shape | architect |
| `docs/project-overview/architecture.md` | Layers (api → services → repositories → models, validators), dependency rules, data flows | architect |
| `docs/project-overview/coding-conventions.md` | Naming, language, style, error-handling conventions | architect |
| `docs/project-overview/configuration-files.md` | Config/data files (`pyproject.toml`, `alembic.ini`, migrations, …) | architect |
| `docs/project-overview/domain-concepts.md` | Banking domain: clients, accounts, transactions, business rules | product-owner |
| `docs/test-strategy/` | Test framework, layout, fixtures, testing conventions | tester |
| `docs/bug-reporting/` | How to report a bug | tester |
| `docs/pending-decisions/` | One file per item awaiting a human decision | product-owner (business) / architect (technical) |

There is no documentation-specialist agent: the owner verifies, and the **implementor writes the text** inside the same chunk as the code.

**Not living docs** — never update them to describe current behaviour, never treat them as the source of truth:
- `docs/HB-*/` — per-task briefs, analyses and reviews (history). Read for context only.
- `docs/agent-system/` — describes the legacy `.github/` Copilot agent system, not this `.claude/` framework.

## Update Triggers

A code change REQUIRES a documentation update when it:

| Change | Update |
|---|---|
| Adds/removes/renames a module, layer, or architectural dependency | `docs/project-overview/architecture.md` |
| Adds/changes an API endpoint | `architecture.md` (flows) + `README.md` if user-facing |
| Adds/changes a business rule, domain model, or transaction behaviour | `docs/project-overview/domain-concepts.md` |
| Introduces or changes a coding convention | `docs/project-overview/coding-conventions.md` |
| Adds a test file, shared fixture, or testing convention | `docs/test-strategy/` |
| Changes setup, configuration files, migrations, or how the app is run | `README.md` / `INSTALL.md` / `configuration-files.md` |
| Pure refactoring within a module, no interface change | Usually none — verify existing text is still accurate |
| Brings a documentation file to or past 200 lines | Decompose per **Decomposition at the Cap**, in the same change |

## Decomposition at the Cap

Documentation files are capped at 200 lines. A file that reaches it is **decomposed** — never trimmed of content it needs, never split into `<name>1.md`/`<name>2.md`. Root `README.md`/`INSTALL.md` cannot become folders: they extract content into a `docs/` file and keep a pointer.

1. **Prefer a folder over a sibling file.** Convert `<name>.md` into `<name>/`. A sibling `<name>-<topic>.md` is allowed only when exactly one cohesive part leaves and the parent ends ≤150 lines.
2. **Name files by sub-domain.** Group level-2 headers into sub-domains; name each file after its sub-domain. No resulting file under ~30 lines stands alone — it joins its nearest neighbour.
3. **Add a `README.md` signpost** with the original title, the original preamble, and one line per file (link + what it covers) — no level-2 content of its own.
4. **Cap the folder at 15-20 files** (soft 15, hard 20). Over 20, group into 2-4 descriptively-named sub-folders.
5. **Rewrite inbound references in the same change.** Grep the repo (including `.claude/`) for the old path first — a dangling reference means the conversion is incomplete.

A folder plus its signpost is **one** map entry; its owner verifies every file in it.

## Rules

1. **Same chunk**: documentation changes ship in the same chunk as the code they describe — never as a follow-up.
2. **Proposals are specific**: name the file, the section, and the nature of the change (add/modify/remove) — not "update docs".
3. **Owner verifies**: the owning agent (see map) confirms the change is accurate as part of their review.
4. **Drift is a defect**: documentation that contradicts the code after a change is a FIX-level finding, not a suggestion.
5. **Match existing style**: English, tables and short sections; follow the structure already in the file.
6. **Non-obvious decisions carry their rationale**: record *why* — the alternative rejected, the constraint that forced it, the trade-off accepted. A file that only describes current shape, with no reason for a non-obvious choice, is incomplete even if accurate. Put the reason where the target file already keeps reasons (a "Rationale" note, a "Notes" column, a short "Why" line).

## The Rationale Test

Applied by the `rationale-reviewer` agent during `/refine` (planning) and `/solve` (review), and by anyone who hits an undocumented decision. For a non-obvious decision, ask: could a future reader discover *why* it is this way without asking the original author?

| Verdict | When | Effect |
|---|---|---|
| **CLEAR** | The reason is stated, or the decision is self-evident (restates code behaviour, or the only possible reason is a language/framework constraint) | Nothing to do |
| **NEEDS RATIONALE** | No reason is written down, but one defensible candidate exists | Does not block, but ships in the same change (FIX, never a follow-up) — propose the wording; the human confirms or adjusts on review |
| **UNCLEAR INTENT** | No candidate rationale is more plausible than another — a guess, not a recovery | Blocking — per the `/refine`/`/solve` blocking protocols; never resolved by inventing an answer |

**What counts as "non-obvious"** (the test applies only to these):
- A choice with a plausible alternative that was not taken (a rejected design, a workaround, a constraint)
- A limit, threshold, or format not self-explanatory from its value alone (e.g. a transfer limit, a rounding rule)
- A convention, or an exception to one, stated without why it deviates
- NOT flaggable: restating what the code does; a decision whose only possible reason is the language/framework's own constraint; anything already carrying a "Rationale"/"Why"/"Because" note nearby

## Error Handling

| Situation | Action |
|---|---|
| No existing file covers the knowledge | Propose a new `docs/project-overview/<topic>.md` to the user; do not create it unilaterally |
| A documentation file has reached the 200-line cap | Decompose per **Decomposition at the Cap**; never trim content to fit |
| Documentation contradicts observed code behaviour | Report it in your review; the fix belongs to the current change |
| Unclear which file owns a piece of knowledge | Prefer the map; if still ambiguous, ask the user |
| Knowledge found only in `docs/HB-*/` | Treat as history; if still true and needed, propose moving it into a living doc |
| A decision's rationale is unclear or missing | Apply the Rationale Test; do not silently note it and move on |
