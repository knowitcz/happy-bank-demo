# Ship Mechanics

The shared closing contract for any flow that lands work on an issue — `/solve` Step 7, and `/process-ai`'s implementation phase (adapted there for an asset change).

Fixed order: **commit → push → completion comment → close**. Only the orchestrator runs these commands; no subagent commits, pushes, or comments.

`<scratchpad>` = the absolute session scratchpad path given in your system prompt. It lives outside the working tree, so nothing written there can be committed by accident. If no scratchpad is available, use `.tmp/` in the repo.

## 1. Commit

0. **Unbranched flows only — confirm you are on `demo` first**: `scripts/branch.sh where` (or `git branch --show-current`). Anything else → **stop and report the branch**; do not commit. Since `/solve` gained its `issue-<N>` branch, a working tree can be parked on one — a `/solve` run that died mid-flow, or one whose `branch.sh start --resume` refused. Committing an unrelated flow's change there would push it to `happy-bank-demo/issue-<N>`, report `Pushed:` and close the issue while `demo` never receives it, and later fold it into that issue's squash commit. A branched flow skips this: `branch.sh ship` handles its own checkout.
1. Write the commit message to `<scratchpad>/commit_msg.md` with the **file-editing tool** — never `echo`, `cat`, or a heredoc, for the reason given in the `github-issues` skill, **Body-File Rule**.
   - First line: `[#N]: <what was implemented>`
   - Body: test results and documentation updates
2. `git commit -F <scratchpad>/commit_msg.md`. **Never `-m`** — the shell interprets backticks and `$` in an inline message and corrupts it.
3. Capture the commit SHA for the completion comment: `git rev-parse --short HEAD`.

**If the flow branched**, steps 1–3 and the push below are one call instead: `scripts/branch.sh ship <N> <scratchpad>/commit_msg.md`, which squash-merges the issue branch onto `demo` and prints the push status line for §3. **Write the summary alone on the first line — no `[#N]: ` prefix**: `branch.sh` composes every subject prefix itself, so typing one here lands `[#N]: [#N]: …` on the commit `demo` keeps forever. The `[#N]: ` form above is for the unbranched path only. Only `/solve` branches — see [branching.md](branching.md); `/process-ai` and `/discover-debt` commit straight to `demo` and run this step as written.

## 2. Push

Run `git push happy-bank-demo demo` (local `demo` tracks a different remote, so never a bare `git push`).

**`--force` and `--force-with-lease` are forbidden on `demo`.** This step runs unattended: a forced push rewrites published history and can destroy commits other people already pushed. If `demo`'s history genuinely must be rewritten, a human does it outside this flow.

**One carve-out, `issue-<N>` branches only:** `/solve`'s Sync step rebases its branch onto `happy-bank-demo/demo` before ship, and `branch.sh` then publishes it with `--force-with-lease` (`publish`, and `escape`/`ship` after a rebase). `demo` is protected and issue branches are expected to be rebased (#196), so rewriting one destroys nothing anyone else builds on; the lease still refuses a push someone made since the last fetch. An inline forced push stays forbidden everywhere.

Automatic recovery of a failed `demo` push is forbidden: do **not** retry, and do **not** run `git pull`, `git rebase`, or `git merge` yourself. The Sync rebase is not recovery — it runs *before* ship, on the issue branch, and never touches `demo`.

### If the push fails (non-zero exit)

The work is committed and safe locally; only publication failed (typically newer commits on the remote). Do not block, do not stop, do not fix it:

1. Report the failure and its reason (the `git push` stderr) to the user.
2. Record the unpushed state in the completion comment (section 3) — the issue artifact must carry it, not just terminal scrollback.
3. Continue to the completion comment and the close. A failed push does not make the issue unfinished.

**Human recovery** — quote it in the report and in the comment; never execute it here:

```
git pull --rebase happy-bank-demo demo && git push happy-bank-demo demo
```

This repo is **rebase-only**: one continuous line of commits, never a merge commit. Plain `git pull` and `git merge` are therefore forbidden in this repo — both can produce a merge commit.

**One carve-out:** `git merge --ff-only <ref>` and `git merge --squash <branch>` are permitted, and only from inside `branch.sh` — at three sites (Sync's `rebase` is a rebase, not a merge, and rewrites only the issue branch): `ship` fast-forwards `demo` to `happy-bank-demo/demo` and then squashes the issue branch onto it, and `start --resume` fast-forwards the issue branch to `happy-bank-demo/<branch>`. Neither form can record a merge commit — `--ff-only` refuses rather than merging, `--squash` stages without committing one — so both serve the linear history this rule protects rather than breaking it. The ban stands for every other `merge` form and for plain `git pull`.

## 3. Completion Comment

Post with `issue.sh comment <N> implementation <scratchpad>/issue_comment.md` (body written to the file per the Body-File Rule). Content only, per the `issue-lifecycle` **Body files** rule — write to the template below directly:

```markdown
**Summary:** <what was implemented, test results, documentation updates>
**Plan adherence:** <one line per chunk: `as planned` / `diverged` — reason>
**Risk outcomes:** <one line per refinement risk: `held` / `materialized` / `never triggered` — evidence, e.g. which check or test confirms it>
**New risks:** <from the final-gate verifiers' `New risks observed` lines, or "none">
**Push status:** <exactly one line: `Pushed: <sha>` or `NOT pushed: <reason> — recover with: git pull --rebase happy-bank-demo demo && git push happy-bank-demo demo`>
```

- Fix cycles, decomposition sub-chunks, scope changes, and extra review rounds all count as divergence for **Plan adherence** — report them factually, they are data, not failures.
- Actionable **New risks** → also spawn `product-owner` to create the follow-up issue; the rest are recorded here only.

In Trivial Mode the plan-adherence and risk sections are omitted (there is no refinement plan).

## 4. Close

`issue.sh close <N>` — strips the stage label. A closed issue with no `stage:*` label **is** the finished state; there is no `stage:finished`. Close even when the push failed: the unpushed SHA is recorded in the comment above.

## Error Handling

| Situation | Action |
|-----------|--------|
| `git push` exits non-zero | Report; record `NOT pushed` + reason + recovery command in the comment; continue to close. Never force-push, never auto-rebase |
| `git commit` exits non-zero (nothing staged, hook failure) | Stop before pushing; report the output — an empty or rejected commit means Step 6 did not actually produce the change |
| §1 step 0: an unbranched flow finds itself on an `issue-*` branch | Stop and report which branch, before committing. A parked branch belongs to another issue's interrupted `/solve`; landing this change there hides it from `demo` and mislabels it as that issue's work. A human returns the tree to `demo` |
| Tempted to fix a rejected push | Forbidden. The human runs `git pull --rebase happy-bank-demo demo && git push happy-bank-demo demo`; `git pull` without `--rebase` and every `git merge` form except `--ff-only`/`--squash` are forbidden in this repo |
| `branch.sh ship` refuses (not synced, diverged `demo`, squash conflict, or dirty tree) | Not a push failure — the squash never happened and `demo` is untouched. Not synced (exit 3) → back to `/solve`'s Sync step, never a block. A dirty tree means an uncommitted Step 5/6 change: commit it and retry. The other two are block triggers; see [branch-exits.md](branch-exits.md) |
| No scratchpad directory available | Write `commit_msg.md` under `.tmp/` in the repo; never fall back to `git commit -m` |
