---
name: workspace-branch
description: Use when setting up workspace and branch context, switching workspaces or branches, creating or deleting branches, reviewing branch history, or creating a pull request for a working branch. This skill should be used when the user asks to "list workspaces", "switch workspace", "create a branch", "delete a branch", "switch branch", "show branch history", "create a PR", or "open a pull request" in Honeydew.
---

# Workspace & Branch Management

All Honeydew MCP tool calls operate against a workspace and branch set for the current session. Use this skill to set up that context, manage branches, and create pull requests when development work is ready for review.

---

## Session Setup (Required Before Any Work)

**Step 1: Check existing context**

Call `get_session_workspace_and_branch` first. If a workspace and branch are already set, skip to Step 3.

**Step 2: Select workspace and branch**

```
list_workspaces → pick a workspace → set_session_workspace_and_branch
```

If the user needs a specific branch, call `list_workspace_branches` first to see available options.

**Step 3: For development work, create a branch**

```
create_workspace_branch → session switches automatically
```

Never make modeling changes on the `prod` branch directly. Always create a development branch first.

---

## MCP Tools Reference

### Read-Only Tools

- `list_workspaces` — List all available workspaces. Returns the workspace name and data warehouse type (`snowflake`, `databricks`, or `bigquery`). Use the warehouse type to inform SQL dialect choices.
- `list_workspace_branches` — List all branches available for a workspace. Requires `workspace_id`.
- `get_session_workspace_and_branch` — Get the workspace and branch set for the current session.
- `get_branch_history` — Get the change history for the current session's branch. Returns a chronological list of what semantic objects were modified, by whom, and when. Optional `limit` parameter (default: 50).

### Write Tools

- `set_session_workspace_and_branch` — Set the workspace and branch for the current session. All subsequent tool calls use this context. Requires `workspace_id`; `branch_id` is optional (defaults to `prod`).
- `create_workspace_branch` — Create a new branch from the current state of the workspace's `prod` branch. The session automatically switches to the new branch. Requires `workspace_id` and `branch_name`.
- `delete_workspace_branch` — Delete a branch from a workspace. **Destructive and irreversible.** Always confirm the workspace name and branch name with the user before calling. The `prod` branch cannot be deleted. If the deleted branch is the current session branch, the session switches to `prod` automatically. Requires `workspace_id` and `branch_name`.
- `create_pr_for_working_branch` — Create a pull request for the current session's working branch. Returns the PR URL on success. Requires `title`; optional `description`.

---

## Typical Workflows

### Starting a session

```
get_session_workspace_and_branch
  → already set? → continue with current context
  → not set?     → list_workspaces → set_session_workspace_and_branch
```

### Starting development work

```
get_session_workspace_and_branch (confirm you're on the right workspace)
create_workspace_branch (workspace_id, branch_name)
  → session switches to new branch automatically
  → make modeling changes
```

### Reviewing work done on a branch

```
get_branch_history
  → inspect what changed, who changed it, and when
```

### Finishing development and opening a PR

```
create_pr_for_working_branch (title, description)
  → display the returned PR URL to the user
```

### Cleaning up a branch

```
list_workspace_branches (confirm the branch name)
  → confirm with user before proceeding
delete_workspace_branch (workspace_id, branch_name)
```

---

## Rules

- **Always confirm** before calling `delete_workspace_branch` — it is irreversible.
- **Never modify `prod` directly.** Always create a development branch for modeling changes.
- `create_workspace_branch` always creates from the current `prod` state, not from another branch.
- If the deleted branch is the session branch, the session reverts to `prod` automatically — remind the user to switch if needed.
- After `create_pr_for_working_branch`, always display the returned PR URL.
