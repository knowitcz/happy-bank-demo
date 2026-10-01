---
name: 'issue-lifecycle'
description: 'Stage-label contract for GitHub Issues in this repo: the stage:* vocabulary, allowed transitions, the gate that refuses work on blocked issues, and the scripts/issue.sh helper that performs every stage change, comment, block, unblock, and close. Also owns `/solve`''s git workflow via scripts/branch.sh: the issue-<N> branch, per-chunk commits, the escape routine''s commit-and-push, the Sync-with-main rebase before ship, and the squash-merge ship. Load before changing an issue stage, recording stage output, writing any issue or comment body file for issue.sh, or running any git operation inside `/solve` — "which branch does solve work on", "how do I commit a reviewed chunk", "how does a blocked run save its work", "main moved under my branch", "rebase the issue branch". DO NOT USE FOR: running a refinement (use the `/refine` command), running an implementation (use `/solve`), or creating a plain issue (use github-issues).'
---

# Issue Lifecycle – Stage Contract

Defines the single stage state machine that `/refine` and `/solve` obey; both call `scripts/issue.sh` for every issue mutation so stage labels and the durable comment log never diverge. The script splits along its two responsibilities: `issue.sh` holds the stage machine and command dispatch, and the `scripts/lib/compose.sh` it sources holds the heading registry, the AI-author marker, and the round-trip check. A sibling `scripts/branch.sh` owns the git half of `/solve` for the same reason — one script per external surface, so an unattended run needs one permission grant rather than one per verb.

## When to Use

Use this skill when:
- A flow is about to start work on an issue and must check the gate first
- An issue's stage label must change (claim, advance, decompose, block, unblock)
- A stage outcome must be recorded as a comment on the issue
- A blocked issue is being resolved by the human
- `/solve` needs any git operation — claiming its `issue-<N>` branch, committing a reviewed chunk or a fix, rebasing it onto a moved `demo`, saving and pushing work as it blocks, or reading what already landed on a resume
- An implemented issue is being shipped and closed (commit → push → comment → close)

## 0. Reading an Issue

`issue.sh brief <N>` is the standard read: title, state, stage, body, and the comment log — with `### 💰 Cost` comments filtered out (see below and [references/comment-formats.md](references/comment-formats.md)). Never inline `gh issue view` output where `brief` would do.

## 1. Gate Before Any Work

Run `bash <skill-dir>/scripts/issue.sh gate <N> <refine|solve>` as the **first** action of any flow. It exits non-zero on a hard refusal; stop and report the reason to the user. Never inspect labels by hand instead — clearing the `blocked` label does **not** unblock an issue by itself; a comment resolving it (structurally, not just any comment) does.

The gate prints `stage`, `approved`, `refined`, `blocker`, `blocked`, `waiting`, `builds-on`, `resume`, `ai`, and `verdict` lines (`waiting` and `builds-on` are computed for `solve` only; `builds-on` is the sha a readiness stamp or human recorded for `/solve` to adopt — see [references/branching.md](references/branching.md)). Apply flow-specific policy (trivial mode, approval requirement) to those values; the hard refusals are the script's decision, not yours. `blocked: yes` means this invocation follows a block — see §5.

> See [references/states.md](references/states.md) for the stage vocabulary, transitions, and refusal rules.

## 2. Claim the Stage

Immediately after an OK gate, mark work in progress: `issue.sh set-stage <N> in-refinement` or `issue.sh set-stage <N> in-implementation`. A crashed session then leaves a truthful state, and the gate reports `resume: yes` on the next run.

## 3. Record the Outcome

Write the comment **body** to a temp file, then `issue.sh comment <N> <key> <file> [suffix]` with a key from the [registry](references/comment-formats.md) (e.g. `exploration`, `refinement`). The script emits the registered heading, stamps the `🤖` AI-author marker directly beneath it, and verifies the round trip — so the log stays parseable and every AI-authored artifact is attributable. What the file may contain is the **Body files** rule in Notes.

> See [references/comment-formats.md](references/comment-formats.md) for the heading registry, the marker position, and templates.

Then advance the stage with `issue.sh set-stage <N> <refined|decomposed>`.

## 4. Block When a Human Must Decide

When a question or failure cannot be resolved without the human, write the numbered questions to a file and run `issue.sh block <N> <refinement|implementation> <file> [target-stage]`. A refinement block takes no further argument (stage stays `in-refinement`); an implementation block requires `target-stage` — `refined` in Standard Mode, `fresh` in Trivial Mode — because the resumed run needs to land there regardless of when the block resolves (see [references/states.md](references/states.md) §2). This posts the blocker comment with its durable marker and adds the `blocked` label. Then **stop** — do not continue the flow, do not guess the answer, do not open a follow-up issue instead.

Whether the human is asked in-session first is the **flow's** decision, not this skill's. Both flows are non-interactive today and neither asks: `/refine` batches its questions and blocks at a checkpoint; `/solve` runs its escape routine — commit, push the issue branch, block — see [references/branch-exits.md](references/branch-exits.md). Each keeps exactly one ask, at flow entry only, when no issue number was given: there is no issue yet to write a blocker on.

## 5. Resolve (human-driven only)

The human resolves the blocker by replying on the issue — a plain reply is sufficient; `issue.sh unblock <N> <file>` remains available for a structured, explicitly-marked answer, but takes no target-stage argument any more since `block` already set it. Either way, do not verify the answer covers every numbered question yourself — that check belongs to the *resuming* flow (§2's `blocked: yes` signal), which re-blocks naming any gaps rather than proceeding on a partial answer.

Never post an unblock marker as part of a refine or solve run, and never infer the answers from the codebase — the comment log is the only evidence the gate trusts. `set-stage`, run by the resuming flow once it claims, clears `blocked` as a side effect — a resolved-but-unclaimed block correctly still shows `blocked: yes` until then.

## 6. Ship and Close

`issue.sh close <N>` strips the stage label and closes the issue. A closed issue carries no `stage:*` label; closed-with-no-stage **is** the finished state — and `gate` refuses every flow against it, reading the issue's own `state` rather than letting the absent label read as `fresh`.

Closing is the last step of a fixed sequence when a flow has produced actual changes — commit, push, completion comment, then close — shared by every flow that lands work on an issue.

> See [references/ship.md](references/ship.md) for the shared commit → push → completion comment → close mechanics, including the push-failure policy and the completion-comment template.

`/solve` additionally does its work on an `issue-<N>` branch — a commit per reviewed chunk, rebased onto `happy-bank-demo/demo` by its Sync step when `demo` moved, squash-merged onto `demo` at ship time — executed by `scripts/branch.sh` (sync mechanics in `scripts/lib/sync.sh`). That is `/solve`-only — apart from the read-only `branch.sh log`, which `/refine` runs to record the branch it builds on: `/process-ai` and `/discover-debt` commit straight to `demo`, which is why `ship.md` stays flow-agnostic.

Remote and base branch are declared once, in `scripts/lib/git.sh` (`REMOTE=happy-bank-demo`, `MAIN=demo`); every fetch, push and remote ref in the scripts derives from them. Never use `origin` (it is a different repo) and never a bare `git push` (local `demo` tracks `origin`).

> See [references/branching.md](references/branching.md) for the branch itself — subcommands, the commit-subject contract, branch selection on resume, and `start`'s refusals — and [references/branch-exits.md](references/branch-exits.md) for the two ways a run leaves it: the squash-merge ship and the escape routine's git half.

## Notes

- **Cost recording** (`### 💰 Cost` comments, posted by the `session-cost` skill via `issue.sh cost <N> <file> <session-id>`) is a separate mechanism from every flow above — it fires on session teardown, not from `/refine` or `/solve`. `issue.sh comment` refuses the `cost` key, since posting it there would skip the per-session marker; see `session-cost/SKILL.md`.
- `approved` is a human-only label. No skill, agent, or command may add it.
- `issue.sh` is the **only** writer of issue text. Never hand-roll `gh issue create` / `comment` / `edit --body-file` / `edit --add-label stage:*` / `close` — a hand-rolled write is unmarked, unverified, and stage-less. Reads may use `gh` directly.
- **Body files** — the single rule for every writer (`create`, `comment`, `set-body`, `block`, `unblock`, `cost`): the file holds **content only** — no `###` heading, no `🤖` marker. `issue.sh` emits both, so a typed one only duplicates them; earlier issue bodies carry the marker, so never copy it from them. As a backstop the script strips a leading heading (comments) and leading marker lines (every writer) with a stderr note, and refuses a file left with no content.
- New issues are opened with `issue.sh create "<title>" <file> [gh flags...]`, which applies `stage:fresh` and the marker.
- `issue.sh init-labels` creates the canonical label set — run it once in a fresh repo, and once more in an existing repo to pick up any newly-added label (e.g. `blocked` did not exist before this change; every command that touches it tolerates its absence, but nothing can attach it until this runs). It also deletes the two label names `blocked` superseded (`stage:blocked-refinement`, `stage:blocked-implementation`) — safe to re-run either way.
- `gate` refuses an `ai`-labeled issue for both `refine` and `solve`, regardless of stage or blocker state — AI-asset changes are filed via the `report-difficulty` skill and processed by their own interactive flow, not this state machine.
- `issue.sh list` is a **read-only backlog snapshot, not an issue fetch**: open issues with stage, `approved`/`blocked`/`ai` markers, and parent/sub-issue relations (only open sub-issues are named; a fully-closed set of children still renders a marker instead of looking childless). It must never be inlined into a subagent prompt, and its failure is never a stop condition — see Error Handling.

## Error Handling

| Situation | Action |
|-----------|--------|
| Gate exits non-zero | Stop; report the printed reason verbatim; do not relabel to work around it |
| `blocker: unresolved` but `blocked: no` | Trust the marker, refuse the work, tell the user the label was cleared without a resolving comment |
| `blocked: yes` but `blocker: none` | Stale label from a resolution the claiming flow hasn't consumed yet — not an error; claiming the stage (`set-stage`) clears it as a side effect |
| Stage label present that is not in the vocabulary | Stop; ask the user to remap it rather than guessing |
| `gh` CLI unavailable or unauthenticated | Follow `github-issues` skill error handling; report to user |
| `set-stage` rejects the stage name | Consult [references/states.md](references/states.md); do not create ad-hoc stages |
| Issue is `stage:decomposed` | `gate` refuses it outright; report the open sub-issues so the human can pick one. A non-interactive flow states them, it does not wait on an answer |
| Resume after a block finds unanswered questions | Re-block, naming the unanswered numbers, before claiming — never proceed on a partial answer |
| `issue.sh list` fails (unsupported `gh` JSON field, network) | Advisory only — note the failure to the user and continue without backlog context; never treat it as a gate refusal |
