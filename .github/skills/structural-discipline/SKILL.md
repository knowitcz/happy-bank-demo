---
name: structural-discipline
description: 'AI-readability and structural health rules: file/function/class size limits by category, decomposition patterns, import hygiene, and fragmentation detection. Referenced by Architect, Implementor, Executor, Reviewer, and Tester agents.'
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

## Step-by-Step Assessment

For every function, class, or file affected by a change, perform this assessment on the **resulting** code (not just the diff).

### Step 1 — Name the Responsibility

Express the single responsibility in 2–3 words (e.g., "calculate totals", "build data table", "load config"). If you cannot name it concisely without conjunctions ("and", "then", "also") → it violates SRP → MUST be split.

This applies equally to files: each file MUST have a name that precisely describes its contents. If the file's purpose requires conjunctions → the file MUST be split.

### Step 2 — Categorize the Code

| Category | Description | Examples |
|---|---|---|
| **Logic** | Decisions, calculations, branching, data transformation, conditional flows | Calculator functions, validation rules, business logic |
| **Orchestration** | Calling other functions in sequence, assembling results, coordinating a workflow | CLI commands, API endpoints, top-level generators |
| **Declarative** | Uniform, repetitive registration or configuration with NO embedded logic/branching | Route tables, style dictionaries, constant maps, flat form field lists |

If the categorization is unclear (e.g., a function mixes orchestration with non-trivial logic), ask the human to clarify. Once resolved, record the decision so the same ambiguity does not arise again.

### Step 3 — Apply Size Limits

| Category | Function limit | Class limit | Module (file) limit |
|---|---|---|---|
| **Logic** | ~25 lines | ~150 lines | ~300 lines |
| **Orchestration** | ~50 lines | ~200 lines | ~400 lines |
| **Declarative** | ~300 lines | — | ~500 lines |

- Exceeding by more than ~20% = **BLOCKED**
- Exceeding by less = **NEEDS CHANGES** with a concrete split proposal

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

For specific file-to-split mappings, consult `copilot-instructions.md` which may define project-specific split patterns.

For functions/classes that exceed limits, name the extracted sub-functions/classes and describe their responsibilities.

### Step 6 — Check Import Hygiene

Every import MUST target the actual source module, not a barrel `__init__.py` re-export — unless the `__init__.py` IS the intentional public API surface (e.g., a package `__init__.py` that re-exports from sub-modules after a split).

AI agents trace definitions by grepping import paths; barrel imports cost an extra file read every time.

### Step 7 — Determine the Verdict

- Size limit clearly exceeded (>20% over) → **BLOCKED**
- Size limit exceeded (≤20% over) → **NEEDS CHANGES** with a concrete split/extraction proposal
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