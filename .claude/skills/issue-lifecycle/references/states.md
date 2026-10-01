# Stage Vocabulary, Transitions & Refusals

The `stage:*` label names the **state the issue is in** (a fact already established), never the next action to take.

## 1. States

| Label | Meaning | Set by | Leaves via |
|---|---|---|---|
| *(none)* or `stage:fresh` | Filed; no analysis yet — or a sub-issue whose re-sizing came back borderline/over, carrying inherited analysis but not readiness — or a resolved Trivial-Mode implementation block, no `stage:refined` to return to | issue creation (`github-issues`, `discover-debt`); `/refine` step 8b (demoted child); `issue.sh block implementation` (Trivial Mode target, or a Standard-Mode Sync step that judged the issue stale) | `/refine`, or `/solve` again when it's a resolved block |
| `stage:explored` | Exploration recorded, no spec yet | *reserved — no flow produces it today* | `/refine` |
| `stage:in-refinement` | A refinement run is in progress — or was blocked and is awaiting/received a human reply, see `blocked` below | `/refine` step 0 | refined / decomposed / closed |
| `stage:refined` | Spec + AC complete, awaiting `approved` — or an implementation was blocked in Standard Mode and stands here until resolved | `/refine` readiness stamp (8a branch); `/refine` step 8b (right-sized child); `issue.sh block implementation` (Standard Mode target) | human adds `approved`, then `/solve` |
| `stage:decomposed` | Split into sub-issues; never implemented directly | `/refine` step 9 (8b branch) — after the readiness stamp, so a crashed decomposition doesn't strand the parent behind the tracking-parent refusal | children are solved; parent closes last |
| `stage:in-implementation` | A solve run is in progress | `/solve` after gate | close / blocked |
| *(no label, closed)* | Finished — `gate` refuses every flow against it (§3), so the missing label is never read as `fresh` | `issue.sh close` | — |

`approved` is an **orthogonal, human-only** label; never set by a skill, agent, or command. It survives an implementation block to `refined` so a re-run does not need re-approval. A block to `fresh` drops it (`issue.sh block` does this): a stale spec goes back to `/refine`, and the re-refined one must be read and approved anew — removing the label is not adding it, so the human-only rule holds. Trivial Mode never needs `approved`, so it loses nothing.

`blocked` is a second **orthogonal** label, not a `stage:*` value — see §5. It marks that a human decision is required, the same way `approved` marks sign-off; the underlying `stage:*` already reflects where the issue resumes from once the block clears.

## 2. Transitions

```
fresh ──/refine──> in-refinement ──┬──> refined ──(human: +approved)──> ──/solve──> in-implementation ──> closed
  ^                  ^             ├──> decomposed ──> (sub-issues: refined, or fresh if re-sizing says so)
  |                  |             └──(+blocked, stays here)──┐
  |                  └──────────────────── resolved ──────────┘
  |
  fresh <──(+blocked, Trivial Mode, or stale)── in-implementation ──(+blocked, Standard Mode)──> refined
```

**Stale** (#196): `/solve`'s Sync step found `demo` moved so far that the refinement no longer describes the code it would land on. The spec is invalid, so the target is `fresh` — `/refine` runs again — not `refined`. `branch.sh retire` renames `issue-<N>` first, so the re-refined issue's next `/solve` makes a clean fresh claim.

A refinement block never leaves `in-refinement` — `/refine` is non-interactive and blocks often, so the resumed run continues from the comment log instead of re-refining from zero. An implementation block moves **immediately**, at block time, to the stage the resumed solve run needs anyway: `refined` in Standard Mode, `fresh` in Trivial Mode (which never produces `stage:refined` to begin with).

The reason is that **the stage is not what a solve run resumes from.** Its resume evidence is the `issue-<N>` branch: the escape routine commits and pushes it before blocking, and the resumed run reads its commits — reviewed chunks land, a `WIP blocked` HEAD is re-run (see [branching.md](branching.md)). So the stage is free to say the plainly useful thing instead, namely where the issue stands for a *human* reading the issue: a Standard-Mode issue still has its refinement spec, a Trivial-Mode one never had one. `approved` survives either way, which is what lets the re-run proceed without re-approval.

> Superseded rationale, recorded because it justified this same behaviour on a premise that is now false (#148): "`/solve` commits once, at the very end — there is no per-chunk commit, so resuming mid-implementation from uncommitted edits can't be trusted." Per-chunk commits removed that premise; the behaviour was re-decided on the branch-evidence reasoning above and kept unchanged.

Sub-issues inherit the parent's completed analysis, but inheriting the analysis is not the same as inheriting readiness. `/refine` Step 8b re-sizes every child it creates (see that step for how the size is derived) and stamps it accordingly: `stage:refined` when it fits the budget, otherwise `stage:fresh` plus a `size verdict` comment, which must be re-refined before `/solve` will take it. That demotion is what stops a child too large for one implementation pass from looking ready. Either way a child requires its **own** `approved` label; approving the parent does not approve its children.

## 3. Hard Refusals (enforced by `issue.sh gate`)

The script exits non-zero, for both flows unless the row says otherwise, when:

| Condition | Reason |
|---|---|
| Issue is **not a confirmed open issue** | Closed → finished work, no flow may run against it; state unreadable (bad number, `gh` failure) → nothing to verify against. Both checked first, from the issue's own `state`, before any other signal is computed, since `close` strips the stage label and the absent label would otherwise read as `fresh`. Enforced by `gate` **only**: `set-stage`, `comment`, `block` and `cost` still accept a closed issue, and `cost` necessarily so — the `session-cost` hook and sweep post after the flow that closed it |
| `ai` label present | AI-asset changes are processed by their own interactive flow, not `/refine`/`/solve` — checked before any stage/blocker signal |
| Unresolved blocker marker in the comment log | A human decision is outstanding, regardless of the `blocked` label's state |
| `stage:decomposed` | The parent is a tracking issue; solve or refine its children |
| `gate <N> solve` while `stage:in-refinement` | A refinement run is live or crashed mid-way; the spec is not trustworthy |
| `gate <N> refine` while `stage:in-implementation` | Code is being written against the current spec; re-refining would invalidate it |
| `gate <N> solve` with an open native "blocked by" dependency (`waiting:` ≠ `none`) | The issue waits on another issue, e.g. a red-`demo` bug filed by `/solve`'s preflight. Solve only: refining needs no green `demo`, so `refine` prints `waiting: n/a` without querying; a failed query refuses `solve`. It clears on its own when the blockers close, with no label or reply. `issue.sh depend` records the dependency, and it is the only record |

A blocker is **unresolved** when the latest structurally-valid block comment (§5) has no comment after it that is either the structurally-valid unblock marker or simply not AI-authored — a plain human reply resolves a block exactly as well as `issue.sh unblock`. There is no separate stage-based refusal for a blocked issue: the two rows above already refuse a wrong-flow attempt regardless of blocking, and a `refined`+`blocked`(unresolved) or `in-refinement`+`blocked`(unresolved) issue is caught by the marker check before any stage logic runs.

## 4. Soft Signals (flow decides)

The gate prints these for the flow to act on; they are never a refusal by themselves:

| Line | Use |
|---|---|
| `approved: yes\|no` | `/solve` requires `yes` outside Trivial Mode |
| `refined: yes\|no` | `/solve` falls back to the Trivial Mode check when `no` |
| `blocked: yes\|no` | Label-based, cheap. `yes` means this invocation follows a block — the flow must read every human-authored comment after the block comment, map it against the original numbered questions, and re-block (naming any gaps) before claiming, rather than assume the reply is complete. **Deliberately label-based, not comment-log-based**: the comment log records a resolved block forever, so a marker-derived signal would never stop firing — `blocked` only stops meaning "unconsumed" once the resuming flow claims (§1). A human manually clearing `blocked` bypasses this — the blocker template tells them not to |
| `resume: yes\|no` | `yes` means a prior run of this same flow did not finish — read the comment log for partial progress before redoing work |

**Automation rule:** any automated issue-selection query (e.g. a future unattended picker) MUST exclude `blocked` issues, exactly as it must already check `approved` (and, for solve, issues with an open `blockedBy`). `stage:fresh`+`blocked` (a resolved Trivial-Mode block) and `stage:refined`+`approved`+`blocked` (a resolved Standard-Mode one) both look like ordinary ready candidates by stage and `approved` alone — `blocked` is what says a flow still needs to consume the reply first.

## 5. Label Definitions

`issue.sh init-labels` creates exactly this set:

| Label | Colour | Description |
|---|---|---|
| `stage:fresh` | `#1d76db` | Filed; not yet refined |
| `stage:explored` | `#1d76db` | Explored; ready for refinement |
| `stage:in-refinement` | `#fef2c0` | Refinement in progress |
| `stage:refined` | `#0e8a16` | Refined; awaiting human approval |
| `stage:decomposed` | `#5319e7` | Split into sub-issues; tracking only |
| `stage:in-implementation` | `#fef2c0` | Implementation in progress |
| `approved` | `#fbca04` | Human-approved; ready to implement |
| `blocked` | `#b60205` | A human decision is required; see the `⛔ Blocked` comment |
| `ai` | `#7057ff` | AI assets: skills, agents, commands, prompts |
| `ai-in-progress` | `#fef2c0` | `process-ai` concurrency guard; set by `issue.sh ai-start`, cleared by `ai-finish` |

A block is detected structurally, not by substring search: the AI marker (`🤖`) must be the first or second non-blank line of a comment, and the block/unblock marker must be its exact last non-blank line — both resist a GitHub quote-reply, which blockquotes every line with `> ` and would otherwise falsely satisfy a plain `contains()` check. `ai`-labeled issues skip `stage:*` and `blocked` entirely — they run through `process-ai`, not `/refine`/`/solve`.
