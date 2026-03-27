# Agent System – Roles and Workflows

This document describes every agent in the Happy Bank multi-agent system, their responsibilities, and the orchestration workflows that connect them. It is the authoritative reference for understanding how issues travel from raw request to shipped code.

---

## Agent Roster

| Agent | Model | Role |
|---|---|---|
| **Refiner** | Claude Sonnet 4.6 | Orchestrator — refines raw issues into implementation-ready specs |
| **Executor** | Claude Sonnet 4.6 | Orchestrator — drives implementation, review, and shipping |
| **Product Owner** | Claude Sonnet 4.6 | Business definition, acceptance criteria, chunk breakdown |
| **Architect** | Claude Opus 4.6 | Code quality, layer boundaries, SOLID/DRY/KISS, LOC estimates |
| **Implementor** | GPT-5.3-Codex | Writes production code and test code (TDD) |
| **Tester** | GPT-5.4 | Test plan design, coverage analysis, test specifications |
| **Reviewer** | GPT-5.4 | Final review gate — runs tests, inspects UI, verifies coverage, cross-chunk integration, and ship verdict |
| **Documentation Specialist** | Claude Sonnet 4.6 | Sole writer of all persistent documentation |
| **Post-Mortem Analyst** | Claude Opus 4.6 | Root-cause analysis after bug fixes ship |
| **Meta Agent Designer** | Claude Opus 4.6 | Designs and maintains `.agent.md` files |
| **Meta Skill Designer** | Claude Opus 4.6 | Designs and maintains `SKILL.md` files |

---

## Ownership Boundaries

- **Orchestrators** (Refiner, Executor) coordinate specialists; they never write code or docs themselves.
- **Implementor** is the only agent that writes or modifies source code.
- **Documentation Specialist** is the only agent that writes or modifies files in `docs/` or `.github/instructions/`.
- **Meta agents** operate at the system level: they design the agents and skills that define the system.

---

## Refiner — Issue Refinement Workflow

The Refiner takes a raw GitHub issue and produces a fully specified, implementation-ready task definition.

```mermaid
flowchart TD
    A([Raw GitHub Issue]) --> S1

    S1{"Step 1 Labeled bug?"}
    S1 -->|Yes| S1A["Explore subagent: search docs/lessons-learned/ for prior entries"]
    S1 -->|No| S2
    S1A -->|Lesson found| S1B[Include lesson in specialist fan-out — flag recurrence if applicable]
    S1A -->|Not found| S2
    S1B --> S2

    S2[Step 2 — Delegate to Product Owner]
    S2 --> E{PO has blocking Qs?}
    E -->|Yes| F([Ask Human — pause])
    E -->|No| G[PO posts business description as issue comment]

    G --> SB[Explore subagent: check docs/simplification-backlog/ for entries scoped to affected files]
    SB --> H & I & J

    H[Architect affected files, data model, design concerns]
    I[Tester test plan, edge cases, boundary values]
    J[Domain specialist if routing table applies]

    H & I & J --> K[Step 3 — Collect specialist findings]
    K --> L{Specialists have Qs?}
    L -->|Business Q| S2
    L -->|Technical conflict| F2([Escalate to Human])
    L -->|None| M

    M[Step 4 — Extract Documentation + Simplification Notes]
    M --> N{Any notes?}
    N -->|Yes| O[Delegate batch to Documentation Specialist]
    N -->|No| S5
    O --> P{DS result}
    P -->|OK| S5
    P -->|Too large| Q[PO creates follow-up doc issue]
    P -->|Contradiction| R{Resolved within 2 rounds?}
    R -->|Yes| S5
    R -->|No| F3([Escalate to Human])
    Q --> S5

    S5[Step 5 — Commit documentation changes git add + commit + push]
    S5 --> S6

    S6[Step 6 — Architect produces LOC estimate]
    S6 --> T[PO applies budget thresholds]
    T --> U{Decision}
    U -->|Proceed| W
    U -->|Decompose| V[PO creates sub-issues]
    U -->|Flag risk| W
    V --> W

    W[Step 7 — PO breaks scope into ordered chunks with dependencies and verifications]
    W --> X

    X[Step 8 — Post readiness stamp comment on issue]
    X --> Y[Label issue: refined]
    Y --> Z([Ready for Executor])
```

### Refiner Iteration Limits

| Loop | Max rounds | On cap hit |
|---|---|---|
| PO ↔ specialist clarification | 2 | Escalate to human |
| Full specialist re-analysis | 1 | Post findings as-is, flag uncertainties |
| PO decomposition attempts | 2 | Escalate to human if chunks still too large |

---

## Executor — Implementation Workflow

The Executor drives implementation from a refined issue to shipped, committed code. It loops per chunk, then applies a final holistic gate.

```mermaid
flowchart TD
    A([Refined GitHub Issue]) --> RG[Refinement Guard: check for Refiner readiness stamp]
    RG --> RGC{Stamp present?}
    RGC -->|No + not trivial| STOP([Stop — ask human to run Refiner first])
    RGC -->|Yes or trivial| C
    C{Execution mode?}
    C -->|Standard| D[Execute chunks in dependency order]
    C -->|Trivial single file, no business logic| TM[Single-chunk loop — skip final gate]

    subgraph LOOP["Per-Chunk Loop"]
        D --> PC[Pre-check: file sizes per structural-discipline skill]
        PC --> I[Delegate to Implementor with chunk spec + targeted tests]
        I --> AR[Delegate to Architect for design review]
        AR --> AV{Architect verdict}
        AV -->|APPROVED| DV
        AV -->|NEEDS CHANGES| RI[Re-implement]
        RI --> AR
        AV -->|2 rounds exhausted| ESC([Escalate to Human])
        DV["Domain verification if domain specialists named in issue or participated in refinement"]
        DV --> DN["Collect ### Documentation + Simplification Notes from Implementor + Architect"]
        DN --> CK[Mark chunk complete — post progress comment if ≥3 chunks]
        CK --> MK{More chunks?}
        MK -->|Yes| PC
        MK -->|No| ESCAPE
    end

    subgraph ESCAPE["Mid-Execution Escape Check"]
        ES{Scope significantly larger than estimated?}
        ES -->|Yes| EP[Stop — delegate to PO reduce scope or continue]
        ES -->|No| FG
        EP --> EPC{PO decision}
        EPC -->|Reduce| ECR[Commit done work — create follow-up issue]
        EPC -->|Continue ≤2 chunks| FG
    end

    subgraph FG["Final Gate — Standard Mode Only"]
        FG1[Structural health check all modified files vs size limits]
        FG1 --> FG2["Delegate to Reviewer — run full test suite, check coverage, inspect UI, assess cross-chunk integration"]
        FG2 --> FGF["Documentation flush — Documentation + Simplification Notes to Doc Specialist"]
        FGF --> FG8{Reviewer verdict}
        FG8 -->|SHIP| SHIP[Commit all changes — post completion comment on issue]
        FG8 -->|FIX| FIX["One fix cycle: Implementor writes tests / fixes + Architect review"]
        FIX --> FG2
        FG8 -->|FOLLOW-UP| FU[PO creates follow-up issues — ship what's done]
        FG8 -->|REFINE| REFINE[Post reviewer findings as issue comment — stop, do not commit or close]
    end

    SHIP --> PM{Issue labeled bug?}
    PM -->|Yes| PMA[Delegate to Post-Mortem Analyst]
    PMA --> PMR["Route recommendations: Doc Specialist / Meta Skill Designer / Meta Agent Designer"]
    PM -->|No| CLOSE
    PMR --> CLOSE([Issue closed])
    FU --> CLOSE
```

### Executor Iteration Limits

| Loop | Max rounds | On cap hit |
|---|---|---|
| Implementor ↔ architect per chunk | 2 | Escalate to human with both positions |
| Final gate fix cycle | 1 | Ship with known issues as FOLLOW-UP, or escalate |
| Total chunks per execution | 5 | Remaining work becomes follow-up issue |

### Executor Trivial Mode

For single-file changes with no business logic (typo, config, simple bug). Final gate is skipped.

```mermaid
flowchart LR
    A([Trivial issue]) --> B[Implement directly]
    B --> C[Architect review]
    C --> D[Targeted tests only]
    D --> E{Pass?}
    E -->|Yes| F[Commit + close]
    E -->|No| B
```

---

## Bug Fix — Full Flow with Post-Mortem

When an issue is labeled `bug`, both the Refiner and the Executor add extra steps.

```mermaid
flowchart TD
    A([Bug issue opened]) --> RLook[Refiner: read docs/lessons-learned/ for similar prior entries]
    RLook --> RFlag{Prior lesson exists?}
    RFlag -->|Yes — include in specialist fan-out| REF[Normal refinement with recurrence flag]
    RFlag -->|No| REF

    REF --> EXE[Executor: implement per normal loop]
    EXE --> SHIP[Final gate: SHIP verdict]

    SHIP --> PMA[Executor triggers Post-Mortem Analyst]
    PMA --> RCA[Root-cause classification analysis-gap / test-gap / spec-gap / domain-knowledge-gap / integration-gap / regression]
    RCA --> REC[Recurrence check against docs/lessons-learned/]
    REC --> PREC{Recurrence?}
    PREC -->|NEW| PROPS[Propagation recommendations MUST / SHOULD / COULD]
    PREC -->|RECURRENCE| PROPSR[Escalated severity — address why prior prevention failed]
    PROPS & PROPSR --> ROUTE[Executor routes recommendations]

    subgraph ROUTE_TARGETS["Propagation Targets"]
        DS[Documentation Specialist lessons-learned + instructions]
        MSD[Meta Skill Designer skill updates]
        MAD[Meta Agent Designer agent workflow updates]
    end

    ROUTE --> DS & MSD & MAD
```

---

## Documentation Flow

Documentation is a first-class citizen — it flows through every phase.

```mermaid
flowchart TD
    subgraph SPECIALISTS["Specialists (any phase)"]
        SP[Architect / Tester / Implementor / PO / Post-Mortem Analyst]
        SP --> DN["### Documentation Note in their output"]
    end

    subgraph ORCH["Orchestrators (batch & route)"]
        DN --> BATCH[Accumulate notes per phase]
        BATCH --> DS[Delegate batch to Documentation Specialist]
    end

    subgraph DS_FLOW["Documentation Specialist workflow"]
        DS --> SG{Size gate ≤ 3–5 file changes?}
        SG -->|Too large| REF2[Refuse: recommend follow-up issue or smaller batch]
        SG -->|OK| READ[Read existing docs check project-documentation skill]
        READ --> CC{Contradiction check}
        CC -->|Found| BLOCK[Block write escalate to specialists max 2 rounds → human]
        CC -->|None| PLACE[Decide placement: epdate / create / split file]
        PLACE --> WRITE[Write documentation]
        WRITE --> IDX[Update index in project-documentation skill]
        IDX --> REPORT[Report: Changes Made Cross-Links Added Pending Decisions Filed]
    end
```

---

## Meta System — Agent and Skill Lifecycle

```mermaid
flowchart LR
    H([Human request: new agent or skill]) --> ASSESS[Meta Agent/Skill Designer reads all existing .agent.md / SKILL.md]
    ASSESS --> TABLE[Presents candidate table: extend / split / merge / create new]
    TABLE --> CONF{Human confirms new artifact?}
    CONF -->|No, extend existing| EXT[Modify existing file]
    CONF -->|Yes| DESIGN[Design: job, trigger, tools, model, output contract]
    DESIGN --> CHECK[Self-check: SRP, min tools, no inlined domain data]
    CHECK --> SAVE[Save to .github/agents/ or .github/skills/]
```

---

## Routing by Change Area

Orchestrators use this table to select specialists for each task.

| Change area | Required specialists | Optional |
|---|---|---|
| New API endpoint | Architect, Tester | Product Owner (if AC unclear) |
| Business logic (services) | Architect, Tester | Product Owner |
| Data model change | Architect, Tester | Product Owner |
| Validation rules | Architect, Tester | — |
| Database migration | Architect | Tester |
| Documentation only | Documentation Specialist | — |
| CI/CD pipeline | Architect | Tester |
| Frontend (`resources/web/`) | Architect | Tester |
| Bug fix | Architect, Tester | Post-Mortem Analyst (after fix ships), Documentation Specialist (lessons learned) |

---

## Definition of Done

A task is complete only when **all** of these hold:

1. **Code implemented** — conventions and architecture rules followed.
2. **Tests passing** — full suite passes; new/changed logic has adequate test coverage.
3. **Documentation propagated** — findings included as `### Documentation Note` in agent output; Documentation Specialist applied changes.
4. **Changes committed** — all modified files committed with a descriptive English message referencing the issue number (e.g., `fix: brief description (#12)`).
5. **Issue closed** — GitHub issue closed with a summary comment.

> Changes **must be committed before** the issue is closed. Never close an issue with uncommitted work.
