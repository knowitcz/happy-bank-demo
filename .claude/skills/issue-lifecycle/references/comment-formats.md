# Comment Heading Registry, AI Marker & Templates

`scripts/issue.sh` is the only writer of issue text; `scripts/lib/compose.sh` holds the formatting half it sources. Between them they emit the heading, stamp the AI marker, and verify the round trip; what a caller's body file may contain is `SKILL.md`'s **Body files** rule.

Keep comments tight: a durable decision log, not a transcript.

## AI Author Marker

Every comment and every issue description authored by an AI carries `🤖` on its own line, **directly below its header**:

| Artifact | Header | Marker position |
|---|---|---|
| Comment | the `###` heading | the line below the heading |
| Issue body | the issue title (no in-body heading) | the body's first line |

The marker sits *below* the heading rather than inside it so the headings below stay byte-identical — later sessions parse them, and a re-emojied heading would break that.

## Registry

Headings are fixed. The key in column 1 is what you pass to `issue.sh comment`; the script maps it to the heading. This table and `heading_for()` in `scripts/lib/compose.sh` must change together.

| Key | Heading | Posted by | Marks |
|---|---|---|---|
| `exploration` | `### 🔍 Exploration` | any flow, before a spec exists | Findings that precede refinement; `process-ai` reads this heading as a phase heading |
| `refinement` | `### 📐 Refinement` | `/refine` (on the issue being refined, and on each sub-issue it creates); `process-ai` (brainstorming phase, `— brainstorming` suffix; unresolved reviewer objections on a waived run, `— objections` suffix) | Business description, specialist analysis, readiness stamp; on a sub-issue, its inherited analysis and its size verdict — or, for `process-ai`, the design decision and alternatives considered, or objections a human must resolve before the run can be re-entered |
| `implementation` | `### 🛠 Implementation` | `/solve`; `process-ai` | Completion report |
| `difficulty` | `### ⚠️ Difficulty Note` | `report-difficulty` (one-time branch) | A difficulty judged one-time, resolved by the fix just applied — never a phase key, so it can't be mistaken for one by anything scanning phase headings |
| `observed` | `### 🔁 Observed Again` | `report-difficulty` (recurring branch, existing-issue match) | A difficulty resurfaced on an already-filed issue — never a phase key |
| `rebase` | `### 🔀 Rebase Note` | `/solve` Sync step | A rebase-time event resolved automatically — conflict resolved, suite re-greened, re-sync — auto-approved, recorded so a human can audit it. Distinct from `difficulty` (a gap in an AI asset) and never a phase key
| `waiting` | `### ⏸ Waiting` | `/solve` Step 2 preflight | `demo` was red, so the issue now waits on the named native-dependency blockers; the solve gate clears it when they close. Never a phase key
| `cost` | `### 💰 Cost` | `session-cost` skill, via `issue.sh cost` only | One session's estimated token/dollar spend on this issue. Never a phase key either — nothing scanning for phase progress should see it |
| — | `### ⛔ Blocked — <flow>` | `issue.sh block` | Open questions; carries `<!-- issue-lifecycle:blocked -->` |
| — | `### ✅ Unblocked` | `issue.sh unblock` | Human answers; carries `<!-- issue-lifecycle:unblocked -->` |

`block` and `unblock` own their headings outright and take no key.

## Cost Body

Posted by `issue.sh cost <N> <file> <session-id>`, not by `comment` — the third argument is stamped into the body as `<!-- issue-lifecycle:cost:<session-id> -->`, which is how a re-run recognizes its own comment and declines to post a duplicate. Unlike the block markers this one is *parameterized*: several cost comments legitimately coexist on one issue (a refine session, then a solve session, then each resumed leg), so the guard has to identify the session rather than the comment kind. Never write the marker into the body file yourself; `issue.sh` composes it.

The body itself is fixed by the [`session-cost`](../../session-cost/SKILL.md) skill — a one-line human summary followed by a JSON block with a stable schema, so per-issue cost stays comparable across issues rather than being prose someone has to read. Nothing else may post under this key — `issue.sh comment` refuses `cost` outright, pointing the caller at `issue.sh cost` instead.

Cost comments are also **filtered out of `issue.sh brief`**, matched by their trailing marker line (never by substring — a comment that merely discusses the marker text stays in the log): a recorded run's cost is an analysis artifact, not decision-log content a later flow needs to re-read, and leaving it in would inflate every subsequent run's context with its own history of JSON blocks. `brief`'s comment count reports how many were omitted, e.g. `(3 + 2 cost, omitted)`.

## Posting

```
issue.sh comment <N> <key> <file> [suffix]
```

The optional fourth argument appends `— <suffix>` to the heading; it is free-form, so a new suffix needs no script change — only an entry here. `/refine` posts several `refinement` comments across its flow and distinguishes them this way:

| Suffix | Posted on | Meaning |
|---|---|---|
| `business description`, `specialist findings`, `technical analysis`, `documentation changes`, `loc estimate`, `chunk breakdown`, `readiness stamp` | the issue being refined | The canonical outputs of that issue's **own** refinement run — reserved for it, so a later run on the same issue can tell its own work from anything inherited. `loc estimate` carries the Step 6 per-file/per-module tables verbatim: Step 8b apportions them, and a resumed run has only the comment log to read them from |
| `sub-issues` | the parent being decomposed | The child list with each child's stamped stage — canonical for the parent's own run |
| `inherited analysis` | a sub-issue, by the parent's Step 8b | The parent's specialist analysis, copied down. Deliberately *not* a canonical suffix: a demoted child gets re-refined and must not collide with its own future comments |
| `size verdict` | a sub-issue, by the parent's Step 8b | The child's apportioned size came back borderline or over, so it stayed `stage:fresh` and must be re-refined. Also disqualifies the child from `/solve`'s Trivial Mode |

Example:

```
issue.sh comment 42 refinement body.md "business description"
→ ### 📐 Refinement — business description
```

A body file whose first non-blank line is a markdown heading (1–6 `#` followed by a space) has that line **stripped** — the registry emits the real heading, so a caller-supplied one is dropped with a stderr note rather than failing the write. A line like `#42 relates to...` is not a heading and survives untouched. A body that is nothing but that heading, with no content left afterward, is still rejected.

## Blocker Body

Pass to `issue.sh block`. Content only, per `SKILL.md`'s **Body files** rule:

```markdown
**Stage reached:** <what completed before the block>
**Branch:** `issue-<N>` @ `<sha>` (pushed to happy-bank-demo)

**Questions**
1. <question — one decision per number, answerable without reading code>
2. <…>

**Why this needs a human:** <business intent / trade-off / external dependency>
**What unblocks it:** answer every question above, either as a plain reply on
the issue or via `issue.sh unblock <N> <answers-file>` for a structured one —
either resolves it. The resuming flow re-checks the reply against every
numbered question and re-blocks, naming any gaps, before it claims the issue.
**Do not remove the `blocked` label by hand** — the resuming flow clears it
once it has actually consumed your reply; clearing it early just makes an
unconsumed reply look identical to a virgin issue.
```

`issue.sh block <N> refinement <file>` takes no further argument — the stage stays `in-refinement`. `issue.sh block <N> implementation <file> <target-stage>` requires one: `refined` in Standard Mode, `fresh` in Trivial Mode (the caller's own mode, not a choice made here).

Implementation blocks additionally state which escape fired: implementor↔architect cap, final-gate fix-cycle cap, red full test suite, an unresolvable specialist conflict, a `rationale-reviewer` UNCLEAR INTENT with no defensible rationale, or — at ship time — a local `demo` that diverged from `happy-bank-demo/demo`, a squash of `issue-<N>` that conflicts with `demo`, or a `branch.sh start` refusal that fired before any branch existed. Name the failing check and paste its output. `/solve` owns this list — it is reproduced here only so a blocker body can be written from this file alone; the two must change together.

The **Branch** line belongs on every implementation block — `/solve` commits and pushes `issue-<N>` before blocking, so the human gets a concrete tree to inspect rather than a description of one. Copy it verbatim from whichever command printed it: `branch.sh escape` on the ordinary path, `branch.sh ship` when it is the ship-time refusal that blocked (which skips `escape`). Three blocks have no such line of their own and omit it: a **refinement** block, which has no branch; `/solve`'s **gate re-block** on an incomplete reply, which fires before any branch is checked out; and `/solve`'s **`start`-refusal block**, which fires because the branch could not be claimed at all — it says so in the body instead, and inventing a `**Branch:**` line there would post a git fact that is not true. The re-block instead **repeats verbatim** whatever the blocker it is answering carried — the `**Branch:**` line, and any statement that a `branch.sh start` refusal fired. It becomes the latest blocker, and the resuming run reads only that one, so anything dropped here is simply lost: a dropped refusal statement sends the next run down the resume path against a branch that does not exist.

## Unblock Body

Pass to `issue.sh unblock <N> <file>` (optional — a bare human reply resolves a block too). Must answer **every** numbered question from the blocker:

```markdown
**Answers** (to #<comment-ref>)
1. <the human's decision, verbatim intent>
2. <…>

**Resulting change to scope:** <none / what shifted>
```

`unblock` takes no target-stage argument — `block` already set the correct stage when the block was posted (see Blocker Body above).

## Builds-on Line

`**Builds on:** issue-<N> @ <full sha>` or `**Builds on:** none — <why>`, on its own line (a list marker in front is fine). It records the `issue-<N>` branch state that `/solve` adopts instead of creating a fresh branch (#206). The gate's `builds-on:` signal reads it only from the `readiness stamp` comment or a human-authored comment; the latest one wins. A line quoted in any other AI comment is ignored, so a blocker must never be the one that records it.

## Implementation Completion Body

Pass to `issue.sh comment <N> implementation <file>`. The shared Ship Mechanics template is the canonical shape for this key — see [ship.md §3](ship.md) — so it isn't duplicated here; `process-ai` adapts it for an asset change per its own command doc instead of reusing it verbatim.
