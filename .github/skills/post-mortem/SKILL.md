---
name: 'post-mortem'
description: 'Root-cause taxonomy, comparison checklist, and propagation decision matrix for retrospective bug-fix analysis. Used by the Post-Mortem Analyst agent after a bug fix ships. DO NOT USE FOR: writing fixes (see implementor agent), designing test plans (see test-strategy skill), filing bugs (see github-issues skill).'
---

# Post-Mortem — Domain Knowledge for Retrospective Analysis

Root-cause classifications, comparison checklist, and propagation rules consumed by the Post-Mortem Analyst agent. For the analysis workflow, see the `post-mortem-analyst` agent file.

## When to Use

Use this skill when:
- Classifying the root cause of a shipped bug fix
- Comparing an original refinement analysis against the actual fix
- Deciding which project artefacts need updating to prevent recurrence
- Checking whether a bug is a recurrence of a prior lessons-learned entry

## 1. Root-Cause Taxonomy

| Category | Definition | Typical Signals | Banking Example |
|---|---|---|---|
| `analysis-gap` | The analysis phase missed a scenario that should have been caught | Fix touches files/logic not mentioned in the Refiner's analysis | Overdraft check was not considered for joint accounts |
| `test-gap` | The test plan was correct but test coverage was incomplete | A test case for the failing scenario is absent despite the plan listing it | Transfer test existed but only covered same-currency transfers |
| `specification-gap` | Acceptance criteria were ambiguous or incomplete | The fix satisfies a behaviour the AC neither required nor prohibited | AC said "reject negative amounts" but was silent on zero-amount transfers |
| `domain-knowledge-gap` | A business rule or domain constraint was unknown to the team | The fix adds a rule not found anywhere in existing docs or skills | Regulatory hold period for large transfers was not documented |
| `integration-gap` | Components were correct in isolation but failed in combination | Unit tests pass; the bug only reproduces via an API or end-to-end path | Account balance update succeeded but transaction log was not created |
| `regression` | A prior change broke existing behaviour; no regression test existed | `git bisect` points to a specific prior commit; the old behaviour had no test | Refactoring the account model silently dropped the `is_active` check |

### Classification Rules

1. Assign **one** primary category. If two seem equally valid, pick the one closest to the origin of the miss (earlier in the pipeline wins).
2. A bug is `regression` only if a previously working behaviour broke. New features that were never correct are not regressions.
3. `integration-gap` requires that each component has passing unit tests — otherwise it is `test-gap`.

## 2. Comparison Checklist

Walk through each item when comparing the original analysis against the actual fix.

| # | Question | If NO → likely category |
|---|---|---|
| 1 | Were the affected files predicted correctly by the Refiner's analysis? | `analysis-gap` |
| 2 | Did the test plan cover the failing scenario? | `test-gap` |
| 3 | Were edge cases from the HTSM analysis relevant to this bug? | `test-gap` or `analysis-gap` |
| 4 | Were there prior `### Documentation Note` items hinting at this risk? | `analysis-gap` (signal was ignored) |
| 5 | Was there a `docs/lessons-learned/` entry for a similar bug class? | Potential **recurrence** |
| 6 | Did the PO's acceptance criteria cover the failing behaviour? | `specification-gap` |
| 7 | Was the root cause in a layer included in the specialist fan-out? | `analysis-gap` (wrong specialists invoked) |
| 8 | Was the business rule documented in `docs/` or a skill's `references/`? | `domain-knowledge-gap` |
| 9 | Did the bug only manifest when multiple components interacted? | `integration-gap` |
| 10 | Did `git bisect` trace the bug to a prior commit that had no regression test? | `regression` |

## 3. Propagation Decision Matrix

After classification, determine which artefacts need updating.

| Target | Path | `analysis-gap` | `test-gap` | `specification-gap` | `domain-knowledge-gap` | `integration-gap` | `regression` |
|---|---|---|---|---|---|---|---|
| Lessons learned | `docs/lessons-learned/` | MUST | MUST | MUST | MUST | MUST | MUST |
| Instruction file | `.github/instructions/` | SHOULD | SHOULD | — | — | COULD | SHOULD |
| Skill reference | `.github/skills/` | COULD | COULD | COULD | SHOULD | COULD | — |
| Agent workflow | `.github/agents/` | — | — | — | — | — | — |
| Orchestrator | Refiner / Executor | — | — | — | — | — | — |

### Recurrence Escalation

When the recurrence check (Step 5 of the agent workflow) finds a prior lessons-learned entry for the same bug class, escalate every non-MUST cell by one level:

| Original | Escalated |
|---|---|
| — | COULD |
| COULD | SHOULD |
| SHOULD | MUST |
| MUST | MUST (unchanged) |

This ensures that repeated failures receive stronger preventive measures.

### Priority Definitions

| Priority | Meaning |
|---|---|
| **MUST** | High recurrence risk — same class of bug is likely without this change |
| **SHOULD** | Moderate risk — improves resilience but not strictly required |
| **COULD** | Low risk — nice-to-have improvement |
| **—** | Not applicable for this root-cause category (skip unless escalated) |

## Error Handling

| Situation | Action |
|---|---|
| Root cause fits two categories equally | Pick the category closest to the origin of the miss (earliest pipeline stage) |
| No Refiner analysis exists for the issue | Mark checklist items 1, 3, 4, 7 as N/A; classify based on available evidence |
| `docs/lessons-learned/` directory is empty | Treat every bug as NEW (no recurrence check possible) |
| Agent is unsure about recurrence match | Flag as "POSSIBLE RECURRENCE" and let the Executor decide |
