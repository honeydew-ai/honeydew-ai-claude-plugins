---
name: conversation-review
description: Use when a semantic/context layer curator wants to review past analysis conversations in bulk, categorize user feedback into actionable improvement areas, and apply targeted changes to the semantic model or context layer. Covers the full workflow from collecting conversations and classifying feedback through to creating action items and applying them on a branch.
---

## Overview

This skill is for **semantic and context layer curators** who want to use accumulated user feedback to drive continuous improvement. It structures the work into two phases:

1. **Categorize** — review past conversations with feedback and classify each piece of feedback into an actionable improvement category
2. **Act** — turn the categorized feedback into a concrete list of changes, then apply them to the semantic model or context layer on a branch

---

## Prerequisites

Before starting, ensure a workspace and branch are set. Use `get_session_workspace_and_branch` to check the current context. If nothing is set, use `list_workspaces` and `set_session_workspace_and_branch`. See the `workspace-branch` skill for the full reference.

You will be reading the model as-is (use `prod` branch for reading), then applying changes on a development branch later.

---

## Phase 1: Collect Conversations

### 1.1 Fetch conversations with feedback

Use `list_analysis_chats` to retrieve past conversations. Focus on those that have received feedback — positive or negative.

```
list_analysis_chats(limit=50, offset=0)
```

Paginate with `offset` until you have covered the desired time window or conversation count. For each conversation, note:

- `conversation_id`
- `title`
- `feedback` (the stored feedback text, if any)
- `agent` and `domain`
- `created_at` and `created_by`

**Filter to conversations with feedback.** Skip conversations with no feedback unless the user explicitly wants to review all conversations.

If a conversation has no feedback or the stored feedback is inaccurate, use `provide_analysis_feedback` to record the correct label before categorizing:

```
provide_analysis_feedback(conversation_id="abc123", feedback="Data Issue: net revenue metric missing")
provide_analysis_feedback(conversation_id="def456", feedback="Good")
```

This keeps the stored feedback in sync with the categorization, so future reviews start from an accurate baseline.

### 1.2 Read the full conversation when needed

If the feedback text alone is not enough to understand what went wrong, retrieve the full conversation content with `get_stored_conversation`:

```
get_stored_conversation(conversation_id="abc123")
```

This returns all final responses and plan/interpretation messages. Read these to understand what the AI actually did — what question it interpreted, what approach it took, and what it concluded.

To also see individual analysis steps (useful when you want to identify which step produced wrong data), pass `with_step_ids: true`:

```
get_stored_conversation(conversation_id="abc123", with_step_ids=true)
```

This includes `step_start` and `step_insight` entries with `step_id` values you can then pass to `get_analysis_step_details` to retrieve the exact semantic query and SQL used in that step.

---

## Phase 2: Categorize Feedback

For each conversation with feedback, assign it to one or more of the following **action categories**. A single conversation can yield multiple categories.

### Feedback → Action Category Mapping

| Feedback Signal | Root Cause | Action Category |
|---|---|---|
| `Data Issue: X metric doesn't exist` | Missing aggregation | **Add metric** |
| `Data Issue: wrong value / incorrect result` | Metric or attribute SQL is wrong | **Fix calculation** |
| `Data Issue: missing dimension / can't slice by X` | Missing attribute | **Add attribute** |
| `Wrong Judgement: used wrong field` | Ambiguous names or descriptions | **Improve metadata** |
| `Wrong Judgement: missed a standing rule` | Missing instruction | **Add instruction** |
| `Wrong Judgement: didn't follow a procedure` | Missing analytical skill | **Add skill** |
| `Wrong Judgement: lacked business context` | Missing knowledge or memory | **Add knowledge / memory** |
| `Wrong Judgement: wrong domain or agent` | Agent misconfigured | **Update agent** |
| `Chart Issue` | Visualization only | **No semantic action** |
| `Good` / positive | Working as intended | **No action** |
| `Other: X` | Ambiguous | **Manual review** |

### Categorization Output

Produce a table summarizing all categorized feedback before proceeding:

| Conversation | Feedback | Category | Proposed Change |
|---|---|---|---|
| `abc123` — "Revenue by region" | `Data Issue: net revenue metric missing` | Add metric | Add `net_revenue` to `orders` entity |
| `def456` — "Churn analysis" | `Wrong Judgement: used gross revenue` | Add instruction | "Always use `orders.net_revenue` for revenue questions" |
| `ghi789` — "Top products" | `Good` | No action | — |

Group the proposed changes by category to make patterns visible. If three conversations all flag the same missing metric, that is one action item, not three.

---

## Phase 3: Build Action Items

Turn the categorized feedback into a concrete, prioritized action list. Each action item should be self-contained enough to execute in a single MCP call.

### Action Item Format

For each item, record:

- **Type**: what kind of change (`add_metric`, `fix_attribute`, `add_instruction`, `add_skill`, `add_knowledge`, `add_memory`, `update_agent`, `improve_description`)
- **Target**: the entity, field, agent, or context item to create or update
- **Evidence**: the conversation IDs and feedback text that motivated this item
- **What to do**: a one-sentence description of the specific change

### Action Item Types and Tools

| Type | Tool(s) |
|---|---|
| Add metric | `create_object` with metric YAML |
| Add attribute | `create_object` with attribute YAML |
| Fix calculation | `get_field` to read current YAML → `update_object` with corrected SQL |
| Improve metadata | `get_entity` or `get_field` → `update_object` with improved `description` or `display_name` |
| Add instruction | `create_context_item` with `subtype: instruction` |
| Add skill | `create_context_item` with `subtype: skill` |
| Add knowledge | `create_context_item` with `subtype: knowledge` and `external_source` |
| Add memory | `create_context_item` with `subtype: event` |
| Update agent | `get_agent` → `update_agent` with corrected domain, context globs, or description |

### Prioritization

Present the action list sorted by **impact × frequency**:

1. Changes that would have fixed multiple conversations (high frequency)
2. Changes to core metrics or standing rules (high impact)
3. Minor metadata improvements and one-off additions

Review the list with the user before applying any changes. Ask: *"Would you like to proceed with all items, or select a subset?"*

---

## Phase 4: Apply Changes on a Branch

### 4.1 Choose a branch

Ask the user whether to apply changes on:

- **A new branch** — recommended for a significant batch of changes:
  ```
  create_workspace_branch(workspace_id="...", branch_name="conversation-review-<date>")
  ```
- **An existing development branch** — if work is already in progress:
  ```
  set_session_workspace_and_branch(workspace_id="...", branch_id="<branch>")
  ```

Never apply changes directly to `prod`.

### 4.2 Apply semantic layer changes

For each semantic layer action item, apply in this order to avoid dependency issues:

1. **New entities** (if any) — `create_entity`
2. **New attributes** — `create_object` with attribute YAML
3. **New metrics** — `create_object` with metric YAML
4. **Updated calculations or metadata** — `update_object`

After each `create_object` or `update_object`, display the returned `ui_url` to the user.

Refer to the **attribute-creation**, **metric-creation**, or **entity-creation** skills for the correct YAML structure.

### 4.3 Apply context layer changes

For each context layer action item:

1. Run `list_context_items` to check for existing items that overlap — update rather than duplicate.
2. Apply `create_context_item` or `update_context_item`.
3. Display the returned `ui_url` after each call.

Refer to the **context-item-creation** skill for naming conventions, folder structure, and type-specific parameters.

### 4.4 Validate

After all changes are applied, run validation on the affected objects. Use `validate_object` on any YAML you are unsure about before committing it. For a broader check, use the **validation** skill.

### 4.5 Review branch history and open a PR

Use `get_branch_history` to review what changed on the branch. Then:

```
create_pr_for_working_branch(
  title="Model improvements from conversation review — <date>",
  description="Changes derived from reviewing N conversations with feedback. Addresses: <list of categories>."
)
```

Display the returned PR URL to the user.

---

## Full Workflow Summary

```
set_session_workspace_and_branch (confirm prod for reading)
    │
    ▼
list_analysis_chats (paginate, collect all with feedback)
    │
    ▼
[For each conversation with feedback]
  → read feedback text
  → optionally: get_stored_conversation for full context
  → optionally: get_analysis_step_details for a specific step
    │
    ▼
Categorize feedback → produce categorization table
    │
    ▼
Build action item list → review with user
    │
    ▼
create_workspace_branch (or switch to existing dev branch)
    │
    ├── Semantic layer: create_object / update_object (entities, attributes, metrics)
    ├── Context layer: create_context_item / update_context_item
    └── Agents: update_agent
    │
    ▼
validate_object (for any uncertain YAML)
    │
    ▼
get_branch_history (confirm what changed)
    │
    ▼
create_pr_for_working_branch → display PR URL
```

---

## Tips

- **Batch similar items.** If five conversations all lack the same metric, create it once and note all five as the motivation.
- **Prefer fixing the semantic layer over adding instructions.** If a `Data Issue` can be resolved by correcting a metric's SQL, do that — don't add an instruction telling the AI to work around the wrong value.
- **Instructions must be short.** If the proposed instruction is longer than two sentences, consider whether it should be a skill instead. See the `context-item-creation` skill for the boundary.
- **Check for existing items before creating.** Run `list_context_items` and `search_model` before adding anything — duplicate instructions or metrics with slightly different names are worse than none.
- **Start small.** Apply the highest-priority items first, validate, then continue. A PR with five focused changes is easier to review than one with twenty.
