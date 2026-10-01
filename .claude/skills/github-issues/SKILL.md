---
name: github-issues
description: 'Create, update, search, and comment on GitHub issues. Triggers when users want to file a bug, request a feature, create a task issue, change issue state, add labels or assignees, or add a comment to an existing issue in a GitHub repository.'
---

# GitHub Issues

Covers issue **content**: which template to use, how to word it, which labels to pick, and how to get the text to GitHub uncorrupted. The stage machine that governs *when* an issue may move and who may move it belongs to the `issue-lifecycle` skill.

## 1. Resolve Tooling

Every **write** goes through `issue.sh` = `.claude/skills/issue-lifecycle/scripts/issue.sh`. It is the single writer: it stamps the `🤖` AI-author marker, applies `stage:fresh` to new issues, emits registered comment headings, and verifies the round trip. Never hand-roll a `gh` write — a hand-rolled one is unmarked and unverified.

**Reads** use `gh` directly; they emit no text, so they need no marker.

Verify tooling with `gh --version`. If unavailable, fail with:
> "Cannot manage GitHub issues: the `gh` CLI is not available. Install it from https://cli.github.com."

| Operation | Command |
|-----------|---------|
| Create issue | `issue.sh create "<title>" <scratchpad>/issue_body.md [--label …] [--parent N]` |
| Replace issue body | `issue.sh set-body <number> <scratchpad>/issue_body.md` |
| Add comment | `issue.sh comment <number> <key> <scratchpad>/issue_comment.md [suffix]` |
| Change title/labels only | `gh issue edit <number> --title "…" --add-label "…"` |
| Close issue | `issue.sh close <number>` |
| Fetch issue (full log) | `issue.sh brief <number>` |
| Fetch issue (fields) | `gh issue view <number> --json title,body,labels,state` |
| Search issues | `gh issue list --search "<query>" --json number,title,state` |
| List issues | `gh issue list --json number,title,state,labels` |
| List labels | `gh label list --json name,description,color` |

Comment `<key>` is a key from the registry (e.g. `exploration`, `refinement`) — see [comment-formats.md](../issue-lifecycle/references/comment-formats.md) for the registry. Title and label arguments stay inline: they are plain text, not markdown. If a title must contain a backtick, `$` or `!`, wrap it in single quotes or drop the character.

## 2. Body-File Rule (mandatory)

**No markdown body may travel as an inline shell argument.** Not for create, not for edit, not for comments, not for "just one short line".

Why: the shell interprets backticks and `$` inside the argument, so any markdown body invites defensive escaping, and those escapes land in the posted text as literal `` \` `` — corrupting the issue permanently.

Procedure for every write:
1. Write the body to a file in the **session scratchpad directory** — `<scratchpad>/issue_body.md` for issue bodies, `<scratchpad>/issue_comment.md` for comments — using the **file-editing tool**. Never `echo`, `cat`, or a heredoc: those are shell again and reintroduce the same corruption. If no scratchpad directory is available, write to `.tmp/` in the repo instead — never fall back to an inline body.
2. The file carries **content only** — see the `issue-lifecycle` skill's **Body files** rule.
3. Pass the file path to `issue.sh`, substituting for `<scratchpad>` the real absolute scratchpad path given in your system prompt. The scratchpad is session-isolated and lives outside the working tree, so nothing written there can be committed by accident.

## 3. Determine Action

Identify whether the request is: **create**, **update**, **comment**, **search**, or **list**.
If the intent is ambiguous or matches more than one action, stop and ask the user to clarify.

## 4. Read Existing Labels

Fetch the repository's label list before any create or update operation. Use this to select existing labels. Consult [references/labels.md](references/labels.md) for synonym mapping and creation rules.

`issue.sh create` adds `stage:fresh` for you — never pass it yourself. Never add `approved`; that label is the human's alone. Add `ai` when the issue is about AI assets (skills, agents, commands, prompts) rather than product code.

## 5. Select Template

Map the request to a template from [references/templates.md](references/templates.md):

| User intent | Template |
|-------------|----------|
| Bug, error, broken, crash, not working | Bug Report |
| Feature, enhancement, add, improve, new | Feature Request |
| Task, chore, refactor, update, track | Task |
| Single short request | Minimal |

If the request matches more than one template or is unclear, stop and ask the user which type they intend.

## 6. Structure the Issue

- **Title**: Use a `[Type]` prefix when appropriate; keep under 72 characters; be specific and actionable.
- **Body**: Fill the chosen template into the scratchpad file from Step 2. Do not leave placeholder text — ask the user for any missing sections that cannot be inferred.

## 7. Execute

Run the `issue.sh` command for the action. For **update** operations, fetch the current issue first (`issue.sh brief <number>`), then apply only the changed fields — `set-body` replaces the whole body, so it must carry the parts you are keeping.

`issue.sh` re-reads the posted text and compares it to the file you sent. A `round-trip check FAILED` message means the text was corrupted or truncated in transit: correct the scratchpad file and re-post. Never work around it with an inline body.

## 8. Confirm

Report the issue URL to the user.

---

## Error Handling

| Situation | Action |
|-----------|--------|
| `gh` CLI unavailable | Fail with explicit error message (Step 1) |
| `gh` not authenticated | Fail with: "`gh` is not authenticated. Run `gh auth login`." |
| No git remote found | Fail with explicit error message (Step 7) |
| Multiple remotes, none specified | Stop and ask user to choose (Step 7) |
| Ambiguous action | Stop and ask user to clarify (Step 3) |
| Required label missing in repo | Create label, inform user of name (Step 4) |
| Template selection ambiguous | Stop and ask user which type (Step 5) |
| Body section cannot be inferred | Ask user rather than leaving placeholder (Step 6) |
| Update without pre-fetch | Always fetch current issue before updating to avoid silently clearing fields (Step 7) |
| `round-trip check FAILED` | Correct the scratchpad file and re-post; never fall back to a hand-rolled `gh` write |
| `comment body was only a heading with no content` | The file had nothing but a leading heading; a leading heading alone is stripped automatically, but real content must still be added (Step 1) |
| `bad heading key` | Use a key from the registry; do not invent stages |
| Body file cannot be written (no scratchpad **and** no `.tmp/`, or no file-editing tool) | Stop and report — do **not** substitute an inline body or a shell heredoc |
