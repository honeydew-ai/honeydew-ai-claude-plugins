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

Because a single perspective can play either role (a curated dataset users consume directly, or a hidden cache routed to behind the scenes), the YAML schema is shared between them. The configuration choices you make — especially *which attributes you group by* — determine which queries can hit it.

> Dynamic datasets are fundamentally different from entity caches. Entity caches materialize an *entire entity* (and its calculated attributes) and live on the entity YAML. See the `entity-creation` skill for that. Use a dynamic dataset when you want to control the granularity, metric set, or filter scope independently of any entity.

---

## When to Create a Dynamic Dataset

| Goal | What to build | Key fields |
|---|---|---|
| **Share a curated slice** with a BI tool, Python notebook, or external app | Dataset deployed as a view or table | `attributes`, `metrics`, `filters`, `delivery` |
| **Build a dbt model** that wraps semantic logic | Dataset with dbt delivery | `delivery.use_for_cache: dbt` |
| **Accelerate slow queries** (the high-leverage case) | Aggregate cache | `attributes` on entity keys, additive `metrics`, `delivery.use_for_cache` |
| **Freeze a dataset** for ad-hoc analysis | Dataset deployed as a table | `delivery: ... target: table` |

The aggregate-cache flow is where most of the performance value lives, and it's the case most likely to be misconfigured. A poorly designed aggregate cache only serves the exact queries it was built for; a well-designed one can serve hundreds of variant queries from the same materialized table.

---

## Creation Method

### Primary: create_object with perspective YAML

Dynamic datasets are created via `create_object` with `type: perspective` YAML. Always validate first:

```
validate_object → review compiled object → create_object
```

For updates, use `update_object` with the perspective's `object_key`. Find the key with `search_model` if you don't have it.

Required permission: Editor or higher.

### After Creation: Display the UI Link

The response from `create_object` / `update_object` includes a `ui_url`. Always show it to the user so they can open the perspective in the Honeydew app, inspect compiled SQL, and trigger a deploy from the UI when they're ready.

---

## Decision Flow

```
Need to create a dynamic dataset?
    │
    ├─► Goal: accelerate slow queries (aggregate cache)?
    │       └─► Build for additive metrics on entity-key groups
    │           See "Aggregate Cache Best Practices" below ✓
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

---

## Aggregate Cache Best Practices

These four rules determine whether an aggregate cache accelerates a few queries or many. Get them right and one cache can serve dozens of dashboard variants; get them wrong and the cache sits unused.

### 1. Group by entity keys, not foreign-key attributes

The single most common mistake. When a perspective groups by an **entity key** (e.g. `properties.property_id` — the primary key of the properties entity), Honeydew's aggregate-aware engine treats the cache as representing *the whole entity*. Any query that groups by *any attribute reachable from that entity* can roll up from the cache — including attributes on related entities reached via joins (e.g. `hosts.country` via `properties.host_id → hosts`).

When you instead group by an **FK attribute on the source entity** (e.g. `bookings.property_id` — the FK column on bookings), Honeydew sees just one specific column. Only queries that explicitly group by that exact attribute will route. The cache becomes far less reusable.

| Pattern | Routing coverage |
|---|---|
| `attributes: [properties.property_id, date.date]` | Any property attribute, any date attribute, anything reachable via joins from properties or date |
| `attributes: [bookings.property_id, bookings.check_in]` | Only queries grouping by `bookings.property_id` and/or `bookings.check_in` exactly |

The values in the columns may be string-equal, but Honeydew's matching logic is structural, not value-based.

**Rule:** when the cache aggregates events from a fact entity (`bookings`, `orders`, `events`), prefer grouping by the keys of the *related dimension entities* (`properties.property_id`, `users.user_id`, `date.date`) rather than the FK attributes on the fact entity.

### 2. Use additive metrics for partial-group matching

Honeydew can roll up additive aggregations — `SUM`, `COUNT`, `MIN`, `MAX` — from a pre-aggregated row to any coarser grouping. A cache built at `(property_id, date)` grain can serve a query at just `property_id`, just `date`, or no grouping at all, by re-aggregating the cached rows.

Non-additive aggregations — `AVG`, `COUNT(DISTINCT)` — only match when the user query has the *exact* same groups as the cache. They can't roll up.

When the metric you want to accelerate is non-additive, decompose it into additive building blocks. Replace `AVG(x)` with the pair `SUM(x) / COUNT(*)`, define the SUM and COUNT as additive metrics in the cache, and have the AVG metric reference them. The downstream calculation re-derives correctly from any roll-up.

For complex metrics that aren't auto-detected as additive, set the `rollup` field on the metric definition (`rollup: sum`, `min`, `max`, or `no_rollup`). This is on the metric, not the perspective.

### 3. Avoid explicit filters; use a domain instead

A cache with an explicit filter (e.g. `filters: [orders.year = 2024]`) only serves user queries that include that exact filter. This kills routing for almost every dashboard variant.

If you need scoping (e.g. a regional cache, an active-records cache), put the filter on a **domain** and set the perspective's `domain:` field. Any user query in the same domain automatically inherits the filter, so cache and query stay aligned.

### 4. Connect time dimensions through the time spine

If the cache groups events by date, group by the **time spine entity key** (`date.date`), not the source entity's date column (`bookings.check_in`). Through entity-key matching, this lets queries grouping by `date.month`, `date.quarter`, `date.year`, or any other spine attribute roll up from the daily cache automatically.

> Add the time spine grouping with the additive metrics it accelerates, not as a separate cache. One cache at `(entity_key, date.date)` grain typically beats two caches at `(entity_key)` and `(date.date)` separately.

---

## Examples

See [examples.md](examples.md) for full worked examples covering: shared analytics dataset, aggregate cache (basic), aggregate cache with additive-metric decomposition, domain-scoped cache, dbt-orchestrated cache, and dataset update.

---

## Discovery Helpers

Use these MCP tools before creating a dynamic dataset:

- `list_entities` — Identify which entities provide the metrics and attributes you'll include
- `get_entity` — Inspect an entity's metrics, especially their additivity (auto-detected for SUM/COUNT; check `rollup` on others)
- `search_model` — Find existing perspectives, find object keys for updates
- `list_domains` — If the dataset should run in a domain context, find the right one
- `get_sql_from_fields` — Generate the SQL Honeydew would produce for a candidate query; useful for verifying the perspective covers the user's expected query patterns *before* deploying

---

See [reference.md](reference.md) for: full perspective YAML schema, delivery options for Snowflake / Databricks / dbt, and the two delivery YAML shapes (cache form vs. list-of-warehouses form).

---

## Documentation Lookup

Search Honeydew docs when:

- The user asks about how aggregate caching works under the hood (matching rules, entity-key matching, partial-group matching)
- You need warehouse-specific delivery details (Snowflake dynamic tables, Databricks tables, dbt incremental builds)
- The user asks about parameterized datasets, conditional filtering, or order-of-computation
- Edge cases around non-additive metrics, custom SQL transforms, or domain interactions

Search for: "dynamic datasets", "perspectives", "aggregate aware caching", "use_for_cache", "rollup", "delivery".

---

## Best Practices

- **Always set `owner`** for governance and accountability.
- **Name perspectives by purpose, not by table.** `agg_bookings_by_property_date` (cache role) or `executive_kpi_dashboard` (sharing role) — readers should infer intent from the name.
- **Use a `Caches` folder** for aggregate caches and a separate folder for sharing/dbt datasets. Helps users distinguish "things I should query" from "things Honeydew uses behind the scenes."
- **Mark caches `hidden: true`** if they shouldn't appear in BI-tool listings — most users shouldn't query the cache directly.
- **Document what the cache covers** in the description: which metrics route, which don't, and why. The next person to extend the model will thank you.
- **Use placeholder catalog/schema** in delivery if the deployment target isn't decided yet, with a clear comment in the description. Better than committing wrong values that fail at deploy time.
- **Validate before creating.** Run `validate_object` first — perspective YAML errors are easier to fix in isolation than after the object is in the model.

---

## MANDATORY: Validate After Creating

After creating or updating any perspective, validate it works. The exact validation depends on the perspective's role:

**For sharing/dbt datasets** — verify the dataset compiles and returns expected data:

1. `search_model` for the perspective name to confirm it persisted (sometimes the create-response says success but the object isn't saved — re-validate).
2. `get_data_from_fields` against the entities and metrics in the perspective to verify the underlying logic works.
3. Use `get_sql_from_fields` if the user wants to see the compiled SQL.

**For aggregate caches** — verification is harder because routing is invisible until deployed:

1. `validate_object` confirms the YAML compiles.
2. `search_model` confirms it persisted.
3. *Routing cannot be tested without deploying the table.* Tell the user this clearly. Once deployed, they can verify routing by running a query through the SQL interface and inspecting the query plan — Honeydew will reference the cache table if matching applies.
4. As a partial check, run `get_sql_from_fields` for a query you'd expect the cache to serve (e.g. `metrics: [bookings.confirmed_revenue]`, `attributes: [destinations.country]`) and confirm the planner shape is sensible — but the actual cache routing only kicks in post-deploy.

---

## Common Pitfalls to Avoid

- **Grouping by FK attributes instead of entity keys.** See the first best-practice rule. The single most common mistake; the cache works for the exact query you tested with and nothing else.
- **Including non-additive metrics in a cache and expecting roll-ups.** AVG, COUNT(DISTINCT), and derived ratios won't roll up. Either decompose into additive components, or accept that those metrics won't auto-route.
- **Adding explicit filters to a cache.** Filters limit which user queries can match. Move scoping to a domain instead.
- **Forgetting that the cache is empty until deployed.** A perspective configured with `use_for_cache` doesn't do anything until the table physically exists in the warehouse. Deploy from Honeydew UI, the Native App API, dbt, or external orchestration.
- **Mixing the two delivery YAML shapes.** The cache-form (`delivery.use_for_cache + delivery.<warehouse>`) and the list-form (`delivery: [- snowflake: ..., - databricks: ...]`) are both valid for general datasets, but only the cache-form supports `use_for_cache`. See `reference.md` for which shape to use when.
- **Caching custom-SQL entities (table generators).** Custom-SQL entities like time-spine generators (`SEQUENCE`, `EXPLODE`) bypass query caching at the warehouse level. Materialize them as **entity caches** (on the entity itself) rather than dynamic-dataset caches — different mechanism, same goal. See `entity-creation` skill.
- **Ignoring `rollup:` for complex metrics.** Honeydew auto-detects additivity for plain SUM/COUNT metrics. For derived/composed metrics that are still mathematically additive, set `rollup: sum` (or `min`/`max`) explicitly so they participate in cache matching. For metrics that aren't additive (averages, ratios), set `rollup: no_rollup` to make the intent explicit and prevent silently-wrong matches.
