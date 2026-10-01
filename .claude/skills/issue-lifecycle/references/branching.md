# Branch Workflow (`/solve` only)

One `issue-<N>` branch per issue, a commit per reviewed chunk on it, a
squash-merge onto `demo` at ship time. `scripts/branch.sh` executes all of it;
this file is the contract it implements. **Scope: `/solve` only** (plus `/refine`'s
read-only `log`, to record a branch it builds on) — `/process-ai`
and `/discover-debt` still commit straight to `demo`, so `ship.md` stays
flow-agnostic and only points here. Why that split, why a script instead of
inline `git`, and why the branch is squashed but never deleted:
`docs/decisions.md`, the #148 rows.

## The subcommands

| Call | When |
|---|---|
| `branch.sh preflight` | Fresh claim, just before `start`: runs the full suite on `happy-bank-demo/demo` detached, then returns to where it was. Prints `preflight: green\|red`, `sha:`, and for red a `failed:` list of `FAILED`/`ERROR` IDs (or `UNPARSED pytest-exit-<rc>` when none) plus `summary:`. Both verdicts exit 0; a dirty tree or failed fetch refuses like `start` |
| `branch.sh start <N> [--base <sha>]` | Fresh claim — creates `issue-<N>` off a freshly-fetched `demo`, or off `--base` (preflight's proven sha; refused if not on `happy-bank-demo/demo`) |
| `branch.sh start <N> --resume` | `resume: yes` or `blocked: yes` — checks out the existing branch |
| `branch.sh start <N> --adopt <sha>` | Fresh claim with gate `builds-on: <sha>` — checks out a human-prepared branch whose every tip is exactly `<sha>` (see Branch selection) |
| `branch.sh chunk <N> <k> <total> <file>` | A chunk whose review passed |
| `branch.sh fix <N> <file>` | A post-review fix-cycle change |
| `branch.sh rebase-fix <N> <file>` | A fix that re-greens the suite after a Sync rebase |
| `branch.sh wip <N> <file>` | Partial, unreviewed work an escape interrupted |
| `branch.sh escape <N>` | Push the branch, return to `demo` — the escape routine's last git step |
| `branch.sh ship <N> <file>` | Push the branch, squash onto `demo`, commit, push `demo` |
| `branch.sh log <N>` | Fetch (best-effort), print `tip:` (full sha; `origin-tip:` too when it differs from the remote) and the branch's commits — how a resume reads what landed; also answers "is there a branch?" (`branch: none`, exit 0) |
| `branch.sh where` | Print the current branch |

**Sync with main** (`/solve`'s Sync step, before ship — mechanics in `scripts/lib/sync.sh`):

| Call | Contract |
|---|---|
| `behind <N>` | Fetches; prints `behind:`, `base:`, the new `happy-bank-demo/demo` commits, the `[#M]` issues they name, and the file `overlap:` with the branch. Read-only |
| `rebase <N>` | Rebases onto `happy-bank-demo/demo` (`GIT_EDITOR=true`). `rebase: done` → exit 0; `rebase: conflict` + commit + files → **exit 2**, rebase left in progress |
| `rebase-continue <N>` | Refuses while any conflicted file still holds a `<<<<<<<`/`>>>>>>>` marker; else stages and continues. Same output/exit as `rebase` — the next commit may conflict too |
| `rebase-abort <N>` | Restores the pre-rebase branch; a no-op when none is in progress |
| `bisect <N>` | Verifies the base green first (`first-bad: base-red` otherwise), then `git bisect run uv run pytest`; pytest exit ≥2 is *skip*. Prints `first-bad: <commit>` + files, or `inconclusive`. Always resets and ends on `issue-<N>` |
| `publish <N>` | Pushes `issue-<N>`; `--force-with-lease` only when the remote's copy is not an ancestor (i.e. after a rebase). No fetch — the lease is the remote's sha as `rebase` last saw it |
| `retire <N>` | Renames to `issue-<N>-stale-<date>`, pushes it, then drops `issue-<N>` from the remote; ends on `demo`. Nothing is deleted — the history lives on under the new name |

`ship` exits **3** (`not-synced`) when `happy-bank-demo/demo` is not an ancestor of the branch — a route back into Sync, not a block. `escape` refuses while a rebase is in progress and, like `ship`, force-pushes with lease only a rebased branch.

`<file>` is a commit-message file: first non-blank line is the summary, the rest
is the body. The script composes the subject prefix — never write one yourself,
and never `git commit -m` (inline messages corrupt backticks and `$`).
**`branch.sh` is the only git a flow runs** (`/refine`: `log` only); inline `git` is forbidden.

## Commit-subject contract

| Subject | Means | On resume |
|---|---|---|
| `[#N] chunk <k>/<total>: <summary>` | The chunk passed `architect` **and** `rationale-reviewer` | Landed — do not redo |
| `[#N] fix: <summary>` | A fix cycle after a review verdict | Landed — do not redo |
| `[#N] rebase fix: <summary>` | A post-rebase fix that passed its validators and re-greened the suite | Landed — do not redo |
| `[#N] WIP blocked: chunk <k>/<total> interrupted: <…>` | Committed only because an escape fired mid-chunk | **Re-run chunk `<k>` — only when this commit is HEAD** (`wip: yes`). A later `[#N] chunk <k>/<total>:` supersedes it: that chunk was re-run and reviewed, and is landed |
| `[#N] WIP blocked: sync interrupted: <…>` | An escape fired inside `/solve`'s Sync step, after the rebase | `wip: yes`, but there is no chunk to re-run: it is **unreviewed input** to the resumed Sync's re-verify fix round (Step 6b, step 5) |
| `[#N]: <summary>` (on `demo`) | The squashed ship commit | — |

Without the WIP prefix a resuming run cannot tell reviewed work from work merely
saved so it would not be lost, and would ship the latter unreviewed. A `wip`
summary **must** name its chunk (outside the loop: `final gate interrupted: …`;
in the Sync step: `sync interrupted: …`)
— the subject is all the resuming run gets.

## Branch selection (`/solve` Step 2)

All three entries share one procedure, not just the blocked one.

1. **`blocked: yes` or `resume: yes`** → `start <N> --resume`: fetches the remote,
   checks out `issue-<N>` (local, else from the remote), lists what already landed,
   prints `wip: yes|no`. That listing — not the comment log — says which chunks
   are done. `wip: yes` → the HEAD subject names the interrupted chunk; re-run it.
2. **Fresh claim** → `start <N>`. A pre-existing `issue-<N>` with no resume
   signal is a **conflict** the script refuses rather than overwrites: only a
   human can say whether it is abandoned work or a missed signal.
   **Unless the gate prints `builds-on: <sha>`** (#206) → `start <N> --adopt <sha>`:
   a human prepared the branch and the readiness stamp, or a later human comment,
   recorded `**Builds on:** issue-<N> @ <sha>`. The tip must equal `<sha>` exactly.
   A commit pushed after the record was never analysed, and `/solve`-authored
   subjects mean an interrupted run, not a base. Both are refused.
3. **Carve-out:** a block whose trigger was a `start` refusal was posted before
   any branch existed, so `blocked: yes` must not route to `--resume` — that
   refuses and re-blocks forever. When the blocker names a `start` refusal, pick
   the call from `branch.sh log <N>` (exits zero either way): `branch: none` →
   `start <N>`; a listed branch → `start <N> --adopt <sha>` when the gate prints
   `builds-on: <sha>`, else `start <N> --resume`.
4. **Invariant: no flow starts already on an `issue-*` branch.** `escape` and
   `ship` both end with `git checkout demo`, and every `start` refusal is
   checked before its checkout, so no path here parks the tree on a branch.
   A run that *dies* mid-flow still can, which is why `ship.md` §1 makes the
   unbranched flows verify `branch.sh where` before they commit.

## `start` Refusals

Every one of these is a **block**, not a chat report — see
[branch-exits.md](branch-exits.md), Escape routine.

| Situation | Action |
|---|---|
| Working tree dirty | Refused, never stashed. The edits are someone else's (or a crashed run's) and must not cross a checkout; a human clears them |
| Fresh claim but `issue-<N>` already exists | Refused. A human decides: record a Builds-on line (adopt), resume it, or delete it |
| `--adopt`: a tip ≠ the recorded sha, the sha is unknown, or the branch is missing | Refused. A human reconciles the branch and re-records the line |
| `--adopt`: the branch holds `/solve`-authored commits | Refused: an interrupted run. A human posts `**Builds on:** none` (next run resumes) or deletes it |
| `--resume` but the branch exists nowhere | Refused. The issue's signal and git disagree — unless the blocker names a `start` refusal, which carve-out 3 above handles instead |
| Local `issue-<N>` and `happy-bank-demo/issue-<N>` have **diverged** | Refused, not warned: continuing would squash a branch whose published counterpart says something else. Being merely *ahead* is not this — the branch is pushed only by `escape`/`ship`/`publish`, so any commit since then legitimately puts it ahead; behind is fast-forwarded. A Sync rebase would diverge them, which is why every rebase is followed by `publish` and a post-rebase escape pushes with lease — never leave a rebased branch unpublished |
| `git fetch happy-bank-demo` fails | Refused. The branch base cannot be established, and guessing it is how a stale branch point gets published |

## Leaving the branch

Ship and escape — the two ways a run ends — are in
[branch-exits.md](branch-exits.md).

