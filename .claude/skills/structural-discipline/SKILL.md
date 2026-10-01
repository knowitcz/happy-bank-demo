---
name: structural-discipline
description: 'AI-readability and structural health rules: file/function/class size and function-parameter-count limits by category, decomposition patterns, import hygiene, fragmentation detection, and single-responsibility / separation-of-concerns enforcement at interfaces where layers meet. Referenced by the architect, implementor, and tester subagents and the `/solve` orchestrator.'
---

# Structural Discipline – AI-Readability & Code Health

This skill defines size limits, decomposition rules, and import hygiene standards that ensure codebases remain AI-agent-friendly. These rules are language-agnostic and apply to any project.

## When to Use

Use this skill when:
- Reviewing code changes for structural health
- Implementing new code (pre-submission size check)
- Running final gate checks on cumulative file growth
- Proposing file splits or function extractions

## Why This Exists

AI agents read files in context-window-sized chunks. When a file exceeds ~300 lines, agents need multiple reads, partial context causes incorrect edits, and token costs rise sharply. These size limits are structural prerequisites for reliable AI-assisted development — not stylistic preferences.

The same reliability argument extends to interfaces: an agent reasons about one layer by reading the contract it exposes to the next. A contract that conflates two concerns forces the agent to load and reason about both every time either is touched, and quietly couples layers that should evolve independently. Single-responsibility at layer boundaries (Step 1 interface gate) is therefore enforced with the same hard-gate weight as the size limits.

## Step-by-Step Assessment

For every function, class, or file affected by a change, perform this assessment on the **resulting** code (not just the diff).

### Step 1 — Name the Responsibility

Express the single responsibility in 2–3 words (e.g., "calculate totals", "build data table", "load config"). If you cannot name it concisely without conjunctions ("and", "then", "also") → it violates SRP → MUST be split.

This applies equally to files: each file MUST have a name that precisely describes its contents. If the file's purpose requires conjunctions → the file MUST be split.

#### Interface gate (hard gate — every layer boundary, not just API)

An *interface* is any contract where two distinct layers meet: a function signature, a return type, a response/DTO schema, an endpoint contract, or a module's public surface. The two layers may be **technical** (e.g., `api` ↔ `core`, `core` ↔ `pdf`) or **domain** (e.g., validation ↔ order identity/naming). At every such boundary:

- The interface MUST name its single responsibility in 2–3 words without conjunctions — the same test as above, applied to the **contract**, not the implementation.
- The interface MUST communicate that one intention to its consumer. A field, parameter, or return value that serves a second, unrelated consumer intention conflates two concerns → **BLOCKED**, even when no size limit is exceeded.
- **Separation of concerns is this same gate seen from the boundary**: each concern crossing the boundary gets its own interface. Do NOT widen an existing contract to carry a second concern because doing so is "less invasive" or saves a round-trip — least-invasive is never a valid reason to merge two responsibilities onto one contract.

Example (**BLOCKED**): adding `order_id` to a `ValidateResponse` so a download handler can source a filename. `validate` answers *"is this valid?"*; `order_id` answers *"what is this order's identity/filename?"* — two intentions on one contract. Correct: expose the identity concern through its own interface.

### Step 2 — Categorize the Code

| Category | Description | Examples |
|---|---|---|
| **Logic** | Decisions, calculations, branching, data transformation, conditional flows | Calculator functions, validation rules, business logic |
| **Orchestration** | Calling other functions in sequence, assembling results, coordinating a workflow | CLI commands, API endpoints, top-level generators |
| **Declarative** | Uniform, repetitive registration or configuration with NO embedded logic/branching | Route tables, style dictionaries, constant maps, flat form field lists |

If the categorization is unclear (e.g., a function mixes orchestration with non-trivial logic), ask the human to clarify. Once resolved, record the decision so the same ambiguity does not arise again.

**Orchestration does not exempt the interface.** Classifying an endpoint, CLI command, or top-level generator as Orchestration only relaxes its *size* limits (Step 3). Its public contract still must pass the Step 1 interface gate — assembling results internally is allowed; exposing two unrelated concerns on one signature or response schema is not.

### Step 3 — Apply Size Limits

| Category | Function limit | Parameter limit | Class limit | Module (file) limit |
|---|---|---|---|---|
| **Logic** | ~25 lines | ~5 params | ~150 lines | ~300 lines |
| **Orchestration** | ~50 lines | ~7 params | ~200 lines | ~400 lines |
| **Declarative** | ~300 lines | — | — | ~500 lines |
| **Documentation** (`.md`) | — | — | — | 200 lines (hard) |

- Documentation's 200 is a hard cap per `CLAUDE.md` — the ±20% tolerance below does not apply to it
- Exceeding a line limit by more than ~20% = **BLOCKED**
- Exceeding a line limit by less = **NEEDS CHANGES** with a concrete split proposal
- Exceeding the parameter limit (count every parameter of the function/method signature, excluding `self`/`cls`) = **NEEDS CHANGES** with a suggestion to group related parameters into a parameter object / typed model

### Step 4 — Check for Fragmentation

If a function/class is very small (< 5 lines of logic), is used in exactly one place, and its name adds no explanatory value beyond the code itself → it SHOULD be inlined into the caller. Too many tiny pieces harm readability just as much as a God function.

### Step 5 — Propose Concrete Splits

When a file exceeds its limit, propose a split using domain-appropriate patterns. Common approaches:

| Pattern | When to use |
|---|---|
| Package with re-exports | Model files that cover multiple domains |
| Orchestrator + section builders | Generator files with many output sections |
| Thin entry + per-command modules | CLI/API apps with many commands or endpoints |
| Read/write separation | Loader files that both serialize and deserialize |
| Split by feature area | Test files covering multiple business domains |
| Folder of the same name + `README.md` signpost | Documentation file (`docs/`, `tools/*/docs/`) at or over 200 lines — see the `documentation` skill, "Decomposition at the Cap" |
| Split by responsibility into `references/` | AI-asset `.md` (`.claude/**`) over its cap — see the `ai-assets-designer` skill, `references/skill-anatomy.md` |

For specific file-to-split mappings, consult `CLAUDE.md` which may define project-specific split patterns.

For functions/classes that exceed limits, name the extracted sub-functions/classes and describe their responsibilities.

### Step 6 — Check Import Hygiene

Every import MUST target the actual source module, not a barrel `__init__.py` re-export — unless the `__init__.py` IS the intentional public API surface (e.g., a package `__init__.py` that re-exports from sub-modules after a split).

AI agents trace definitions by grepping import paths; barrel imports cost an extra file read every time.

### Step 7 — Determine the Verdict

- Interface conflates two concerns at a layer boundary (Step 1 interface gate) → **BLOCKED**, regardless of size
- Size limit clearly exceeded (>20% over) → **BLOCKED**
- Size limit exceeded (≤20% over) → **NEEDS CHANGES** with a concrete split/extraction proposal
- Parameter count exceeds the category limit (Step 3) → **NEEDS CHANGES** with a suggestion to introduce a parameter object / typed model
- Borderline → raise as 🟡 Important with a concrete proposal. Approve only if the code has a clear internal structure.
- Fragmentation detected → raise as 🟡 Important suggesting inlining
- Import hygiene violation → raise as 🟡 Important

**CRITICAL**: This assessment applies to the WHOLE resulting function/file after the change, not just the lines added in the diff. If a change adds clean lines to an already-too-long function or file, the change MUST include decomposition or be rejected.

## Pre-Submission File Size Check

Before reporting implementation as complete:
1. Check the line count of every file modified or created
2. Verify each file is within its category limit
3. If any file exceeds the limit → decompose before reporting
4. Include the line counts in the output report