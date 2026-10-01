---
description: Turn a refined, approved GitHub issue into shipped code — per-chunk implement/review loop, documentation closure, final gate, commit, push, close
argument-hint: <issue number>
model: sonnet
---

Implement a GitHub issue. Parse the issue number from the invocation arguments below and call it `<N>`; every `<N>` in this document refers to it. If no issue number is present, stop and ask the human for one. Never guess which issue to solve.

Invocation arguments: $ARGUMENTS

**You (the top-level conversation loop) run this flow, acting as the Executor** — the implementation orchestrator. You orchestrate every step and are the **only** participant that touches GitHub and git; every stage change, comment, block and close goes through `scripts/issue.sh` from the `issue-lifecycle` skill and every git operation through `scripts/branch.sh`, never hand-rolled `gh` label edits or inline `git`. You **never write code, tests, or docs yourself** — every change is produced by a subagent (spawned with the **Task** tool) and reviewed by `architect`; you enforce reviews and gates and escape on deadlock rather than overruling a verdict. Subagents return text or edit source files; they never spawn further subagents and never touch GitHub/git.

## Non-Interactive Contract

A solve run never stops to ask the human a question — assume nobody is watching it. Every deadlock this flow can reach is a **blocking trigger** (see **Blocking** below), and the response is always the same three steps, never a chat prompt: commit what exists, push the branch, post the blocker. The human answers on the issue and re-runs `/solve <N>`, which resumes from the branch.

Exactly one ask survives, and only at flow entry: **the missing issue number** above. There is no issue yet to write a blocker on, so there is nothing to write it to — the same accepted exception `/refine` carries. Everything after the gate blocks instead of asking.

Reporting a *missing tool or capability* is not a question and stays out of band (`CLAUDE.md`'s reporting rule → the `report-difficulty` skill).

## Flow

Throughout, `issue.sh` = `.claude/skills/issue-lifecycle/scripts/issue.sh` and `branch.sh` = `.claude/skills/issue-lifecycle/scripts/branch.sh`. Every body file passed to `issue.sh` in this flow is content only, per the `issue-lifecycle` **Body files** rule. See the **Delegation Rules** section below for the participants roster (who fills each role, and who may be spawned via Task).

### 1. Fetch the Issue (exactly once)

Run: `issue.sh brief <N>`

The comments contain the refinement outputs you will execute: business description, technical analysis (locations of changes, acceptance criteria), **documentation changes comment**, chunk breakdown, and readiness stamp (risks, assumptions). All downstream prompts receive the relevant parts inline; no participant re-fetches the issue.

If the issue is sub-issue, fetch its parent too to gather the whole context.

### 2. Gate Check, Branch, and Claim

Run `issue.sh gate <N> solve` **before anything else**. Non-zero exit → stop and report the printed reason; never relabel to bypass a refusal (clearing `blocked` does not unblock by itself — a resolving comment does). Then apply the flow policy to the printed signals, in this order:

- `blocked: yes` → this invocation follows an implementation block. `block` already moved the stage to its target when the block was posted (`refined` in Standard Mode, `fresh` in Trivial Mode — see `.claude/skills/issue-lifecycle/references/states.md` §2), so `stage:` already reads correctly below; this line only means "check the reply before trusting that." Read every comment after the `### ⛔ Blocked` comment that is not itself AI-authored, and map it against every numbered question from the blocker. Any question unanswered → `issue.sh block <N> implementation <file> <target>` again — `refined` in Standard Mode, `fresh` in Trivial Mode, the same target the original block used — naming only the open numbers, and **stop**. **Carry forward two things verbatim** from the blocker you are answering, if it had them: its `**Branch:**` line, and its statement that a `start` refusal fired. The re-block becomes the latest blocker, so anything it drops is invisible to the next run — and dropping the refusal statement sends that run down the `--resume` path instead of the carve-out below, straight into a refusal the human cannot answer. All answered → fall through to the `refined:`/Trivial-Mode branch below as normal; claiming the stage (below) clears `blocked`.
- `resume: yes` → a prior solve run died mid-flow, unrelated to blocking (stage is still `in-implementation`).
- `refined: yes` + `approved: yes` → Standard Mode (Step 3).
- `refined: yes` + `approved: no` → stop; tell the user to read the refinement comments and approve the issue.
- `refined: no` → check Trivial Mode eligibility. ALL must hold: single file affected (or source + its test), no business logic changes, no calculation or legal implications, no design decisions, **and no `### 📐 Refinement — size verdict` comment in the log**. That last one marks a decomposition child that `/refine` Step 8b measured as borderline-or-over and demoted to `stage:fresh`; Trivial Mode has no Final Gate to catch an oversized change, so such an issue is never trivial no matter how few files it names — it needs `/refine <N>`. If eligible → treat the whole task as one chunk, run Steps 4–5 once, skip the Final Gate (Step 6 — Architect review + targeted tests suffice; there is no Final Gate to discharge an UNCLEAR INTENT here, so it blocks directly at chunk review instead — see Blocking), and continue with Step 6b (Sync with `demo`) and Step 7 (Ship; the plan-adherence and risk sections are omitted since there is no refinement plan). If not eligible → stop and tell the user to run `/refine <N>` first.

**Then put the run on its branch**, before any code is written. All three entries go through the same call — this is not the blocked path's private step:

| Signals | Call |
|---|---|
| `blocked: yes` **or** `resume: yes` | `branch.sh start <N> --resume` |
| Neither (fresh claim), `builds-on: none` | `branch.sh start <N>` |
| Neither (fresh claim), `builds-on: <sha>` | `branch.sh start <N> --adopt <sha>` — the refinement (or a human) recorded a human-prepared `issue-<N>` as the base; adopted only at exactly that tip (#206) |

**One carve-out, and it is not optional.** A block whose trigger was a `branch.sh start` refusal was posted *before* any branch existed — the blocker names the refusal and carries no `**Branch:**` line. The next run sees `blocked: yes` and would call `--resume` against a branch that still does not exist, refuse, and re-block: a loop that never ends, on triggers as ordinary as a dirty tree. So when the blocker being resolved names a `start` refusal, **pick the call from git state, not from the signal**: run `branch.sh log <N>` (which exits zero either way) — `branch: none` → fresh claim, `branch.sh start <N>`; a branch listed → `branch.sh start <N> --adopt <sha>` when the gate printed `builds-on: <sha>`, else `branch.sh start <N> --resume`. `--adopt`'s own refusals name the way out that ends this loop. For an interrupted run, a human posts `**Builds on:** none`, which routes the next run to `--resume`. For a moved tip, a human re-records the line.

**Preflight — prove `demo` green before any fresh claim.** Every call above that is a plain `branch.sh start <N>` (the fresh-claim row, or the carve-out's `branch: none`) or a `--adopt` is preceded by `branch.sh preflight`, in both modes. A `--resume` skips it: that base was proven green when the branch was cut. The repo must never be red. A green base is also what makes the Final Gate's "red → FIX" rule (Step 6) sound: whatever turns red later is this branch's doing. One red run is the verdict. Never re-run it hoping for green, since a flaky test is a defect to track too. A preflight refusal (dirty tree, failed fetch) runs the escape routine's `start` row (see **Blocking**).

- `preflight: green` → `branch.sh start <N> --base <sha>`, passing preflight's `sha:`. That forks from the exact tip proven green, not from wherever `happy-bank-demo/demo` moved while the suite ran (Step 6b catches up later). Every fresh `start` in this step, including the self-fix path below, takes `--base`, **except `--adopt`**. The two flags don't combine, since an adoption forks nothing. Before an adoption, preflight only proves `happy-bank-demo/demo` green. The adopted human commits were never tested, but they are this issue's scope, so red they cause is still this branch's to fix. Step 6b brings the branch onto `demo`.
- `preflight: red` → do not branch. For each `failed:` ID, strip any `[…]` parameter suffix, then find an open issue naming it: `gh issue list --state open --search "<function name> in:body" --json number,body`, and keep only issues whose body contains the `path::function` ID word for word (search breaks `::` apart into loose tokens). An ID with no `::` part (a collection `ERROR`) is matched on its file path instead: search the basename, keep bodies containing the full path. **Leave `<N>` itself out of the matches.** IDs that `<N>`'s own body names are dropped from the set, since this issue exists to fix them. Nothing left → make the call the branch table picked: `branch.sh start <N> --base <sha>` (preflight's `sha:`), or `branch.sh start <N> --adopt <sha>` when the gate printed `builds-on: <sha>`; making those tests green is its scope. A red run with no `FAILED`/`ERROR` line (a crash, an interrupt, no tests collected) lists the stable ID `UNPARSED pytest-exit-<rc>`. It is searched as the whole token, then matched and dropped word for word like any other ID, so it is never an empty set, never files a duplicate, and its own fix issue can still branch. Otherwise, for the IDs that remain:
  1. IDs no open issue names → **one** issue for all of them: `issue.sh create "Red demo: <short cause or first test>" <file> --label bug`. Body: the `failed:` IDs, the `sha:`, the `summary:` line, and "found by `/solve` preflight for #<N>".
  2. `issue.sh depend <N> <M>` for every blocking issue `M` (found or filed). It is GitHub's native "blocked by", and the gate refuses `solve` while any `M` is open (`waiting:`), then clears on its own.
  3. `issue.sh comment <N> waiting <file>`: which issues block it and which tests are red at which sha.
  4. **Stop** and report. No branch, no stage change, no `blocked` label: the issue was never claimed, and no human decision is pending.

`--resume` lists the branch's commits under `landed:` — **that listing, not the comment log, is what says which chunks are done** (`branch.sh log <N>` reprints it; you may not run `git` yourself). Each `[#N] chunk k/total:` and `[#N] fix:` there passed review: do not redo it. It also prints `wip: yes` when `HEAD` is a `[#N] WIP blocked:` commit — work an escape saved mid-chunk, never reviewed. Its subject names the interrupted chunk (`chunk <k>/<total> interrupted: …`); **re-run that chunk**, do not count it as landed. `wip: no` means every commit landed, including any earlier `WIP blocked` a later `chunk` commit superseded. An `--adopt` prints the same `landed:` listing with `wip: no`. Its human-authored commits carry no `chunk`/`fix` subject, so they are the base the chunks build on, not landed chunks. Any `branch.sh start` refusal — branch already exists on a fresh claim, an `--adopt` that does not match its record, exists nowhere on a resume, dirty working tree, local branch diverged from `happy-bank-demo`, or a failed fetch — runs the escape routine's `start` row (see **Blocking**): post a blocker and stop. Never a chat-only report.

One resume entry skips ahead: a block whose trigger was a **ship-time refusal** (`landed:` ends with a normal chunk/fix commit and the blocker names the divergence or squash-conflict trigger). Everything is implemented, reviewed and committed there — re-enter at **Step 6b** (a no-op when `demo` has not moved), do not rebuild the plan or re-spawn implementors over finished files. Likewise a blocker naming a **Sync trigger** (Step 6b: intent conflict, a Sync cap, `base-red`) → re-enter at **Step 6b** once answered, at the entry point its **Resuming into Step 6b** paragraph names; the chunks are landed, and `landed:` may end with `[#N] rebase fix:` commits, which are landed too.

Full contract: `.claude/skills/issue-lifecycle/references/branching.md` (the branch and how a run picks it up) and `references/branch-exits.md` (ship and escape).

Once branched, claim the issue: `issue.sh set-stage <N> in-implementation`.

### 3. Build the Execution Plan

From the refinement comments extract: chunks in dependency order, per-chunk acceptance criteria and affected files, the documentation changes list, and the risks with their mitigations.

**On a sub-issue whose own comment log has no `chunk breakdown`** — a child stamped `refined` directly by `/refine` Step 8b — those comments are not on the child: Step 8b posts the parent's analysis down as a single `inherited analysis` comment and reserves the canonical suffixes for the child's own future run, and the parent has no `chunk breakdown` either. Build the plan from the child's body (scope, affected files, acceptance criteria, required verifications) plus its `inherited analysis` comment, and treat the child as one chunk. The parent's comments are **context only**: the child's documentation obligations are the list inside its `inherited analysis` comment, and that list — never the parent's full one — is what Step 5 closes against.

Condition on the missing `chunk breakdown`, not on the parent being `stage:decomposed`. A child that Step 8b demoted to `stage:fresh` and that was later re-refined has its own canonical comments, which is exactly why Step 8b reserved those suffixes — run it as any other Standard-Mode issue and skip this paragraph. **Assign each risk to the chunk(s) whose scope it touches** — a mitigation nobody executes cannot be evaluated later; risks that map to no chunk stay on your own watchlist. Then gather a compact codebase **context brief** (≤40 lines) with your own read/search tools, and run `issue.sh list` for backlog context — a read-only snapshot for your own awareness, never inlined into a delegation prompt; if it fails, note it and continue, since backlog context is advisory and must never stop a run. Track chunk status and risk outcomes as a checklist throughout.

### 4. Per-Chunk Loop (in dependency order)

1. **Pre-check file sizes** — if the chunk would push any file past its category limit (`structural-discipline` skill), schedule a decomposition sub-chunk first.
2. **Implement** — spawn **`implementor`** via Task: chunk spec (scope, acceptance criteria, affected files), the chunk's assigned risks and mitigations (the mitigation is part of the chunk's work), the documentation updates belonging to this chunk (per the `documentation` skill), the context brief, and the delegation preamble from the **Delegation Rules** section below. Instruct: run only targeted tests (`pytest tests/test_x.py` or `-k "pattern"`).
3. **Review** — spawn **`architect`** and **`rationale-reviewer`** via Task in parallel, including the chunk's assigned risks — architect confirms each mitigation was actually applied; rationale-reviewer checks the chunk's decisions and doc updates for undocumented intent. Architect APPROVED **and** rationale-reviewer CLEAR → continue. Architect NEEDS CHANGES, **or** rationale-reviewer NEEDS RATIONALE → re-spawn `implementor` with all feedback combined (one round, even if only rationale-reviewer flagged something). An UNCLEAR INTENT is instead carried forward, never resolved through this round (inventing an answer under round pressure is what it exists to prevent) — it is discharged at the Final Gate, or blocks immediately in Trivial Mode, which has none. Max **2 rounds**; unresolved → **escape** (see Blocking) with both positions, without asking the user first.
4. **Commit** — the chunk's review passed, so it lands: write the message body to `<scratchpad>/chunk_msg.md` with the file-editing tool (first non-blank line = summary), then `branch.sh chunk <N> <k> <total> <scratchpad>/chunk_msg.md`. A commit per reviewed chunk is what makes a later escape recoverable — the branch, not the working tree, is the resume evidence. A fix cycle that ran in step 3 lands with the chunk; a fix applied *after* a chunk was already committed uses `branch.sh fix <N> <file>` instead.
5. **Mark complete** — update the checklist. Post a brief progress comment on the issue if the task has ≥3 chunks.

### 5. Documentation Closure

Compare the applied changes against the refinement's **documentation changes comment**. Any unapplied item → one dedicated `implementor` doc chunk, verified by the owning specialist per the `documentation` skill (architecture docs → `architect`, testing docs → `tester`, README → `product-owner`). Documentation drift is a FIX, not a follow-up.

**Commit it.** Once the owning specialist has verified the doc chunk, land it with `branch.sh fix <N> <file>` — `fix`, not `chunk`, because it closes drift against a plan whose chunk count is already fixed; numbering it `chunk <total+1>/<total>` would read as a defect in the very log a resume has to trust. Step 7's `branch.sh ship` requires a clean tree, so anything left uncommitted here stops the ship.

### 6. Final Gate (Standard Mode only)

1. **Structural health check** (you, directly) — cumulative line counts of ALL modified files vs. `structural-discipline` limits.
2. **Lint + full test suite** (once — the only full run before Step 6b, which re-runs it on the rebased tree): `uv run ruff check <every .py file this branch touched>` (never the whole repo — its baseline is not ruff-clean; no `ruff format --check`), then `uv run pytest`. Ruff findings on touched files count as red. Red is always this branch's to fix. The preflight (Step 2) proved the base green, or this issue exists to make it green.
3. **Whole-change verification** — fresh spawns so the final state is read without chunk-history bias:
   - In parallel (multiple Task calls in one message): **`architect`** — cross-chunk integration and consistency ONLY (per-chunk quality was already verified; skip this spawn when the task had a single chunk — there is nothing cross-chunk to check); **`tester`** — coverage verification against the refinement test plan, returning an **AC ↔ test evidence mapping**; **`rationale-reviewer`** — discharges any UNCLEAR INTENT carried from chunk review, plus a whole-change rationale check.
   - Then: **`product-owner`** — acceptance-criteria completeness against the business description, judged on the Tester's evidence mapping.
   - Every verifier's output MUST end with a line `New risks observed: <list> / none` (required via the delegation preamble).
4. **Verdict synthesis** (you, directly — mechanical rules, no re-review):
   - `rationale-reviewer` still reports UNCLEAR INTENT → **block** directly (see Blocking); never routed through the fix cycle below, which would pressure an invented rationale.
   - `rationale-reviewer` reports NEEDS RATIONALE → **FIX** (per the `documentation` skill: doc changes are never a follow-up), never FOLLOW-UP.
   - Any critical finding → **FIX**: one targeted fix cycle (max 1 Implementor ↔ Architect round), then re-run the failed checks. Still failing after the cycle → **block** (see Blocking).
   - Only non-blocking findings → **FOLLOW-UP**: spawn `product-owner` to draft the follow-up issue, post it via `issue.sh create` (content only, per the `issue-lifecycle` **Body files** rule), ship what's done.
   - All clean → **SHIP** → Step 6b.
   - Specialists conflict, or FIX vs FOLLOW-UP is ambiguous → the **`product-owner`** verdict decides.
5. **Commit any fix-cycle change** (you, directly) — a FIX cycle that greened the checks left edits in the tree; land them with `branch.sh fix <N> <scratchpad>/fix_msg.md` before Step 6b. `branch.sh ship` requires a clean tree, so an uncommitted fix stops the ship rather than shipping silently.

### 6b. Sync with `demo` (both modes)

Everything above was verified against the branch's original base. If `happy-bank-demo/demo` moved since, ship would land a combination nobody tested — so bring the branch onto the current `demo` first, and verify again. All of it runs unattended: every resolution below is auto-approved, never asked. `branch.sh` subcommand contracts: the sync section of `references/branching.md`.

1. **Measure** — `branch.sh behind <N>`. `behind: 0` → Step 7.
2. **Intent check** — the new commits name any `[#M]` issue (`issues:` line) → fetch each with `issue.sh brief <M>` and spawn **`product-owner`**: our acceptance criteria vs. their bodies, intent only (no code — its input rule). Do *our* change and *theirs* contradict each other at the level of intent (not code)? **Conflict → block** (target `refined`), numbered questions naming both issues. A code-level clash is not this — the steps below resolve it. On resume, the human's answer settles that `[#M]`: do not re-ask about it.
3. **Distance check** — when `overlap:` is non-empty, and once more before escaping on a step-4 or step-5 round cap if it has not run in this sync: spawn **`architect`** with the refinement's technical analysis, `behind`'s full output, and the `base:` date. Pure judgement, no fixed thresholds: has `demo` moved so far, in code and in time, that the refinement no longer describes the code this would land on? **Stale** → clear the tree first (at a cap it is rarely clean): rebase in progress → `branch.sh rebase-abort <N>`; uncommitted edits → `branch.sh wip <N> <file>` (`sync interrupted: …`); then `branch.sh retire <N>`, then block with target **`fresh`** (re-refine; the block also drops `approved`, since the new spec needs a fresh human read), carrying its `**Branch:**` line and the architect's reasoning. **Current** at a cap → the escape routine as the cap says.
4. **Rebase** — `branch.sh rebase <N>`. Exit 2 = stopped on a conflicting commit: spawn the commit's **validators** (below) to explain *theirs* vs *ours* and plan the resolution → **`implementor`** resolves the named files only, per that plan → validators review (max **2 rounds** per commit) → `branch.sh rebase-continue <N>`, which may stop on the next commit. Then **`branch.sh publish <N>` immediately** — `happy-bank-demo` still holds the pre-rebase branch, and any later escape must not find the two diverged.
5. **Re-verify** — Step 6.1 (structural health check) + 6.2 (lint + full suite). 6.2 red → `branch.sh bisect <N>`: `first-bad:` names the commit to hand the fix to — a *hint*, since chunk commits were only ever targeted-test green; `inconclusive` → the whole rebased diff; `base-red` → `demo` turned red after the branch was cut, not by us: run `branch.sh preflight` (the tree is clean here, and it returns to `issue-<N>`) for `demo`'s own failing IDs and sha. Do not reuse this step's suite output, which includes our changes. `preflight: green` → `demo` was fixed meanwhile: back to step 1 (counts as a re-sync). A preflight refusal here → straight to the blocker, skipping escape steps 0–2 as the `start` refusals do (the branch was already published in step 4). Red → file or link the red-`demo` issue exactly as Step 2's preflight-red path does (its items 1–2, including `issue.sh depend`), then block, naming that issue. The resumed run needs it closed (gate) **and** a human reply (blocker). Only 6.1 red → the whole rebased diff, no bisect (it runs only the suite). Then validators plan → `implementor` fixes → validators review (max **2 rounds**) → `branch.sh rebase-fix <N> <file>` → re-run 6.1 + 6.2 → `branch.sh publish <N>`.
6. **Loop** — back to step 1: `demo` may have moved again meanwhile. A return that finds `behind: 0` goes to Step 7 and counts nothing; one that finds `behind > 0`, or a `ship` exit 3 (`not-synced`), is a **re-sync** — max **2**.
7. **Record** — each conflict resolved, fix made, or re-sync run → one `issue.sh comment <N> rebase <file>` (`### 🔀 Rebase Note`): what clashed with which `[#M]`, how it was resolved, which validators approved. Auto-approved work still leaves an audit trail.

**Resuming into Step 6b** (a blocker that names a Sync trigger) enters at **step 5**, not step 1, whenever the branch already sits on `happy-bank-demo/demo` (`behind: 0`): a cap or `base-red` block fired *after* the rebase, so the tree was never proven green, and step 1 alone would ship it. A `landed:` HEAD of `[#N] WIP blocked: sync interrupted: …` is unreviewed input to the next step-5 fix round — never a chunk to re-run. Otherwise enter at step 1.

**Validators** for a commit or fix — never an inlined file map: **`architect`** and **`rationale-reviewer`** always (as at chunk review), **`tester`** when test files change, and the doc owner per the `documentation` skill.

### 7. Ship

Load `.claude/skills/issue-lifecycle/references/ship.md` and run it in order: commit → push → completion comment (summary, plan adherence, risk outcomes, new risks, **push status**) → `issue.sh close <N>`.

The commit and push halves are one call here, because this flow branched: write the ship message to `<scratchpad>/commit_msg.md` per `ship.md` §1, then `branch.sh ship <N> <scratchpad>/commit_msg.md`. It pushes `issue-<N>` to `happy-bank-demo` (kept forever — it is where the per-chunk history lives), squash-merges it onto `demo` so history stays linear, commits, and pushes `demo`, printing `Pushed: <sha>` or `NOT pushed: …` for the completion comment's push-status line. It **refuses** if local `demo` has diverged from `happy-bank-demo/demo` — that is not a push failure but a block trigger (see Blocking); the branch is already pushed and intact. It exits **3** (`not-synced`) when `happy-bank-demo/demo` moved after Step 6b — go back to Step 6b step 1, never block on it. Then continue with `ship.md` §3–§4 as written.

A failed push exits zero and prints `NOT pushed`; report that too.

### 8. Sub-Issue Bookkeeping

If the solved issue was a sub-issue: check its parent (it carries `stage:decomposed`). If all sibling sub-issues are closed → post a comment on the parent listing the completed children, inform the user, and close the parent issue yourself.

## Blocking — the Escape Routine

These exits are failures a human must resolve. **Never ask the user first** — this flow is non-interactive, and the routine below is the whole response. Run it in this order, then **stop**:

0. **Inside Step 6b only:** a rebase still in progress → `branch.sh rebase-abort <N>` first. A finished rebase stays; `escape` pushes it with lease.
1. **Commit what exists.** Uncommitted edits from the interrupted chunk → write the summary to `<scratchpad>/wip_msg.md`, whose first line **must name the chunk**: `chunk <k>/<total> interrupted: <what was half-done>` (outside the chunk loop, `final gate interrupted: …`; inside Step 6b, `sync interrupted: …`). Then `branch.sh wip <N> <scratchpad>/wip_msg.md`. It lands as `[#N] WIP blocked: …`, which the resuming run reads as *unreviewed* and re-runs — and the subject is all it gets, so an unnamed chunk makes that re-run unexecutable. Nothing uncommitted → skip this step; `wip` refuses an empty commit rather than fabricating one, and `escape` refuses a dirty tree, so a misjudged skip is caught rather than riding onto `demo`.
2. **Push the branch.** `branch.sh escape <N>` pushes `issue-<N>` to `happy-bank-demo` and returns to `demo`. It prints the `**Branch:** …` line — paste it verbatim into the blocker body so the human has a concrete thing to inspect.
3. **Post the blocker.** Write the situation to a file and run `issue.sh block <N> implementation <file> <target-stage>` — `refined` in Standard Mode, `fresh` in Trivial Mode. Then stop and report.

The commit is what makes this safe: without it the escape would discard the run's work, which is why the pre-branch version of this flow had to leave the tree untouched instead.

| Trigger | Must include in the blocker body |
|---|---|
| Implementor ↔ Architect cap hit on a chunk | Both positions verbatim, the chunk, the disputed files |
| Final-gate fix cycle exhausted, checks still failing | The failing check and its output |
| Full test suite red and the fix cycle cannot green it | Failing test names + output |
| Specialist conflict the `product-owner` verdict cannot settle | Each position and why they are irreconcilable |
| `rationale-reviewer` reports UNCLEAR INTENT at the final gate, or at chunk review in Trivial Mode (no final gate to defer to) | The flagged decision/location, why no defensible rationale was found, numbered per the `documentation` skill's Rationale Test |
| Sync: `product-owner` finds an intent conflict with a `[#M]` issue (Step 6b.2) | Both issues, the contradiction at intent level, numbered questions. Target `refined`; resume re-enters Step 6b |
| Sync: `architect` judges the issue stale (Step 6b.3) | Its reasoning (code + time distance) and the `retire` `**Branch:**` line. Target **`fresh`** — the refinement is invalid; `/refine` runs next |
| Sync: a cap hit — conflict rounds, fix rounds, or re-syncs — or `bisect` says `base-red` | The conflicting commit/files or failing tests + output, the `bisect` hint, both validator positions; for `base-red`, the red-`demo` issue it now depends on. Resume re-enters Step 6b |
| `branch.sh ship` refuses: local `demo` diverged from `happy-bank-demo/demo` | The diverging commits it printed. Everything passed — only publication is stuck, and reconciling *local* `demo` is a human's call; Step 6b rebases the issue branch, never `demo` |
| `branch.sh ship` refuses: the squash conflicts with `demo` | The conflict it named — unreachable after a passing Step 6b, so a defect worth reporting. `demo` is untouched and nothing was committed — a human resolves it |
| **Any** `branch.sh start` or `branch.sh preflight` refusal (Step 2, or preflight in Step 6b.5): branch already exists on a fresh claim, an `--adopt` mismatch, exists nowhere on a resume, dirty working tree, local branch diverged from `happy-bank-demo`, failed fetch, the suite left the tree dirty (preflight — still **detached on `happy-bank-demo/demo`**) | The refusal verbatim, and **say that a `start` refusal is what fired** — the next run needs that to take the Step-2 carve-out instead of looping. Name what the human must settle: record a Builds-on line (adopt) vs. resume vs. delete the branch, re-record a Builds-on line whose tip moved, reconcile signal with git, clear the tree, reconcile the two branch tips, or restore network access. For the suite-dirtied tree: clean it, `git checkout` the ref the refusal printed, and track the tree-writing test as a bug |

The Sync rows follow the routine as written (with step 0); the stale row runs steps 0–1 *before* `retire` and skips step 2, since `retire` pushes the branch under its new name and returned to `demo`. The last three rows are special cases of the routine above:

- **The two ship-time refusals** fire *after* the work is complete: skip step 1 (nothing is uncommitted) and step 2 (`ship` already pushed the branch), copy the `**Branch:** …` line `ship` itself printed, and go straight to the blocker. Say in the blocker body that the resumed run re-enters at **Step 6b** — nothing needs re-implementing.
- **The `start` refusals** fire *before* any work exists: skip steps 1–2 as well, since there is no usable branch to commit onto or push, and post a blocker with **no `**Branch:**` line** — the same exemption `comment-formats.md` grants the gate re-block. This is a block, not a chat report: an unattended run that merely printed the refusal would leave the issue at `stage:refined` with nothing on it saying why nobody is working, which is the invisibility this whole change exists to remove. Say plainly in the body that a `start` refusal fired, so the resuming run takes Step 2's carve-out rather than `--resume`-ing a branch that may not exist.

A **Mid-Execution Escape is not a block** — it is a scope decision (below). Neither is a gate refusal: leave the stage untouched and tell the user what to do.

## Mid-Execution Escape

If the task turns out significantly larger than the refinement estimated: **stop** — do not implement further chunks. Spawn **`product-owner`** with the discovery; it decides: reduce scope (commit completed work, follow-up issue, then Steps 6b–7 as normal) or continue (only if remaining work is ≤2 chunks).

## Iteration Limits

| Loop | Max rounds | On cap hit |
|---|---|---|
| Implementor ↔ Architect per chunk | 2 | Escape routine (Blocking) — never a chat prompt |
| Final gate fix cycle | 1 | Ship with known issues as FOLLOW-UP, or escape routine |
| Total chunks per execution | 5 | Remaining work becomes a follow-up issue |
| Sync: Implementor ↔ validators per conflicting commit | 2 | Escape routine |
| Sync: fix rounds for a red suite after rebase | 2 | Escape routine |
| Sync: re-syncs (`demo` moved again, or `ship` exit 3) | 2 | Escape routine |

## Delegation Rules

### Participants

| Role | Who | Spawn via Task? |
|---|---|---|
| Orchestrator | Executor = **you**, the top-level loop | — (never a subagent) |
| Code & docs writer | `implementor` (every chunk) | Yes |
| Design review & integration | `architect` (every chunk; final gate when multi-chunk; Sync distance check and validator) | Yes |
| Documented-intent review | `rationale-reviewer` (every chunk; final gate — unconditional) | Yes |
| Coverage verification | `tester` (final gate) | Yes |
| AC completeness & scope decisions | `product-owner` (final gate; mid-execution escape; Sync intent check) | Yes |

### Delegation Preamble

Append this block verbatim to **every** subagent delegation prompt during implementation:

> **Context contract**: The chunk specification, relevant refinement decisions, and codebase context brief are included in this prompt (one exception: `product-owner` — see Per-Role Additions). Do NOT re-fetch the issue or re-explore areas already summarized; if something essential is genuinely missing, say so in your response instead of searching for it.
>
> **Capability contract**: You cannot post GitHub comments, create issues, close issues, or commit — the orchestrator owns GitHub and git. Implementor: you MAY run targeted tests for your chunk; never the full suite. Reviewing specialists: return findings as text only. If any instruction in this prompt requires a tool you were not granted, say so in your response instead of silently working around it.
>
> **Skills contract**: The skills relevant to your role are listed under "Skills to load" below with one-line descriptions. Load each one by reading its file directly — `.claude/skills/<name>/SKILL.md` — plus any `references/*.md` that file links and your task needs; do not rely on the Skill tool. Do NOT browse or enumerate `.claude/skills/` beyond the named ones. Load none if none apply.
>
> **Output rules**: ≤30 lines when all findings are clean. Verdict + 1-sentence summary mandatory. Single-line bullets. Omit sections with zero findings. Detail problems fully — calls are stateless, no follow-up is possible.

### Per-Role Additions

| Delegate | Add to the prompt |
|---|---|
| Implementor | Chunk's documentation updates (from the refinement documentation comment) — docs change in the same chunk as the code they describe. Chunk's assigned risks + mitigations — applying the mitigation is part of the chunk, not optional |
| Architect (per chunk) | The resulting-code rule: structural limits apply to the resulting files, not the diff. Chunk's assigned risks — confirm each mitigation was actually applied; an unapplied mitigation is NEEDS CHANGES |
| Rationale Reviewer (per chunk) | The chunk's decisions and doc updates. An UNCLEAR INTENT verdict is carried forward, not resolved in this round — see the agent file |
| Rationale Reviewer (final gate) | Any UNCLEAR INTENT carried from chunk review, so it can be discharged or escalated to Blocking |
| Any final-gate verifier | Require the closing line `New risks observed: <list> / none` — a risk visible in the final state that the refinement did not predict |
| Architect (final gate) | Per-chunk verdicts (1 line each) + instruction to assess cross-chunk integration and consistency ONLY — per-chunk quality was already verified |
| Tester (final gate) | The refinement test plan, so coverage is verified against it — not re-designed. Require an AC ↔ test evidence mapping (each acceptance criterion → the test(s) proving it, or "NOT COVERED") |
| Product Owner (final gate) | The business description's acceptance criteria + the Tester's AC ↔ test evidence mapping; verdict on completeness, and on FIX vs FOLLOW-UP when ambiguous. The codebase context brief is **NOT** inlined — the PO reasons from intent, never implementation (input rule in `.claude/agents/product-owner.md`) |
| Product Owner (Sync intent check) | Our acceptance criteria + each `[#M]` issue's body from `issue.sh brief <M>` — intent only, no code, no diff. Verdict: CONFLICT (which intent contradicts which) or CLEAR |
| Architect (Sync distance check) | The refinement's technical analysis, `behind`'s full output, the `base:` date. Verdict: CURRENT or STALE, with the reasoning that goes into the blocker or rebase note |
| Sync validators (conflict / red suite) | *Theirs* (the `[#M]` commits) vs *ours* (the chunk commit, or `bisect`'s `first-bad`), the conflicting files or failing tests. First a plan, then a review of the implementor's resolution |
| Product Owner (scope escape) | Same exclusion. Give it **your own stated discovery** — what is left, how much, and why the estimate was wrong — as your judgment, which you own. Not the code brief, not raw file findings: the PO decides scope from what you tell it, not from the codebase |

### Skills to Load (inject per role)

Subagents — `implementor` included — load skill content via **Read** against the skill's file path; do not assume a **Skill** tool grant — the authoritative grant list is `tools:` in `.claude/agents/*.md`. They cannot see which skills matter without being told which to load. Include the rows applicable to the spawned role in its prompt as a **"Skills to load"** block — skill name + the one-line description verbatim — so the subagent loads the right skill instead of searching.

| Skill | One-line description | Give to |
|---|---|---|
| `project-conventions` | Happy Bank code organization, layer rules, Python style, ruff, language rules | `implementor`, `architect` |
| `structural-discipline` | File/function/class size limits, decomposition patterns, SRP/SoC enforcement | `implementor`, `architect`, `tester` |
| `test-strategy` | pytest fixtures, helpers, tmp_path, coverage targets, test organization | `implementor`, `tester` |
| `documentation` | Which doc file covers what, its owning specialist, when a change needs a doc update, and the Rationale Test | `implementor` (when the chunk carries doc updates), doc-verifying specialist, `rationale-reviewer` |

`product-owner` (final gate) loads no skill — it judges from the inlined acceptance criteria and evidence mapping.

## Error Handling

| Situation | Action |
|-----------|--------|
| No issue number in the invocation arguments | Stop and ask the human — never guess which issue to solve |
| Gate exits non-zero | Stop; report the printed reason; never relabel to bypass it |
| Gate reports `blocker: unresolved` | Refuse even if `blocked` was cleared — a resolving comment (plain reply or `issue.sh unblock`) is what resolves it |
| Gate reports `blocked: yes` with the reply missing an answer | Re-block naming the unanswered numbers before claiming; never proceed on a partial answer. Carry the previous blocker's `**Branch:**` line and its `start`-refusal statement forward — the re-block is the only blocker the next run reads |
| `gh`/`git` CLI unavailable | Follow `github-issues` skill error handling; report to user |
| Issue not refined and not trivial | Stop; tell the user to run `/refine <N>` |
| `branch.sh start <N>` refuses: `issue-<N>` already exists on a fresh claim (`builds-on: none`) | Escape routine's `start` row (Blocking) — block, naming the branch. A prior run left it, the gate's resume signal was missed, or a human prepared it without a Builds-on record. A human decides: record `**Builds on:** issue-<N> @ <sha>` (adopt), resume, or delete. Never delete or overwrite the branch |
| `branch.sh start <N> --adopt` refuses: tip moved, sha unknown, or branch missing | Escape routine's `start` row — block, pasting the refusal. The branch no longer matches what was analysed. A human reconciles it and re-records the line (re-refining if the new commits change the plan) |
| `branch.sh start <N> --adopt` refuses: the branch holds `/solve` commits | Escape routine's `start` row — block. It is an interrupted run, not a prepared base. A human posts `**Builds on:** none` (the next run resumes via the carve-out) or deletes the branch |
| `branch.sh start <N> --resume` refuses: the branch exists nowhere | Escape routine's `start` row — block. The issue says a run was interrupted but git has no record of it; a human reconciles the two |
| `branch.sh start` refuses: working tree dirty | Escape routine's `start` row — block, listing the files. Uncommitted work belongs to someone else (or a crashed run) and must not be carried across a checkout |
| `branch.sh ship` refuses: working tree dirty | A Step 5 doc update or Step 6 fix was never committed. Land it with `branch.sh fix <N> <file>` and retry the ship — never stash, never `git add` by hand |
| `branch.sh escape` refuses: working tree dirty | Escape step 1 was skipped wrongly. Run `branch.sh wip <N> <file>` (naming the chunk), then escape again |
| `branch.sh ship` refuses: local `demo` diverged, or the squash conflicts | Escape routine's ship rows (Blocking) — post the blocker; never rebase or reset `demo`, never hand-resolve outside Step 6b |
| `branch.sh ship` exits 3 (`not-synced`) | Back to Step 6b step 1; counts as a re-sync |
| `branch.sh rebase-continue` refuses: conflict markers remain | The resolution is incomplete — another implementor round for the named files (counts against the per-commit cap) |
| `branch.sh retire` refuses (rebase in progress, dirty tree) | Step 6b.3's clear-the-tree order was skipped — `rebase-abort` / `wip` first, then retry `retire` |
| `branch.sh publish` fails (lease refused or network) | Someone pushed `issue-<N>` since the rebase fetched — never retry with a stronger force. Escape routine; the blocker carries the printed line |
| `branch.sh preflight` red (Step 2) | File or link the red-`demo` issue, `issue.sh depend`, post the `waiting` comment, stop. Not a block: stage untouched, no `blocked` label. IDs `<N>`'s own body names are dropped first (it fixes them); none left → branch as normal. `UNPARSED pytest-exit-<rc>` is an ID like any other |
| Gate refuses with `waiting: #M…` | Stop and report the open blockers. The issue becomes solvable on its own once they close; never remove the dependency to get past it |
| Lint or full test suite fails at final gate | Treat as FIX verdict (the preflight proved the base green); after the fix cycle cap, escape with failing output |
| Scope larger than estimate | Mid-Execution Escape via Product Owner |
| A needed tool/capability is missing | Report to user; do not substitute another agent for its tools |
| Subagent result redirected to a file you cannot read | Re-request: "Return ALL findings directly in your final message, ≤30 lines" |
