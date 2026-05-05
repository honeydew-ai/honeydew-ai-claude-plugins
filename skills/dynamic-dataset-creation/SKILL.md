---
name: dynamic-dataset-creation
description: Guides creation of Honeydew dynamic datasets (perspectives) — for sharing curated slices, building dbt models, exporting to Python, or critically setting up aggregate-aware caches that accelerate query performance by orders of magnitude. Use this skill whenever the user wants to create a perspective, build a dynamic dataset, set up a pre-aggregation, materialize a slice, deploy to a table or view, accelerate queries, speed up a dashboard, build an aggregate cache, or asks about query caching, performance optimization, or aggregate awareness in Honeydew — even if they don't say the word "perspective."
---

## Prerequisites

Before creating dynamic datasets, ensure you are on the correct workspace and branch. Use `get_session_workspace_and_branch` to check current session context. For development, create a branch with `create_workspace_branch` (the session switches automatically). See the `model-exploration` skill for the workspace/branch tool reference.

---

## Overview

A Honeydew **dynamic dataset** (also called a **perspective**) is a named, shared, governed slice of the semantic model. Conceptually it's a saved query: pick attributes, metrics, filters, optionally a domain, and Honeydew turns it into something downstream tools can consume — a Snowflake or Databricks view/table, a dbt model, or a Python data frame.

The same object also powers **aggregate-aware caching**: when configured with `use_for_cache`, Honeydew materializes the dataset as a warehouse table and automatically routes matching user queries to it. A correctly designed aggregate cache can accelerate dashboards by orders of magnitude.

> Dynamic datasets are fundamentally different from entity caches. Entity caches materialize an *entire entity* and live on the entity YAML. See the `entity-creation` skill for that. Use a dynamic dataset when you want to control the granularity, metric set, or filter scope independently of any entity.

| Goal | What to build | Key fields |
|---|---|---|
| **Share a curated slice** with a BI tool, Python notebook, or external app | Dataset deployed as a view or table | `attributes`, `metrics`, `filters`, `delivery` |
| **Build a dbt model** that wraps semantic logic | Dataset with dbt delivery | `delivery.use_for_cache: dbt` |
| **Accelerate slow queries** (the high-leverage case) | Aggregate cache | `attributes` on entity keys, additive `metrics`, `delivery.use_for_cache` |
| **Freeze a dataset** for ad-hoc analysis | Dataset deployed as a table | `delivery: ... target: table` |

---

## Key Considerations

### Decision flow

```
Need to create a dynamic dataset?
    │
    ├─► Goal: accelerate slow queries (aggregate cache)?
    │       └─► Build for additive metrics on entity-key groups
    │           See "Aggregate Cache Rules" below ✓
    │
    ├─► Goal: deliver a dbt model?
    │       └─► delivery.use_for_cache: dbt + dbt block
    │
    ├─► Goal: share a curated dataset with BI / Python?
    │       └─► delivery target: view (live) or table (frozen)
    │
    └─► Goal: parameterized dataset that adapts per user / context?
            └─► Add `parameters` block; see Honeydew docs on parameters
```

### Aggregate Cache Rules

These four rules determine whether a cache accelerates a few queries or many.

**1. Group by entity keys, not foreign-key attributes**

When a perspective groups by an **entity key** (e.g. `properties.property_id`), Honeydew's
aggregate-aware engine treats the cache as representing the whole entity. Any query grouping by
*any attribute reachable from that entity* can roll up from the cache — including attributes on
related entities via joins (e.g. `hosts.country` via `properties.host_id → hosts`).

Grouping by an **FK attribute on the source entity** (e.g. `bookings.property_id`) matches only
queries that explicitly group by that exact column.

| Pattern | Routing coverage |
|---|---|
| `attributes: [properties.property_id, date.date]` | Any property attribute, any date attribute, anything reachable via joins |
| `attributes: [bookings.property_id, bookings.check_in]` | Only queries grouping by those exact columns |

**Rule:** prefer grouping by the keys of related dimension entities rather than FK attributes on
the fact entity.

**2. Use additive metrics for partial-group matching**

`SUM`, `COUNT`, `MIN`, `MAX` can roll up from a pre-aggregated row to any coarser grouping.
`AVG`, `COUNT(DISTINCT)` only match when the user query has the exact same groups as the cache.

For non-additive metrics, decompose into additive building blocks. Replace `AVG(x)` with
`SUM(x)` and `COUNT(x)` in the cache; the AVG metric references those two and re-derives at
any grain.

For complex metrics not auto-detected as additive, set `rollup: sum` (or `min`/`max`) on the
metric definition. For non-additive metrics, set `rollup: no_rollup`.

**3. Avoid explicit filters; use a domain instead**

A cache filter (e.g. `filters: [orders.year = 2024]`) only serves user queries with that exact
filter. Put scoping on a **domain** instead and set the perspective's `domain:` field — cache and
user query automatically share the filter.

**4. Connect time dimensions through the time spine**

Group by the time spine entity key (`date.date`), not the source entity's date column
(`bookings.check_in`). This lets queries grouping by `date.month`, `date.quarter`, or `date.year`
roll up from the daily cache automatically.

See [reference.md](reference.md) for: full perspective YAML schema and delivery options for
Snowflake / Databricks / dbt.

---

## Creation Methods

### create_object (Required)

Always use `create_object` with full YAML. Run `validate_object` first to catch YAML errors
before committing.

Call `create_object` with `yaml_text`:

```yaml
type: perspective
name: <snake_case_name>
display_name: <Human Readable Name>
description: |-
  <business description>
owner: <owner_email_or_team>
hidden: <true/false>        # set true for caches
domain: <domain_name>       # optional

attributes:
  - <entity.attribute_name>
metrics:
  - <entity.metric_name>
filters:
  - <filter expression>

delivery:
  ...                       # see reference.md for delivery shapes
```

**Required fields:**

- `type: perspective`
- `name` — snake_case identifier
- `owner` — **CRITICAL: always set** (email or team name)
- `attributes` and/or `metrics`
- `delivery` — warehouse target and cache configuration

### update_object (for updates)

1. Use `search_model` (with `search_mode: EXACT`) to find the perspective's `object_key`.
2. Call `update_object` with the full updated YAML (`yaml_text`) and the `object_key`.

> **Minimal diff rule:** Preserve the existing field order and formatting. Only change the fields
> you need to modify. Objects are versioned in git, so unnecessary reordering creates noisy diffs.

### After Creation/Update: Display the UI Link

After a successful `create_object` or `update_object` call, the response includes a `ui_url`
field. **Always display this URL to the user** so they can open the perspective in the Honeydew
app, inspect compiled SQL, and trigger a deploy from the UI when they're ready.

### delete_object (for deletion)

1. Use `search_model` (with `search_mode: EXACT`) to find the perspective's `object_key`.
2. Call `delete_object` with that `object_key`.

---

## Examples

See [examples.md](examples.md) for full worked examples covering: shared analytics dataset,
aggregate cache (basic), aggregate cache with additive-metric decomposition, domain-scoped cache,
dbt-orchestrated cache, and dataset update.

---

## Discovery Helpers

Use these MCP tools before creating a dynamic dataset:

- `list_entities` — Identify which entities provide the metrics and attributes you'll include
- `get_entity` — Inspect an entity's metrics, especially their additivity
- `search_model` — Find existing perspectives, find object keys for updates
- `list_domains` — If the dataset should run in a domain context, find the right one
- `get_sql_from_fields` — Generate the SQL Honeydew would produce for a candidate query; useful
  for verifying the perspective covers the user's expected query patterns before deploying

---

## Documentation Lookup

Search Honeydew docs when:

- The user asks about how aggregate caching works under the hood (matching rules, entity-key
  matching, partial-group matching)
- You need warehouse-specific delivery details (Snowflake dynamic tables, Databricks tables,
  dbt incremental builds)
- The user asks about parameterized datasets, conditional filtering, or order-of-computation
- Edge cases around non-additive metrics, custom SQL transforms, or domain interactions

Search for: "dynamic datasets", "perspectives", "aggregate aware caching", "use_for_cache",
"rollup", "delivery".

---

## Best Practices

- **Always set `owner`** for governance and accountability.
- **Name perspectives by purpose, not by table.** `agg_bookings_by_property_date` (cache role)
  or `executive_kpi_dashboard` (sharing role) — readers should infer intent from the name.
- **Mark caches `hidden: true`** so they don't appear in BI-tool listings.
- **Document what the cache covers** in the description: which metrics route, which don't,
  and why.
- **Validate before creating.** Run `validate_object` first — perspective YAML errors are easier
  to fix before the object is in the model.

---

## MANDATORY: Validate After Creating

After creating or updating any perspective, validate it works.

**For sharing/dbt datasets:**

1. `search_model` for the perspective name to confirm it persisted.
2. `get_data_from_fields` against the entities and metrics in the perspective to verify the
   underlying logic works.
3. Use `get_sql_from_fields` if the user wants to see the compiled SQL.

**For aggregate caches:**

1. `validate_object` confirms the YAML compiles.
2. `search_model` confirms it persisted.
3. *Routing cannot be tested without deploying the table.* Tell the user this clearly. Once
   deployed, verify routing by running a query through the SQL interface and inspecting the
   query plan — Honeydew will reference the cache table if matching applies.
4. As a partial check, run `get_sql_from_fields` for a query you'd expect the cache to serve
   and confirm the planner shape is sensible.

---

## Common Pitfalls to Avoid

- **Grouping by FK attributes instead of entity keys.** The single most common mistake; the
  cache works for the exact query you tested with and nothing else.
- **Including non-additive metrics in a cache and expecting roll-ups.** AVG, COUNT(DISTINCT),
  and derived ratios won't roll up. Decompose into additive components or accept they won't
  auto-route.
- **Adding explicit filters to a cache.** Move scoping to a domain instead.
- **Forgetting that the cache is empty until deployed.** A perspective configured with
  `use_for_cache` does nothing until the table physically exists in the warehouse.
- **Mixing the two delivery YAML shapes.** Only the cache-form supports `use_for_cache`.
  See `reference.md` for which shape to use when.
- **Caching custom-SQL entities (table generators).** Materialize them as entity caches
  instead — different mechanism, same goal. See `entity-creation` skill.
- **Ignoring `rollup:` for complex metrics.** Set `rollup: sum` (or `min`/`max`) for
  mathematically additive metrics Honeydew can't auto-detect. Set `rollup: no_rollup` for
  non-additive metrics.
