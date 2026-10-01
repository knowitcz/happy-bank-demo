---
name: 'report-difficulty'
description: 'Turn an observed difficulty (missing tool, incomplete task, unclear instructions, contradictory rule) into either a comment (one-time — the fix just applied durably closed it) or a tracked, deduplicated `ai`-labeled GitHub issue (recurring — the gap can still hit someone else): classify first, then for recurring ones search open then closed `ai` issues for a match, comment "observed again" on a hit, otherwise file a new issue referencing the causing context. Triggers whenever CLAUDE.md''s "report a difficulty" rule fires, or any flow/agent notices a gap in a skill/agent/command/rule. DO NOT USE FOR: a normal product bug/feature (use github-issues), batch tech-debt discovery (use the `/discover-debt` command), or actually changing the asset (use ai-assets-designer).'
---

# Report Difficulty – Difficulty Triage Protocol

Turns an observed process/tooling difficulty into either an in-session note or a tracked, deduplicated GitHub issue labeled `ai`, so recurring gaps stop leaking into chat-only prose while one-time ones don't clutter the tracker. Consumed by any flow or agent that hits a difficulty mid-run.

## When to Use

Use this skill when:
- A missing tool, incomplete task, unclear instruction, or contradictory rule is observed during any flow (`/refine`, `/solve`, `/discover-debt`, an interactive session, code review)
- `CLAUDE.md`'s "you MUST report a difficulty" rule fires — enter for **every** difficulty; the one-time/recurring call is made inside this skill (Step 2), never pre-filtered by the caller before invoking it
- You need to check whether a difficulty you just hit was already reported, before filing a duplicate

## Flow

Throughout, `issue.sh` = `.claude/skills/issue-lifecycle/scripts/issue.sh` (see the `issue-lifecycle` skill — never hand-roll a `gh` write).

### 1. Frame the Symptom

Write one title (≤80 chars) and a 2–4 sentence body to a scratchpad file (content only, per the `issue-lifecycle` **Body files** rule): what was observed, where (file/skill/agent), and the causing context (issue number, PR, or session task) that surfaced it. This becomes the issue or comment body.

### 2. Classify — One-Time or Recurring?

Ask one question: **can another session hit this same difficulty again here, unchanged by what was just done?**
- Yes, or unsure → **Step 3b** (recurring). Default to this on any ambiguity — a wrongly-filed issue is cheap to close, a wrongly-suppressed one is invisible.
- No — the fix just applied durably closed the root cause itself (an idempotent bootstrap, a missing piece of state/config now permanently established), or the cause was transient/external with no asset-side gap → **Step 3a** (one-time).

Worked example (the case that motivated this step): `issue.sh ai-start` failed because the `ai-in-progress` label didn't exist yet; running the idempotent `issue.sh init-labels` fixed it for good — no future session can hit that same failure in this repo again. One-time.

### 3a. Comment-Only (One-Time)

Always tell the human in-session — this step never replaces that, regardless of what else it does.

If the caller is mid-flow on a GitHub issue (the one being refined/solved/processed) and knows its number:

`issue.sh comment <processed-N> difficulty <file>` — body: what was observed and why the fix just applied closes it for good. The `difficulty` key (see `issue-lifecycle`'s registry) is dedicated and never a phase key, so it can't be mistaken by anything scanning for phase headings (e.g. `process-ai`'s resume logic).

No processed issue in scope → in-session mention only, no GitHub write. Either way, stop here — do not search or file. Return to caller: `"one-time — <commented on #N | in-session only>"`.

### 3b. Search Open `ai` Issues

`gh issue list --search "<keywords>" --label ai --state open --json number,title,url`. Judge similarity by symptom, not exact wording — a close match is a duplicate even under a different title.

Match found → **Step 5a**.

### 4. Search Closed `ai` Issues

No open match → repeat with `--state closed`. A close match here means this was already addressed once and may have resurfaced. Note its number for Step 5b's body — file fresh rather than reopening, since the closed decision may no longer be current.

### 5a. Comment on the Existing Open Match

`issue.sh comment <N> observed <file>` with the body: "Observed again — <causing context>." The `observed` key is never a phase key, for the same reason as `difficulty` in Step 3a. Return that issue's number/URL to your caller. Stop; do not file a new issue.

### 5b. File a New Issue

No open match → `issue.sh create "<title>" <file> --label ai`. Body must include the causing context and, if Step 4 found one, a link to the related closed issue. Return the new issue's number/URL to your caller.

### 6. Report Back

Whatever invoked you still owns telling the human — hand back `#<N> (new|existing): <url>` from Step 5a/5b so it can be folded into that report, per `CLAUDE.md`'s "report a difficulty" rule. This skill files the issue; it never replaces telling the human in-session. (Step 3a already returned its own result and does not reach this step.)

## Error Handling

| Situation | Action |
|---|---|
| Classification is genuinely ambiguous | Default to recurring; file per Step 5b — cheap to close, unlike an invisible suppression |
| Step 3a's in-scope comment write fails | Fall back to in-session mention only; never escalate to filing |
| Search returns nothing in either state | File fresh per Step 5b, no related-issue link |
| `gh` CLI unavailable or unauthenticated | Follow `github-issues` skill error handling; report to caller |
| Ambiguous match (plausible but not clearly the same symptom) | Treat as no match; file fresh rather than mis-attaching to an unrelated issue |
| Caller cannot describe a causing context | Refuse to file — an issue with no causing context is unactionable; ask the caller to supply one |
