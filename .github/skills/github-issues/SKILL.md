---
name: github-issues
description: 'Create, update, search, and comment on GitHub issues. Triggers when users want to file a bug, request a feature, create a task issue, change issue state, add labels or assignees, or add a comment to an existing issue in a GitHub repository.'
---

# GitHub Issues

## 1. Resolve Tooling

Try MCP tools first (`mcp_gh-issues_*` and `mcp_gh-labels_*`). If they are unavailable, fall back to the `gh` CLI. If neither is available, fail with:
> "Cannot manage GitHub issues: neither the GitHub MCP server nor the `gh` CLI is available."

**Issue tools reference (`mcp_gh-issues_*`):**

| Tool | Method / Purpose |
|------|------------------|
| `mcp_gh-issues_issue_write` | `method="create"` — Create a new issue (title, body, labels, assignees, milestone, type) |
| `mcp_gh-issues_issue_write` | `method="update"` — Update an existing issue (pass `issue_number`; supports state, state_reason, duplicate_of) |
| `mcp_gh-issues_issue_read` | `method="get"` — Fetch issue details |
| `mcp_gh-issues_issue_read` | `method="get_comments"` — Fetch issue comments |
| `mcp_gh-issues_issue_read` | `method="get_sub_issues"` — Fetch sub-issues of an issue |
| `mcp_gh-issues_issue_read` | `method="get_labels"` — Fetch labels assigned to an issue |
| `mcp_gh-issues_search_issues` | Search issues (GitHub search syntax, scoped to `is:issue`) |
| `mcp_gh-issues_add_issue_comment` | Add a comment to an issue (or PR by number) |
| `mcp_gh-issues_list_issues` | List repository issues (filter by state, labels, date; paginate with cursor) |
| `mcp_gh-issues_list_issue_types` | List supported issue types for the owning organisation |
| `mcp_gh-issues_sub_issue_write` | `method="add"` / `"remove"` / `"reprioritize"` — Manage sub-issues |

**Label tools reference (`mcp_gh-labels_*`):**

| Tool | Method / Purpose |
|------|------------------|
| `mcp_gh-labels_list_label` | List all labels in the repository |
| `mcp_gh-labels_get_label` | Get a specific label by name |
| `mcp_gh-labels_label_write` | `method="create"` — Create a label (name, color as 6-char hex, optional description) |
| `mcp_gh-labels_label_write` | `method="update"` — Update a label (rename via `new_name`, change color/description) |
| `mcp_gh-labels_label_write` | `method="delete"` — Delete a label |

## 2. Resolve Repository

Determine the target repository using this priority order:

1. **User explicitly provides owner and repo in the prompt** → use those.
2. **Workspace/IDE context attachment provides repository info** → treat as unconfirmed. Display the detected `owner/repo` and ask the user to confirm before proceeding.
3. **Neither of the above** → run `git remote -v` and handle the result:
   - **No git / no remote** → fail with: "No GitHub repository found. Please specify owner and repo or add a git remote."
   - **Exactly one remote** → use it.
   - **Multiple remotes** → stop and ask the user to choose. List each remote with its name and URL.

**Confirmation gate (all paths):** Before executing any write operation (create, update, comment), state "Using repository: `owner/repo`" so the user can catch mistakes. For read-only operations (search, list, get) confirmation is not required.

## 3. Determine Action

Identify whether the request is: **create**, **update**, **comment**, **search**, or **list**.
If the intent is ambiguous or matches more than one action, stop and ask the user to clarify.

## 4. Read Existing Labels

Before any create or update operation, call `mcp_gh-labels_list_label` to fetch the repository's current labels. Match user intent to existing labels using the synonym table in [references/labels.md](references/labels.md).

- **Label exists** → use it directly in `labels` array of `mcp_gh-issues_issue_write`.
- **Label missing but matches a standard name** → create it with `mcp_gh-labels_label_write` (`method="create"`), inform the user of the name and colour, then use it.
- **No synonym match** → create a new descriptive label, report it to the user.

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
- **Body**: Fill the chosen template. Do not leave placeholder text — ask the user for any missing sections that cannot be inferred.

## 7. Execute

Call `mcp_gh-issues_issue_write` with the correct `method`, `owner`, `repo`, `title`, `body`, and resolved `labels`.
For **update** operations: fetch the current issue first (`mcp_gh-issues_issue_read` with `method="get"`), then apply only the changed fields to preserve existing data.

## 8. Confirm

Report the issue URL to the user.

---

## Error Handling

| Situation | Action |
|-----------|--------|
| MCP server unavailable | Fall back to `gh` CLI (Step 1) |
| `gh` CLI also unavailable | Fail with explicit error message (Step 1) |
| No git remote found | Fail with explicit error message (Step 2) |
| Multiple remotes, none specified | Stop and ask user to choose (Step 2) |
| Repo from workspace context, not user | Treat as unconfirmed; display and ask user to confirm before write operations (Step 2) |
| Ambiguous action | Stop and ask user to clarify (Step 3) |
| Required label missing in repo | Create label, inform user of name (Step 4) |
| Template selection ambiguous | Stop and ask user which type (Step 5) |
| Body section cannot be inferred | Ask user rather than leaving placeholder (Step 6) |
| Update without pre-fetch | Always fetch current issue before updating to avoid silently clearing fields (Step 7) |
