# Leaving the Branch: Ship and Escape

The two ways a `/solve` run ends on its `issue-<N>` branch — shipped, or
blocked. The branch itself, its commit-subject contract and how a run picks it
up are in [branching.md](branching.md); the flow-agnostic closing sequence
every flow shares is in [ship.md](ship.md).

## Ship (`/solve` Step 7)

`branch.sh ship <N> <file>` runs, in this order:

0. **Sync guard**: after the fetch, `happy-bank-demo/demo` must be an ancestor of
   `issue-<N>` — i.e. `/solve`'s Sync step already rebased it and the suite
   passed on that exact base. Otherwise exit **3** (`not-synced`): `demo`
   moved again since Sync, so the flow re-enters Sync (counted against its
   re-sync cap) rather than blocking. This is what makes the squash below ship
   the tested combination, not merely a conflict-free one.
1. Push `issue-<N>` to the remote — **before** the squash, and the branch is
   **never deleted**. A squash leaves the branch's own commits off `demo`'s
   ancestry, so this push is the only thing making "the `issue-<N>` branch will
   remain in the git history" (issue #148's own words) actually true.
2. `git checkout demo`, then `git merge-base --is-ancestor demo happy-bank-demo/demo`.
   False → **refuse**, printing the branch line and the diverging commits,
   branch left pushed and intact. Automatic recovery is forbidden for the same
   reason as in [ship.md](ship.md): an unattended run must not rewrite history.
3. `git merge --ff-only happy-bank-demo/demo` — **required, not cosmetic**: `issue-<N>`
   was cut from `happy-bank-demo/demo`, so squashing onto a *behind* `demo` would fold
   `happy-bank-demo/demo`'s intervening commits into this issue's commit, and be rejected
   as non-fast-forward anyway. Step 2 just proved it can only fast-forward.
4. `git merge --squash issue-<N>`. A conflict → reset and **refuse**: nothing
   committed, `demo` untouched, branch intact. A conflicted index left behind
   would make the next run's clean-tree guard refuse everything, silently.
5. One commit from `ship.md`'s message template, then `git push`.

**`--ff-only` and `--squash` are the only permitted merge forms in this repo**,
and only from inside `branch.sh` — `ship`'s two above, plus `start --resume`
fast-forwarding the issue branch to the remote. Neither can record a merge commit,
so both serve the linear history `ship.md` requires. Every other `merge` form,
and plain `git pull`, stay forbidden.

## Escape routine

On any blocking trigger, mid-chunk included:

0. **Inside the Sync step only:** a rebase still in progress → `branch.sh
   rebase-abort <N>` first (the branch returns to its pre-rebase, already
   published state). A *finished* rebase is kept: `escape` pushes it with
   lease, so the remote never holds a branch the resume would see as diverged.
1. `branch.sh wip <N> <file>` — commit whatever exists, tagged `WIP blocked`,
   the summary naming the interrupted chunk.
2. `branch.sh escape <N>` — push `issue-<N>`, return to `demo`. It prints the
   `**Branch:** …` line the blocker body must carry, so the human has something
   concrete to inspect (and it says truthfully if the push failed).
3. `issue.sh block <N> implementation <file> <target-stage>` and stop.

A **`start` refusal** blocks with no branch at all: skip steps 1–2 and no
`**Branch:**` line — and say in the body that a `start` refusal fired, so the
next run takes the selection carve-out instead of looping.

Nothing uncommitted → skip step 1; `wip` refuses an empty commit and `escape`
refuses a dirty tree, so a misjudged skip is caught, not carried onto `demo`.
A **ship-time refusal** (divergence or squash conflict) is the exception: the
work is committed and the branch pushed, so skip steps 1–2 and copy the
`**Branch:** …` line `ship` printed. A resumed run re-enters at Step 7 —
everything is reviewed and landed; nothing is re-implemented.

## Error Handling

| Situation | Action |
|---|---|
| Working tree dirty at `ship` | Refused, never stashed. An outstanding final-gate or doc-closure edit: commit it with `fix <N> <file>` and retry |
| Working tree dirty at `escape` | Refused. Run `wip <N> <file>` first — that is escape step 1 |
| `ship` exits 3 (`not-synced`) | `demo` moved after Sync. Re-enter `/solve`'s Sync step; a block only once its re-sync cap is hit |
| Squash conflicts at `ship` | Unreachable after a passing Sync guard; kept as a defensive net. Reset, `demo` untouched, branch intact. The refusal names the conflicting files, since the blocker it produces is all the human gets. A block trigger, not a retry |
| Local `demo` diverged from `happy-bank-demo/demo` at `ship` | Refused. Branch stays pushed and intact; never auto-rebase, reset, or force |
| Branch push fails at `ship` or `escape` | Warn and continue — the work is committed locally, and blocking on it would strand the issue. The printed branch line says `NOT pushed` truthfully |
| `demo` push fails at `ship` | Exit zero, print `NOT pushed`, so the flow still reaches its completion comment and close; `ship.md` §2 owns the rest |
| Nothing staged at a commit call | Refused — the step that should have produced changes did not |

`start`'s own refusals are in [branching.md](branching.md).
