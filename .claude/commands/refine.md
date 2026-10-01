---
description: Refine a raw GitHub issue into an implementation-ready spec — business description, specialist analysis, complexity estimate, chunk breakdown
argument-hint: <issue number>
model: sonnet
---

Refine a GitHub issue. Parse the issue number from the invocation arguments below and call it `<N>`; every `<N>` in this document refers to it. If no issue number is present, stop and ask the human for one. Never guess which issue to refine.

Invocation arguments: $ARGUMENTS

**You (the main conversation loop) run this flow, acting as the Product Owner** — adopt the persona, business-description / chunk-breakdown formats, and budget thresholds defined in `.claude/agents/product-owner.md`. You orchestrate every step and are the **only** participant that touches GitHub. Every stage change, comment, block, body edit and issue creation goes through `scripts/issue.sh` from the `issue-lifecycle` skill — it is the only writer of issue text. Never hand-roll a `gh` write or label edit. You delegate to specialists by spawning subagents with the **Task** tool; each returns text only.

## Non-Interactive Contract

A refinement run never stops to ask the human a question — assume nobody is watching it. Every question you cannot answer yourself is either **deferrable** (take the safest default, record it as a stated assumption) or **blocking** (batched and posted to the issue via `issue.sh block` at the next checkpoint, which ends the run) — with one exception: a disagreement about *code facts* is **neither**, and goes to the Step 5 `architect` fact arbiter rather than to a checkpoint. Follow the **Blocking Protocol** section below — classification test, the three checkpoints (A business / B specialist / C decomposition), the ad-hoc exit, blocker-body quality, resume procedure.

Exactly one ask survives, and only at flow entry: **the missing issue number** above. There is no issue yet to write a blocker on, so there is nothing to write it to — the same accepted exception `/solve` carries. Everything after the gate blocks instead of asking.

Reporting a *missing tool or capability* is not a question and stays out of band — likewise a subagent that keeps returning unusable output. Neither is answerable by the human on the issue; both go to the `report-difficulty` skill per `CLAUDE.md`'s reporting rule. See the **ad-hoc exit** in Blocking Protocol §2.

## Flow

Throughout, `issue.sh` = `.claude/skills/issue-lifecycle/scripts/issue.sh`. Who may take part, and who is forbidden, is the participants table in the **Delegation Protocol** section below.

Every comment in this flow is posted as `issue.sh comment <N> refinement <file> "<suffix>"`. Write content only to the file, per the `issue-lifecycle` **Body files** rule — the script emits the `### 📐 Refinement — <suffix>` heading. The suffix is what distinguishes this flow's several comments; the registry is in `.claude/skills/issue-lifecycle/references/comment-formats.md`.

### 0. Gate and Claim

Run `issue.sh gate <N> refine` (`issue-lifecycle` skill). Non-zero exit → stop and report the reason; never relabel to work around a refusal. `resume: yes` **or** `blocked: yes` → follow the resume procedure in **Blocking Protocol §4** below before doing anything else — `resume: yes` alone means a prior run died mid-flow; `blocked: yes` (which can appear even when `resume: no`, e.g. this issue was resolved as an implementation block and now sits at `stage:fresh` or `stage:refined`) means the reply must be checked against the original questions before anything else proceeds. On an OK gate, run `issue.sh list` for backlog context — a read-only snapshot for your own awareness, never inlined into a specialist prompt and no substitute for Step 1's fetch of this issue; if it fails, note it and continue, since backlog context is advisory and must never stop a run.

Then claim the issue: `issue.sh set-stage <N> in-refinement`.

### 1. Fetch the Issue (exactly once)

Run: `issue.sh brief <N>`

This is the **only** issue fetch in the entire flow. All downstream prompts receive the issue content inline; no participant re-fetches it. The brief includes the comment log, which is where a previous run's answers live.

Then run `.claude/skills/issue-lifecycle/scripts/branch.sh log <N>`. It is read-only and the only `branch.sh` call this flow makes. `branch: none` is the normal case. A listed branch is one a human (or an earlier run) prepared, and `/solve` refuses to create a fresh branch over it. Its commits are part of what this refinement analyses, and Step 9 must record a verdict on it.

### 2. Gather Documentation Context (exactly once)

Read the documentation covering the areas the issue touches — the `documentation` skill's map says which file covers what. That map is your substrate: what the app does and its domain (`docs/project-overview/overview.md`, `domain-concepts.md`), the shape it has (`architecture.md`, `coding-conventions.md`), and how it is tested (`docs/test-strategy/test-strategy.md`).

Do NOT read source code, and do NOT commission a code survey — the input rule in `.claude/agents/product-owner.md` binds you here. Each specialist gathers the code facts its own analysis needs; there is no shared codebase brief.

If the documentation does not cover the issue's area, that is itself a finding: record it as a stated assumption, or as a Checkpoint-A blocker when the gap makes the scope unknowable. Never fall back to reading code.

### 3. Business Description → Checkpoint A

Write the structured business description yourself (format defined in `.claude/agents/product-owner.md`). Classify every question you hit against the blocking test; list the deferrable ones as stated assumptions and the blocking ones under `Open Questions`.

Post it with suffix `business description`, then run **Checkpoint A**: any blocking business question → `issue.sh block` and stop. Never delegate on an unresolved scope.

### 4. Specialist Fan-Out (parallel)

Spawn in parallel (multiple Task calls in one message): **`architect`** (technical analysis: affected files, design concerns, risks), **`tester`** (test plan), and **`rationale-reviewer`** (documented-intent plan — unconditional, not a domain add-on). Add domain subagents per the routing table when their area is affected.

See the **Delegation Protocol** section below.

### 5. Resolve Questions → Checkpoint B

Answer what you can yourself; classify the rest per the blocking protocol. Max **2 rounds** of specialist ↔ PO iteration — a question surviving both rounds, and any cross-specialist conflict that is a business trade-off, is blocking.

**A disagreement about code facts is not a business trade-off.** Specialists gather their own context (Step 2), so two of them can return contradicting statements about what the code does — and you may not open the source to settle it. Re-spawn **`architect`** as fact arbiter with both positions verbatim and **unattributed**; its ruling is the fact. The unconditional fan-out is `architect` + `tester`, so the realistic conflict has the architect as a party to it — a fresh, stateless spawn that cannot tell which position was its predecessor's is what makes the ruling defensible rather than a party confirming itself. This does **not** consume one of the 2 rounds — it settles a fact, it does not iterate a business question, and charging it a round would leave a contradiction surfacing in round 2 with no exit at all. If the ruling is inconclusive, the architect's stated uncertainty *is* the fact: record it as an assumption and continue. Only the residue that is genuinely a business trade-off reaches Checkpoint B.

Post 3 consolidated comments:

| Suffix | Content |
|---|---|
| `specialist findings` | Specialist and business findings — what the business implications are |
| `technical analysis` | What will be changed, where, why, and the acceptance criteria |
| `documentation changes` | What documentation will be changed and where |

Then run **Checkpoint B**: any blocking question left → one batched `issue.sh block` and stop.

### 6. Complexity Assessment

Only **after** both checkpoints passed clean, run the complexity assessment: two parallel dedicated Task spawns — **`architect`** (production LOC estimate) and **`tester`** (tests LOC estimate) — combined by you into one grand total. Follow the **Complexity Assessment** section below exactly.

### 7. Budget Decision

Apply your budget thresholds (defined in `.claude/agents/product-owner.md`) to the assessment's **grand total** (as computed per the **Complexity Assessment** section below):
- **Within budget** → continue with Step 8a
- **Over budget** → continue with Step 8b
- **Borderline** → continue with Step 8a and flag the risk in the readiness stamp

The budget is the **only hard decomposition rule**. A hint in the issue body (e.g. "consider creating sub-issues") does not force decomposition by itself — acknowledge such hints in the readiness stamp together with the decision and its reasoning.

### 8a. Chunk Breakdown (within budget)

Break the scope into implementation chunks (format in your agent file), ordered by dependency, each with scope, acceptance criteria, affected files, and required verifications. Post with suffix `chunk breakdown`.

### 8b. Sub-Issue Decomposition (over budget) → Checkpoint C

Create one sub-issue per deliverable via `issue.sh create "<title>" <scratchpad>/issue_body.md --parent <parent_issue_number>` — the body always goes through a file in the session scratchpad directory (see the `github-issues` skill, Body-File Rule, for what `<scratchpad>` resolves to). The script stamps the marker, applies `stage:fresh`, and verifies the round trip; never hand-roll `gh issue create`. Each sub-issue body MUST carry: parent reference (`Part of #N`), scope, affected files, acceptance criteria, and required verifications.

**Every child is re-sized before it is stamped.** A child inherits the parent's completed analysis, and therefore also inherits the parent's *over-budget* estimate — which says nothing about whether this particular child fits one implementation pass. Per child:

1. **Apportion** onto the child's `affected files` list, from the Step 6 `loc estimate` comment: the Architect's per-file **production** rows, the Architect's per-file **test** rows, and the Tester's per-module **test** estimates. No new Task spawns — both tables already exist.
2. **Combine** with the Step 6 Combining Rule unchanged: test LOC = max(the child's apportioned **Tester** estimate, 2× its apportioned production); grand total = (production + test) × 1.15. Step 6's divergence rule applies per child too — the child's apportioned Architect test rows and its apportioned Tester estimate more than 50% apart → use the higher, and name that child's divergence in the `sub-issues` comment (the parent's readiness stamp reports only the demoted children, so a divergence on a `refined` child has nowhere else to land).
3. **Judge** against your budget thresholds (`.claude/agents/product-owner.md`) — the same ones the parent was judged by.

Apportionment is mechanical. These cases are pinned so no run re-derives them:

| Case | Rule |
|---|---|
| A row claimed by two or more children | Counts **in full** for each — a shared file is real work in every child that touches it |
| A child lists an affected file with no row in either table | That child takes the over-budget branch — an unmeasured file is not a zero |
| A **test row from either table** — an Architect per-file `tests/…` row or a Tester per-module estimate — whose file/module maps to a production file | Attribute to the child owning that production counterpart; counterparts split across several children → in full for each, per the shared-row rule above. Test files rarely appear in a child's `affected files`, so without this both tables' test rows would fall through to the orphan row below and load every child with the parent's whole test estimate |
| A row no child claims at all | Counts **in full** for **every** child. An orphan row means the split does not cover the parent's scope, so no child may be trusted as small — and the LOC must not silently vanish, which is the same failure the unmapped-file row prevents |

A *row*, throughout this table, means a per-file production row or a per-module test row — nothing else. Aggregate lines are **never** apportioned: the Architect's test-floor subtotal, its `+15% buffer` line, and either table's grand total belong to the parent, and item 2 recomputes all three per child. Sweeping them into the orphan rule would hand every child the parent's whole buffered total and make "comfortably within budget" unreachable.

| Apportioned grand total | Stamp |
|---|---|
| Comfortably within budget | `issue.sh set-stage <child> refined` |
| **Borderline or over** | Leave the child at `stage:fresh` and post a `size verdict` comment on it (below); it must be re-refined before it can be solved |

Borderline **fails** for a child where it merely flags for a parent: an apportioned figure is coarser than the parent's directly-measured one, and "still too large for one implementation pass" is exactly the failure this branch exists to catch.

The `size verdict` comment (`issue.sh comment <child> refinement <file> "size verdict"`) states, in order: that the figure is **apportioned from the parent's table and therefore imprecise**; the apportioned rows and the resulting grand total; that re-refining this child measures it directly, after which Step 7's normal borderline rule applies (borderline then passes); and that until then `/solve` refuses it. It is a "re-measure this" verdict, not a "this is too big" one.

**Inherited analysis.** Add the parent's relevant analysis to each sub-issue as a `refinement` comment with suffix `inherited analysis` — never a canonical suffix (`business description`, `technical analysis`, …), which a later `/refine <child>` reserves for that child's own run. It must carry **this child's slice of the technical analysis and of the `documentation changes` list**, not a pointer to the parent's: `/solve` closes documentation against that list, so a child inheriting the parent's whole list would be made to write its siblings' docs. A demoted child thus reaches re-refinement with the parent's analysis readable in its comment log and no suffix collision.

Each child still needs its **own** `approved` label from the human — approving the parent does not approve its children.

**Decomposition attempts.** An *attempt* is a candidate split of the parent that you draw and then **discard before creating any child issue**, because it does not divide the scope into standalone deliverables. A child that is created and comes back over budget is **not** a failed attempt — it is a normal outcome, handled by the demotion above. Max **2** attempts; both discarded → **Checkpoint C**: `issue.sh block` on the parent with both attempted splits, and stop. A run that creates children — demoted ones included — completes normally and never fires Checkpoint C.

Then post a comment on the parent with suffix `sub-issues`, linking all children and naming each one's stamped stage. **Leave the parent at `stage:in-refinement` for now** — Step 9 stamps it `decomposed` once its readiness stamp is posted. Stamping it here would open a window in which a crashed run leaves a parent that `issue.sh gate` refuses for both flows ("tracking parent; work its sub-issues instead") with no readiness stamp and no way to finish it. From Step 9 onward the parent is a tracking issue and is never implemented directly.

### 9. Readiness Stamp

Post a final comment on the (parent) issue with suffix `readiness stamp`, containing:
1. Key decisions (bullets, not full reports)
2. Complexity estimate and budget verdict
3. Chunk breakdown, or the sub-issue list in dependency order — each child with its stamped stage and, for a child left at `fresh`, its apportioned total and the one-line reason
4. Risks and suggested mitigations
5. Every deferrable assumption taken in lieu of an answer — this is what the human vetoes by withholding `approved`
6. Anything the human should decide before implementation, even though it did not block
7. **Only when Step 1 listed a branch**, on its own line: `**Builds on:** issue-<N> @ <tip sha>` when the plan builds on that branch. Copy the full sha from `log`'s `tip:`. `/solve` adopts the branch only while its tip is still exactly that sha, so anything pushed later is refused as unanalysed. Otherwise write `**Builds on:** none — <why>`. Write `none` also when `log` printed an `origin-tip:`, because the local and remote (`happy-bank-demo`) tips disagree and there is no single state to record. With `none`, `/solve` refuses until a human deletes or re-records the branch. Format: `issue-lifecycle`'s `comment-formats.md`, Builds-on Line

**Then stamp the parent's stage, which depends on which Step 8 branch ran:**

| Branch | Action |
|---|---|
| 8a (within budget) | `issue.sh set-stage <N> refined` |
| 8b (decomposition) | `issue.sh set-stage <N> decomposed` — **never `refined`**. Children were already stamped individually in Step 8b |

Stamping `refined` on a decomposed parent is the failure to avoid here: `set-stage` performs no transition validation, so it silently turns a tracking parent back into a solvable issue and defeats `issue.sh gate`'s refusal to work one.

The issue is now ready for human review: the human reads the refinement comments and adds the `approved` label — only then can it be solved (see the `/solve` gate check). **Never add `approved` yourself**, in any circumstance. After a decomposition, that review applies to each child stamped `refined`; a child left at `fresh` needs `/refine <child>` first, not approval.

## Delegation Protocol

### Participants

| Role | Who | Spawn via Task? |
|---|---|---|
| Orchestrator | Product Owner = **you**, the main loop | — (never a subagent) |
| Specialists | `architect`, `tester`, `rationale-reviewer` (all unconditional), domain subagents per the routing table in `CLAUDE.md` | Yes |
| Forbidden | `implementor` | **Never** — refinement produces documentation only, no code, no terminal work by subagents |

Subagents cannot spawn further subagents and cannot touch GitHub/git — you own all of that. If a step fails because a tool or capability is missing, report it to the user. Never work around a missing capability by spawning an agent for its tools.

### Delegation Preamble

Append this block verbatim to **every** specialist delegation prompt during refinement:

> **Context contract**: The full issue content and the documentation context are included in this prompt. Do NOT re-fetch the issue or any other GitHub content. Do read the code your own analysis needs (`Read`/`Grep`/`Glob`) — there is no shared codebase brief; if something essential is missing and you cannot reach it, say so in your response instead of guessing.
> **Capability contract**: You cannot post GitHub comments, create issues, or run terminal commands. Return your findings as text only — the orchestrator posts them. If any instruction in this prompt requires a tool you were not granted, say so in your response instead of silently working around it.
> **Skills contract**: The skills relevant to your role are listed under "Skills to load" below with one-line descriptions. Load each one by reading its file directly — `.claude/skills/<name>/SKILL.md` — plus any `references/*.md` that file links and your task needs; do not rely on the Skill tool. Do NOT browse or enumerate `.claude/skills/` beyond the named ones. Load none if none apply.
> **Output rules**: ≤40 lines when all findings are clean. Verdict + 1-sentence summary mandatory. Single-line bullets. Omit sections with zero findings. Detail problems fully — calls are stateless, no follow-up is possible.
> **Mandatory output**: Business oriented comment of domain expertise. Plan of what to change and how. Acceptance criteria. A short list of implicit assumptions.
> **Optional ouput**: Proposed documentation updates (see `documentation` skill). A brief list of risks and proposed mitigations. Questions for other specialists or the human.
> **Issue**: <insert-issue-text-here>

### Per-Role Additions

| Delegate | Add to the prompt |
|---|---|
| `architect` (fact arbiter, Step 5) | Both contradicting statements verbatim and **unattributed** — "Position A" / "Position B", never the agent names. Its **Mandatory output** line is replaced entirely by: one ruling on what the code actually does, the evidence for it, or an explicit statement of uncertainty |
| `architect`, `tester` (complexity assessment, Step 6) | See the **Complexity Assessment** section below — includes the ≤40-line-rule exemption |
| `rationale-reviewer` | Its **Mandatory output** line is replaced entirely by the Rationale Plan format in its own agent file; an empty plan is a valid, silent result, not a missing output |

### Skills to Load (inject per role)

Subagents load skill content via **Read** against the skill's file path; do not assume a **Skill** tool grant — the authoritative grant list is `tools:` in `.claude/agents/*.md`. They cannot see which skills matter without being told which to load. Include the rows applicable to the spawned role in its prompt as a **"Skills to load"** block — skill name + the one-line description verbatim — so the subagent loads the right skill instead of searching. Domain specialists come from the `CLAUDE.md` routing table; add their rows when their area is affected.

| Skill | One-line description | Give to |
|---|---|---|
| `project-conventions` | Code organization and layer rules, Python style/typing/ruff, type guidelines, language rules | `architect` |
| `structural-discipline` | File/function/class size limits, decomposition patterns, SRP/SoC enforcement | `architect`, `tester` |
| `test-strategy` | pytest fixtures, helpers, tmp_path, coverage targets, test organization | `tester` |
| `documentation` | Which doc file covers what, its owning specialist, when a change needs a doc update, and the Rationale Test | any specialist proposing documentation updates; `rationale-reviewer` |

## Complexity Assessment (Step 6)

Run only after all blocking questions are resolved. Two delegations, **in parallel** (they are independent). Both prompts carry the delegation preamble above, with one override: **these outputs are exempt from the ≤40-line rule** — the concise protocol never overrides the estimation protocols.

### Delegation 1 — Architect: Production LOC Estimate

Require the full LOC Estimation Protocol table (defined in the Architect's agent file):

- Layer scan first — every touched layer enumerated
- Per-file rows with verified filenames; justified zeros only
- +15% surprise buffer line

LOC numbers mentioned informally in Step 4 analyses are context only; they are NEVER valid input for the budget decision.

### Delegation 2 — Tester: Test Complexity Estimate

Require, based on the agreed test plan (per the Tester's Test LOC Output Rules):

- Per test module: `tests/test_X.py — N new test functions × ~M LOC avg = ~X LOC estimated`
- Overflow flags: any test file that would exceed its size limit (see Limits in `CLAUDE.md`) → new-file proposal included in the estimate
- A note on which scenarios are integration-heavy (higher per-test LOC and runtime)

### Combining Rule (you, the Product Owner)

1. Production LOC = Architect's production subtotal
2. Test LOC = **max(Tester's estimate, 2× production)** — the floor still applies; a real Tester estimate can raise it, never lower it
3. Grand total = (production + test) × 1.15 (surprise buffer)

If the Architect's test rows and the Tester's estimate diverge by more than 50%, use the higher value and flag the divergence in the readiness stamp.

Then post both tables — the Architect's per-file rows and the Tester's per-module estimates — together with the grand total, using suffix `loc estimate`. **This posting is mandatory, not a courtesy:** Step 8b apportions those rows onto sub-issues, and a run resuming after a block re-enters the flow with nothing but the comment log. An estimate that lives only in this run's context is unavailable to the run that needs it. A resumed run that finds no `loc estimate` comment re-runs the two Step 6 delegations before continuing — the one place in this flow where re-spawning is permitted.

The grand total feeds the Step 7 budget decision.

### Validation

| Problem | Action |
|---|---|
| Architect output missing table, layer scan, or buffer | Reject, re-request once with the missing parts named |
| Tester output is a single number without per-module breakdown | Reject, re-request once |
| Still incomplete after re-request | **Ad-hoc exit** (Blocking Protocol §2): run the `report-difficulty` skill and stop. Not a blocker — see below |

A twice-incomplete estimate is not a question the human can answer on the issue; it is a subagent that is not doing its job, which `CLAUDE.md`'s reporting rule and this flow's Non-Interactive Contract both route to `report-difficulty`. Blocking would be worse than useless here: the resumed run re-enters at this same step, re-spawns the same two delegations (Step 6 is the one place re-spawning is permitted), and hits the same failure — the difficulty report is what actually closes it, by fixing the agent.

## Blocking Protocol

This flow never prompts the human mid-run. A question it cannot answer is either taken as a recorded assumption or discharged into the issue as a blocker at a **checkpoint**. This section defines which of the two applies, where the checkpoints are, and how a blocked run later resumes.

### 1. Classify Every Open Question

Apply this test the moment a question surfaces — yours, or one returned by a specialist.

**Blocking** if *any* of these holds:

- the answer changes scope, acceptance criteria, or user-visible behaviour;
- it has legal or compliance implications (per the `CLAUDE.md` routing table);
- specialists disagree and choosing between them is a business trade-off, not a technical one;
- there is no defensible default — every candidate answer is an equally plausible guess at intent.

**Neither**, in one case: a disagreement about *code facts* is not a question for the human at all — a blocker must be answerable without reading code, and this one is only answerable by reading it. It goes to the Step 5 `architect` arbiter instead.

**Deferrable** otherwise: exactly one defensible default exists and being wrong about it is cheap to correct later. Do **not** block on these. Instead:

1. Take the safest default.
2. State it as an explicit assumption in the comment where it applies — `Assumed: <X>, because <why>. Alternative: <Y>.`
3. Repeat it in the readiness stamp under implicit assumptions.

The human's `approved` label is the veto: they read the stamp before approving, so a wrong deferrable assumption costs one review round, not a wrong implementation.

**Never** resolve a blocking question by guessing, by picking "the more common case", or by parking it as a follow-up issue. Those are the failure modes this protocol exists to prevent.

### 2. Checkpoints

Blocking questions accumulate and leave at the next checkpoint — never one blocker per question.

| Checkpoint | Fires after | Carries | Why here |
|---|---|---|---|
| **A — business** | Step 3, the business description is posted | Business questions only | Scope and AC feed every specialist prompt; delegating on an unknown scope wastes the whole fan-out |
| **B — specialist** | Step 5, the three consolidated comments are posted | Specialist questions, cross-specialist conflicts **that are business trade-offs**, questions surviving 2 PO↔specialist rounds, any `rationale-reviewer` UNCLEAR INTENT (per the `documentation` skill's Rationale Test — no defensible default exists) | Step 6 already forbids estimating with an open question; this is the last point where stopping is free |
| **C — decomposition** | Step 8b, after 2 candidate splits were drawn and both discarded | The oversized scope and both attempted splits | The scope cannot be divided into standalone deliverables at all; only a human can re-scope it. An over-budget *child* is **not** this — Step 8b demotes it and the run completes |

**The ad-hoc exit** is the fourth way a run can end, and it is *not* a checkpoint: a failure of the machinery rather than an open business question. It fires when a subagent still returns unusable output after its one permitted re-request (today only the Step 6 estimate rows say so, but the exit is general). Run the `report-difficulty` skill against it and stop — no `issue.sh block`, because the human has nothing to decide and a resumed run would only re-spawn the same failing delegation. It is named here so the protocol documents this path instead of leaving it implicit for each step to improvise.

Rules that hold at every checkpoint:

- **Post the work first, block second.** The comments produced so far are posted before `issue.sh block`, so a blocked run still leaves durable value on the issue.
- **Block exits the run.** After `issue.sh block <N> refinement <file>`, stop. Do not continue to the next step, do not start a second checkpoint's work.
- **No blocking questions → no blocker.** A clean checkpoint is silent; it produces no comment of its own.

### 3. Blocker Body

Use the blocker template in `.claude/skills/issue-lifecycle/references/comment-formats.md`. Question quality is what makes a non-interactive flow work — the human answers without a conversation:

- One decision per number; no compound questions.
- Answerable without reading code — restate the context the answer depends on.
- State the options you already considered and why none is a defensible default.
- Name the consequence: what part of the refinement is waiting on this answer.
- Include the deferrable assumptions you took, so the human can correct one in the same reply.

### 4. Resume After a Block

A refinement block never leaves `stage:in-refinement`, so the human's answer doesn't need to move the stage anywhere — it only needs to exist. A plain reply on the issue resolves it; `issue.sh unblock <N> <answers-file>` remains available for a structured, explicitly-marked answer. Either way the next `/refine <N>` gate reports `resume: yes` (unchanged, since stage never left `in-refinement`) **and** `blocked: yes` — the second signal is what tells this run specifically that a block preceded it.

This procedure also applies when the gate prints `blocked: yes` with `resume: no` — that combination means the block was an *implementation* block, which already moved the stage to `refined` or `fresh` (see `.claude/skills/issue-lifecycle/references/states.md` §2); only the stage differs, the steps below are unchanged.

On a resumed run where the gate printed `blocked: yes`:

1. Read every comment after the `### ⛔ Blocked` comment that is not itself AI-authored — the human's answer, whether or not it carries the `### ✅ Unblocked` heading.
2. Map it against every numbered question from the blocker. Any question left unanswered → `issue.sh block <N> refinement <file>` again, naming only the still-open numbers, and **stop** — do not proceed on a partial answer.
3. All answered → read the `### 📐 Refinement` comments already posted; do not redo a step that has one.
4. Continue from the checkpoint that fired, applying the answers.
5. If an answer invalidates an earlier comment, post a corrected one with the same suffix and say what changed.
6. Claim the stage (`issue.sh set-stage <N> in-refinement`) — this also clears `blocked`, so a later gate call on this issue no longer reports `blocked: yes` once the reply has actually been consumed.

A refinement block always resumes in place, never restarting from `fresh` — restarting would make blocking expensive, and cheap blocking is what lets this flow stay non-interactive.

## Error Handling

| Situation | Action |
|-----------|--------|
| No issue number in the invocation arguments | Stop and ask the human for one — never guess which issue to refine |
| Gate refuses (blocked / decomposed / mid-implementation) | Stop; report the printed reason; never relabel to bypass it |
| `gh` CLI unavailable or unauthenticated | Follow `github-issues` skill error handling; report to user |
| Specialist raises a question you cannot answer | Classify it per the blocking protocol; never guess business intent |
| A blocking question is found | Record it for the next checkpoint; do not prompt the human, do not park it as a follow-up issue |
| Specialist ↔ PO iteration exceeds 2 rounds | Blocking question → Checkpoint B |
| Two specialists state contradicting **code facts** | Not a business trade-off and not a blocker — re-spawn `architect` as fact arbiter (Step 5), consuming no round; never open the source yourself to settle it |
| The fact arbiter's ruling is inconclusive | Its stated uncertainty *is* the fact — record it as an assumption and continue; do not block, and do not go looking in the code |
| Documentation does not cover the issue's area | Stated assumption, or a Checkpoint-A blocker if scope is unknowable without it; never fall back to reading code |
| Refinement blocked or abandoned mid-flow | Stage stays `in-refinement`; the next run resumes from the comment log |
| Gate reports `blocked: yes` (with or without `resume: yes`) and the reply misses a question | Re-block naming the unanswered numbers before claiming; never proceed on a partial answer |
| A needed tool/capability is missing | Report to user; do not substitute another agent for its tools |
| Subagent result redirected to a file you cannot read | Re-request: "Return ALL findings directly in your final message, ≤40 lines" |
| A subagent still returns unusable output after its one re-request | Ad-hoc exit (Blocking Protocol §2): run `report-difficulty` and stop — never `issue.sh block`, the human has nothing to decide |
| 2 candidate splits of the parent drawn and both discarded before any child was created | Checkpoint C. A created child measured over budget is not this — it is demoted to `stage:fresh` per Step 8b and the run continues |
