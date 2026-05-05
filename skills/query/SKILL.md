---
name: query
description: Use when the user wants to query, analyze, or explore data through the Honeydew semantic layer. Covers structured queries and multi-step deep analysis.
---

## Prerequisites

Queries run against the workspace and branch set for the current session. Use `get_session_workspace_and_branch` to check the current context. If no workspace/branch is set, use `list_workspaces`, `list_workspace_branches`, and `set_session_workspace_and_branch` to select one. See the `workspace-branch` skill for the full workspace/branch tool reference.

---

## Overview

Honeydew provides three ways to query data through the semantic layer. Each method suits a different situation — pick the right one based on how well you understand the model and how complex the question is.

| Method                    | Tool                                              | Best For                                                                         |
| ------------------------- | ------------------------------------------------- | -------------------------------------------------------------------------------- |
| **Structured query**      | `get_data_from_fields` / `get_sql_from_fields`    | You know the exact fields. Deterministic, full control.                          |
| **Deep analysis**         | `initiate_analysis` + `monitor_analysis`          | Any natural language question — simple or complex, "why", multi-step, agentic.  |
| **Explain a prior step**  | `get_analysis_step_details`                       | User asks how a specific step in a prior analysis was calculated.                |

---

## When to Use Each Method

### 1. Structured Query (`get_data_from_fields` / `get_sql_from_fields`)

**Use when:**

- You know the entity, attribute, and metric names (or can discover them via `list_entities` / `get_entity`)
- You need precise control over filters, ordering, and field selection
- You want deterministic, reproducible results
- You need to validate a newly created metric or attribute
- The user specifies exact fields like "show me `detailed_listings.price` by `detailed_listings.room_type`"

**Do NOT use when:**

- The question requires multi-step reasoning or investigation

**How it works:**

- `get_data_from_fields` — executes the query and returns data rows
- `get_sql_from_fields` — returns the generated SQL without executing (useful for review, debugging, or handing off to other tools)

Both take the same field parameters.

### 2. Deep Analysis (`initiate_analysis` + `monitor_analysis`)

**Use when:**

- The user asks a question in plain English and you don't know the exact field names
- The user wants a quick answer without worrying about model details
- The question requires multiple steps or investigative reasoning
- The user asks "why" something happened (e.g., "why did revenue drop in Q3?")
- The user wants trend analysis, anomaly detection, or root cause investigation
- The question is open-ended and may require looking at the data from multiple angles
- Follow-up questions build on prior analysis (use `conversation_id`)

---

## Decision Flow

```
User asks a data question
    │
    ├─► User asks to explain / drill into a step from a prior analysis?
    │       └─► get_analysis_step_details (step_id from monitor_analysis)
    │           Returns semantic query, data results, and SQL for that step
    │
    ├─► Do you know the exact field names?
    │       │
    │       ├─► YES → get_data_from_fields (structured, deterministic)
    │       │         (or get_sql_from_fields to preview SQL without executing)
    │       │
    │       └─► NO → initiate_analysis + monitor_analysis (plain English, any complexity)
    │
    └─► Plain English question / investigation / "why" / trends?
            └─► initiate_analysis + monitor_analysis
```

---

## Method 1: Structured Query

### Field Parameters

A structured query uses flat field parameters to define what data to retrieve:

- **`attributes`** — dimensions to group by (columns in the output), e.g. `["entity.attribute_name"]`
- **`metrics`** — aggregated measures (SUM, COUNT, AVG, etc.), e.g. `["entity.metric_name"]`
- **`filters`** — row-level filters applied before aggregation, e.g. `["entity.field = 'value'"]`
- **`order_by`** — sort order for results. **Each entry MUST be a quoted string**, as if it were a SQL identifier — e.g. `["\"entity.field\" ASC"]`. Always wrap the field reference in double quotes inside the string.
- **`domain`** — optional domain name for query context
- **`limit`** — max rows to return (default: 100)
- **`offset`** — rows to skip (for pagination)

All fields use `entity.field_name` syntax. Cross-entity fields are supported when relations exist.

### Discovering Fields

Before building a query, discover the available fields:

1. `list_entities` — see all entities
2. `get_entity` with entity name — see its attributes, metrics, and relations
3. `get_field` with entity and field name — get detailed info about a specific field
4. `list_domains` — see all available domains (useful before passing `domain` parameter)
5. `search_model` with a keyword and `search_mode` (`OR` for broad discovery, `EXACT` for known names) — find fields across the model

### Examples

**Simple metric query — total count:**

Call `get_data_from_fields` with:

- `metrics`: `["detailed_listings.count"]`

**Dimension breakdown — listings by room type:**

Call `get_data_from_fields` with:

- `attributes`: `["detailed_listings.room_type"]`
- `metrics`: `["detailed_listings.count"]`
- `order_by`: `["\"detailed_listings.count\" DESC"]`

**Filtered query — only entire homes:**

Call `get_data_from_fields` with:

- `attributes`: `["detailed_listings.neighbourhood_cleansed"]`
- `metrics`: `["detailed_listings.count"]`
- `filters`: `["detailed_listings.room_type = 'Entire home/apt'"]`
- `order_by`: `["\"detailed_listings.count\" DESC"]`

**Cross-entity query — listings with host info:**

Call `get_data_from_fields` with:

- `attributes`: `["detailed_listings.room_type", "dim_host.host_is_superhost"]`
- `metrics`: `["detailed_listings.count"]`
- `order_by`: `["\"detailed_listings.count\" DESC"]`

**Using aliases — rename fields or ad-hoc expressions:**

You can alias any field or ad-hoc expression using `AS "alias_name"`. This controls the column name in the output.

Call `get_data_from_fields` with:

- `attributes`: `["detailed_listings.room_type"]`
- `metrics`: `["detailed_listings.count AS \"total_listings\"", "AVG(detailed_listings.price) AS \"avg_price\""]`
- `order_by`: `["\"total_listings\" DESC"]`

Once aliased, use the alias (not the original expression) in `order_by`.

**Pagination — large result sets:**

Call `get_data_from_fields` with:

- `attributes`: (your fields)
- `metrics`: (your metrics)
- `limit`: 50 (max rows to return)
- `offset`: 100 (skip first 100 rows)

**Finding duplicate values:**

Call `get_data_from_fields` with:

- `attributes`: `["detailed_listings.host_name"]`
- `metrics`: `["COUNT(detailed_listings.host_name)"]`
- `filters`: `["COUNT(detailed_listings.host_name) > 1"]`
- `order_by`: `["\"COUNT(detailed_listings.host_name)\" DESC"]`

This groups by the attribute, counts occurrences, and filters to only rows that appear more than once — surfacing duplicates.

**SQL preview only:**

Call `get_sql_from_fields` with the same field parameters to see the generated SQL without executing.

### Filter Syntax

Filters use standard comparison expressions: `=`, `>`, `<`, `IN (...)`, `ILIKE`, `SEARCH(...)`, `IS NULL`, booleans, date ranges, and `AND`/`OR` combinations.

> For the complete filter expression reference — including SEARCH, date handling, and type casting — see the **filtering** skill.

---

## Method 2: Deep Analysis

### initiate_analysis + monitor_analysis

Deep analysis is a two-step async process:

**Step 1 — start the analysis:**

Call `initiate_analysis` with:

- `question` (required): the analysis question
- `agent` (required for new conversations): agent name — use `list_agents` to discover available agents and their associated domains
- `conversation_id` (optional): ID from a previous call, for follow-up questions

Returns a `conversation_id` immediately.

**Step 2 — poll until done:**

Call `monitor_analysis` repeatedly with the `conversation_id` until `status` is `"DONE"`. Each call returns only new messages since the last call.

**Report progress when it's meaningful to the user** — not every poll, but not silently either. Use judgement:

- On `interpretation` / `plan`: tell the user what the analysis intends to do
- On `step_insight` with a substantive finding: post a one-liner — e.g. *"58 menu items found, top is The King Combo at $431M"* — so the user can follow along and catch a misdirected analysis early
- On internal errors, retries, or backtracking steps: skip reporting — the user doesn't need to know the agent corrected itself, only that meaningful progress is being made

When `status` is `"DONE"`, the final user-facing report is in the `responses` array.

```
# Example
initiate_analysis(question="Analyze revenue by cuisine type", agent="my_agent")
→ { conversation_id: "abc123" }

# Poll loop — report to user after each call that has new content
monitor_analysis(conversation_id="abc123")
→ interpretation + plan received → tell user what the analysis will do

monitor_analysis(conversation_id="abc123")
→ STEP/0 insight: "Top item is Indian at $1B" → report to user

monitor_analysis(conversation_id="abc123")
→ STEP/1 insight: "Added % contribution" → report to user

...

monitor_analysis(conversation_id="abc123")
→ { status: "DONE", responses: [{ text: "..." }] }
```

### After Deep Analysis: Display the UI Link

The final response may include a `ui_url` field. **Always display this URL to the user** if present so they can view the full analysis in the Honeydew application.

### Follow-up Questions

Use `conversation_id` from the previous analysis to ask follow-up questions that build on prior state:

```
initiate_analysis(
  question="Now break this down by room type — does the pattern hold?",
  conversation_id="abc123"
)
```

### Explaining a Prior Analysis Step

When the user asks to explain, review, or drill into a specific step (e.g., "how was that calculated?", "explain the cuisine breakdown", "what happened in step 5"):

1. Identify the `step_id` from `monitor_analysis` progress messages (e.g. `"STEP/5"`)
2. Call `get_analysis_step_details` with `conversation_id` and `step_id`

Returns:
- The semantic query used (attributes, metrics, filters)
- Context resolved (which entities/fields Honeydew selected)
- Context items used (if any instructions or knowledge were applied)
- Data results from that step
- The SQL generated for that step

### Example Questions

**Simple natural language:**
- "What are the top 10 neighbourhoods by number of listings?"
- "Show me average price by room type."

**Complex analysis:**
- "Why did the average review score drop for listings in Brooklyn?"
- "What factors most influence listing price? Analyze the key drivers."
- "Compare superhost vs non-superhost performance across all metrics."
- "Identify unusual patterns in listing availability over the past year."
- "What are the characteristics of top-performing listings?"

**Step explanation (use `get_analysis_step_details`, not a new question):**
- "How was that calculated?"
- "Explain the cuisine breakdown."
- "Show me what happened in that step."
- "What fields were used there?"

---

## Combining Methods

For complex tasks, combine methods in sequence:

1. **Discover** — Use `list_entities` / `get_entity` to understand the model
2. **Query** — Use `get_data_from_fields` for precise, targeted queries
3. **Investigate** — Use `initiate_analysis` + `monitor_analysis` for root cause or trend analysis

### Example Workflow

User: "Help me understand pricing patterns for Airbnb listings."

1. Discover entities: `list_entities` → find `detailed_listings`
2. Explore fields: `get_entity` for `detailed_listings` → find `price`, `room_type`, `neighbourhood_cleansed`
3. Targeted query: `get_data_from_fields` → price distribution by neighbourhood for Entire homes only
4. Deep dive: `initiate_analysis` → "What factors most influence listing price? Analyze correlations with room type, location, amenities, and reviews."

---

## Documentation Lookup

Use the `honeydew-docs` MCP tools to search the Honeydew documentation when:

- The user asks about query capabilities or features not covered in this skill
- You need to understand how the query API interacts with domains, parameters, or governance rules
- The user encounters unexpected query behavior and needs deeper context on how the semantic layer resolves queries

Search for topics like: "queries", "perspectives", "dynamic datasets", "parameters", "query API".

---

## Tip: Getting Distinct Values for a Field

To retrieve the distinct (unique) values of a field, include it in `attributes` and add a count metric in `metrics`.
Use the entity's built-in count metric (e.g., `entity.count`) if available, or an ad-hoc count metric using `COUNT(entity.field)`
on the field whose distinct values you want — never use `COUNT(*)`.
The metric forces aggregation, which groups by the attribute and returns one row per distinct value.

**Example — distinct room types:**

Call `get_data_from_fields` with:

- `attributes`: `["detailed_listings.room_type"]`
- `metrics`: `["COUNT(detailed_listings.room_type)"]`
- `order_by`: `["\"COUNT(detailed_listings.room_type)\" DESC"]`

This returns each unique `room_type` along with its count, ordered by frequency. The count is a useful bonus — it tells you how common each value is — but the key point is that the query returns **one row per distinct value**.

This pattern is useful for:

- **Exploring filter values** — find out what values exist before writing a filter expression (see the **filtering** skill)
- **Validating a new attribute** — after creating a calculated attribute, check its distinct output values to confirm the logic is correct (see the **attribute-creation** skill)
- **Understanding data distribution** — see how data is spread across categories

---

## Best Practices

- **Start with discovery** — always check `list_entities` / `get_entity` before building queries, so you reference real fields
- **Use structured queries for precision** — when you know the fields, `get_data_from_fields` gives you full control and reproducible results
- **Use deep analysis for insight** — when the question is about "why" or requires investigating multiple dimensions
- **Report meaningful progress, not every step** — surface a one-liner when a step produces a substantive finding; skip internal retries and error-recovery steps the user doesn't need to see
- **Explain a prior step** — use `get_analysis_step_details` with the `step_id`; the response includes the semantic query, data results, and SQL for that step
- **Paginate large results** — use `limit` and `offset` in `get_data_from_fields` to avoid overwhelming output
- **Show SQL when debugging** — use `get_sql_from_fields` to inspect the generated query
- **Reference fields correctly** — always use `entity.field_name` syntax in field parameters
