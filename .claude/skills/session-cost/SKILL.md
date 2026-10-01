---
name: 'session-cost'
description: 'Estimated per-session token and dollar cost, posted automatically onto the GitHub issue a session worked. Covers the SessionEnd hook and the catch-up sweep, how a session is attributed to an issue, the 5-bucket token pricing model, the rates.json upkeep duty, and the degrade-never-fail contract. Triggers on "what did this issue cost", "why is there no cost comment", "the cost figure looks wrong", "update the token rates", "register the cost sweep". DO NOT USE FOR: changing issue stages or posting phase comments (see issue-lifecycle), or estimating a change up front (that is the architect/tester LOC estimate during /refine).'
---

# Session Cost – Per-Issue Spend Recording

Records what a session actually cost onto the issue it worked, so spend becomes reviewable, comparable across issues, and usable as feedback for future complexity estimates. Consumed by humans reading an issue and by anyone maintaining the rate table; no flow calls it — it fires on its own.

## When to Use

Use this skill when:
- A `### 💰 Cost` comment is missing, duplicated, or reports a figure that looks wrong
- The rate table needs refreshing, or a cost comment reports `degraded: rates_stale_*`
- Registering (or removing) the catch-up sweep on a machine
- Deciding whether some new spend source belongs in the total

## Why It Is Not Wired Into `/solve` and `/refine`

#83 proposed folding a cost line into `/solve`'s completion comment and `/refine`'s readiness stamp. It is deliberately **not** built that way. Recording cost is orthogonal to shipping work: coupled into those templates it would only ever cover the flows that were edited, would miss any run that died before its final comment, and would make two commands carry a concern neither is about. Fully decoupled, one mechanism covers every session — including `/process-ai`, ad-hoc sessions, and crashed ones.

## Triggers

| Trigger | Mechanism | Covers |
|---|---|---|
| Session ends | `SessionEnd` hook in `.claude/settings.json` — every reason **except `resume`** | The normal case, posted within seconds |
| Session was killed, crashed, or overran the hook budget | `scripts/cost.py --sweep`, run from cron/launchd | Everything the hook never finished |

`resume` is excluded because `SessionEnd` fires with that reason *before* the session carries on under the same id — costing it there would report a partial total and burn the one-shot marker. `cost.py` re-checks the reason itself, so a matcher-less registration is still safe.

SessionEnd hooks are hard-capped at 60s wall clock, so the hook may be killed mid-post on a slow network. That is not a lost record: the `.done` marker is written only after a successful post, so the sweep — under no such cap — picks it up.

Both triggers are the same file, so they cannot drift. Only the OS-level scheduler registration is external — it is per-machine, so the repo cannot own it. Register it once per machine (also listed in `README.md` setup):

```
*/30 * * * * python3 <repo>/.claude/skills/session-cost/scripts/cost.py --sweep
```

Without it, killed sessions record nothing and nothing complains. The first sweep on a machine posts **nothing** — it only writes its watermark, since the initial run would otherwise mass-comment every session in the transcript history. State (`<session>.done` markers, the watermark) lives in `~/.claude/session-cost/`.

The hook is on by default for every contributor, since `.claude/settings.json` is tracked. That was a deliberate choice over an opt-in gate (see [#83](https://github.com/knowitcz/tooling-hub/issues/83)): a cost record only has value if it exists for every run, and a per-contributor opt-in would leave the history patchy. It does mean every contributor's sessions post to GitHub automatically — remove the `SessionEnd` block to stop that.

## Attribution — A Claim, Never A Mention

A session is attributed to the issue it **claimed**, not one it mentioned. `/solve` sessions routinely reference a parent issue's number in prose and in `gh` reads without working it, so matching `#<N>` over-attributes. The three claim points:

| Command in the transcript | Flow |
|---|---|
| `issue.sh set-stage <N> in-refinement` | `/refine` |
| `issue.sh set-stage <N> in-implementation` | `/solve` |
| `issue.sh ai-start <N>` | `/process-ai` |

`attributionSkill` is **not** used as the filter, and neither is a bare `#N` mention. Once the issue is known, the **whole session** is summed — not just post-claim turns.

**A decomposition run costs wholly to the parent.** That is not special-cased: `/refine` Step 8b stamps children `refined` or `fresh`, neither of which is a claim point, so children never register. A future Step 8b that ever stamped a child `in-refinement` mid-parent-run would silently split the parent's total at that boundary — change this table if that happens.

A session that claims two genuinely different issues falls back to splitting at claim boundaries.

> Measurements behind these choices, and the alternatives rejected, are in [docs/ai/session-cost.md](../../../docs/ai/session-cost.md) § Key Design Decisions.

## What Is Counted

The main transcript **plus every subagent transcript** under `<session-dir>/subagents/`. Omitting subagents would report a fraction of a `/solve` run, where the specialists do most of the work. Scoping to one session (rather than sweeping the shared project directory by time) is what keeps a concurrent session on a different issue out of the total.

Usage is deduplicated by `message.id` before summation — one assistant response spanning several content blocks repeats its `usage` on every line, so a naive sum roughly doubles the total.

## Pricing — Five Buckets

`input`, `output`, `cache_write_1h`, `cache_write_5m`, `cache_read`, priced per model from `scripts/rates.json`. Cache writes split by TTL because a 1h write costs 2x base input and a 5m write 1.25x, while a cache read costs 0.1x — a flat token sum would be wrong by an order of magnitude in either direction.

Not modelled: the 1.1x `inference_geo: "us"` data-residency multiplier. Observed transcripts report `inference_geo: "not_available"`, so applying it would be guesswork; a US-pinned org's figures read ~10% low.

**Upkeep duty.** `rates.json` is transcribed by hand from Anthropic's published prices; nothing in the repo verifies it. It carries `as_of` and `staleness_days: 90`. Past that window, and for any model absent from the table, the comment reports token counts and omits the dollar figure rather than quoting a stale or guessed one. A `degraded` value in a posted comment is the signal to refresh the table and bump `as_of`.

## Output Contract

One comment per session per issue, appended (never edited in place — `issue.sh` has no edit primitive, and per-session records make refine-vs-solve cost directly comparable). Posted **only** via `issue.sh cost <N> <file> <session-id>`, which stamps the `<!-- issue-lifecycle:cost:<session-id> -->` idempotency marker itself; `issue.sh comment` refuses the `cost` key outright, since it would post the heading with no marker. The body is a one-line human summary plus a JSON block with a fixed schema — prose would not be aggregatable, and comparing cost across issues is the whole point.

Cost comments are **excluded from `issue.sh brief`**, so a recorded run never inflates the context of the next flow that reads the issue. The `brief` header still says how many were omitted.

> See [issue-lifecycle/references/comment-formats.md](../issue-lifecycle/references/comment-formats.md) for the registry row and the marker rule.

## Degrade, Never Fail

The transcript format is undocumented and may change between Claude Code versions. Every failure path — unreadable payload, changed shape, missing rates, unknown model, `gh` failure — prints to stderr and exits 0. This runs inside session teardown: no cost comment is a nuisance, a broken teardown or a confidently wrong figure is a defect.

## Error Handling

| Situation | Action |
|-----------|--------|
| No cost comment appeared | Check the session claimed an issue at all (no claim → nothing to attribute, by design); then `--dry-run` against the transcript |
| Cost comment says `degraded: rates_stale_*` | Refresh `scripts/rates.json` from Anthropic's current prices, bump `as_of` |
| Cost comment says `degraded: unpriced_models:*` | A model was released after the table was written — add its row |
| The same session posted twice | `~/.claude/session-cost/` was wiped *and* the `gh` read guard failed; delete the duplicate by hand and report it |
| Figures look implausibly high | Check dedup: a format change to `message.id` would reintroduce double-counting |
| A flow wants to post its own cost line | Refuse — this key is this skill's alone, and a second writer breaks comparability |
