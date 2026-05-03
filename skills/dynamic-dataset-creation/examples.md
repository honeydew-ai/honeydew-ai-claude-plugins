# Dynamic Dataset Examples

Six worked examples covering the spectrum: a sharing dataset, the canonical aggregate cache (with the entity-key matching design), additive-metric decomposition, a domain-scoped cache, dbt orchestration, and how to update an existing perspective.

---

## Example 1 — Shared analytics dataset (live view)

A KPI view that an executive dashboard reads from. Updates live (Snowflake VIEW) so the dashboard reflects current data.

```yaml
type: perspective
name: executive_kpi_dashboard
display_name: Executive KPI Dashboard
owner: analytics@company.com
description: |-
  Top-line revenue, bookings, and host metrics for the executive dashboard. Live view — updates with the underlying data.
folder: Dashboards
attributes:
  - destinations.country
  - countries.continent
  - bookings.season
metrics:
  - bookings.confirmed_revenue
  - bookings.confirmed_bookings_count
  - bookings.avg_booking_value
delivery:
  - snowflake:
      target: view
      name: executive_kpi_dashboard
      schema: dashboards
      database: analytics
      enabled: true
```

This is the **list-form** delivery — appropriate because the perspective is for direct consumption, not aggregate-cache routing.

---

## Example 2 — Aggregate cache (the canonical pattern)

The high-leverage case. Pre-aggregates bookings to property-day grain so dozens of dashboard queries route to a single small table.

**Best practice: always group by entity keys** (e.g. `properties.property_id`, `date.date`) rather than FK attributes on the source entity (e.g. `bookings.property_id`, `bookings.check_in`). Entity-key grouping triggers Honeydew's entity-key matching — any attribute reachable from that entity rolls up from the cache, including attributes on related entities reached via joins. FK-attribute grouping only matches queries that explicitly group by that exact column.

```yaml
type: perspective
name: agg_bookings_by_property_date
display_name: Bookings Aggregate (Property × Date)
owner: analytics@company.com
description: |-
  Pre-aggregate cache of bookings at property × day grain. Honeydew routes matching queries here automatically.

  Groups use entity keys — properties.property_id (the properties entity key) and date.date (the time spine entity key) — so entity-key matching applies. Any query grouping by an attribute on properties (property_type, host, destination, country, continent) or on date (month, quarter, year, week) will roll up from this cache via joins.

  All metrics are additive (SUM/COUNT) so partial-group matching applies on top.

  Limitations: non-additive metrics (avg_*, distinct_*, derived ratios) won't auto-route. For those, decompose into additive components first.
folder: Caches
hidden: true
attributes:
  - properties.property_id    # entity key, not bookings.property_id
  - date.date                 # time spine entity key, not bookings.check_in
metrics:
  - bookings.count
  - bookings.total_revenue
  - bookings.confirmed_revenue
  - bookings.confirmed_bookings_count
  - bookings.cancelled_bookings_count
  - bookings.total_nights_booked
delivery:
  use_for_cache: databricks
  databricks:
    enabled: true
    target: table
    name: agg_bookings_by_property_date
    catalog: analytics
    schema: caches
```

**What this cache routes:**
- `confirmed_revenue` alone (rolls up over all properties and dates)
- `confirmed_revenue` by `destinations.country` (via property → destination → country)
- `total_revenue` by `properties.property_type`
- `total_revenue` by `hosts.country` (via property → host → country)
- `confirmed_bookings_count` by `date.month` (via spine roll-up)
- `total_nights_booked` by `countries.continent` and `date.quarter`
- Any combination of the above

**What it doesn't route** (non-additive):
- `avg_booking_value` (AVG)
- `cancellation_rate` (TRY_DIVIDE)
- `distinct_guests` (COUNT DISTINCT)
- `dau`, `wau`, `mau` (TIME_METRIC + COUNT DISTINCT)

---

## Example 3 — Additive-metric decomposition for ratio metrics

Suppose you want `cancellation_rate` (a ratio) to also benefit from the aggregate cache. The fix is to decompose: the cache stores the additive components, and the ratio metric re-derives from them.

**Step 1** — define additive components on the entity (these are likely already there or easy to add):

```yaml
# bookings.total_bookings_count — already additive
type: metric
name: total_bookings_count
sql: COUNT(*)
rollup: sum   # explicit, even though auto-detected

# bookings.cancelled_bookings_count — already additive
type: metric
name: cancelled_bookings_count
sql: COUNT(*) FILTER (WHERE bookings.status = 'cancelled')
rollup: sum
```

**Step 2** — define the ratio in terms of the additive components:

```yaml
type: metric
name: cancellation_rate
sql: |-
  TRY_DIVIDE(bookings.cancelled_bookings_count, bookings.total_bookings_count)
rollup: no_rollup   # the ratio itself doesn't roll up, but its inputs do
```

**Step 3** — include both additive components in the cache:

```yaml
type: perspective
name: agg_bookings_by_property_date
attributes:
  - properties.property_id
  - date.date
metrics:
  - bookings.total_bookings_count
  - bookings.cancelled_bookings_count
  # ... other additive metrics
delivery:
  use_for_cache: databricks
  databricks: { ... }
```

Now when a user queries `cancellation_rate` by `destinations.country`, Honeydew:
1. Sees `cancellation_rate` decomposes into two additive metrics
2. Both additive metrics are in the cache, grouped by `properties.property_id`
3. Rolls up both numerator and denominator from the cache to country grain
4. Computes the ratio at country grain

The ratio is correct because each input was correctly rolled up before division.

---

## Example 4 — Domain-scoped cache (avoids explicit filters)

You want a cache for US-only revenue analytics. **Don't** put the US filter on the cache — that limits routing to queries with that exact filter. Instead, define a domain with the filter and put both the cache and user queries in that domain.

**Domain definition** (created via `domain-creation` skill):
```yaml
type: domain
name: bookings_us
extends: [bookings_analytics]
filters:
  - name: us_destinations_only
    sql: destinations.country = 'United States'
```

**Cache, scoped to the domain**:
```yaml
type: perspective
name: agg_bookings_us_by_property_date
display_name: Bookings Aggregate — US (Property × Date)
domain: bookings_us             # cache and user queries share the filter
folder: Caches
hidden: true
attributes:
  - properties.property_id
  - date.date
metrics:
  - bookings.count
  - bookings.confirmed_revenue
  - bookings.total_nights_booked
delivery:
  use_for_cache: databricks
  databricks:
    enabled: true
    target: table
    name: agg_bookings_us_by_property_date
    catalog: analytics
    schema: caches
```

Any query a user runs in the `bookings_us` domain automatically inherits the country filter, and matches the cache's domain — so routing engages. A cross-domain query (e.g. someone running a query without specifying domain) won't route to this cache, which is exactly correct: that user is asking for non-US data, the cache doesn't have it.

---

## Example 5 — dbt-orchestrated cache (Databricks)

Databricks doesn't have a native auto-refreshing dynamic-table equivalent. The standard pattern is to use dbt as the orchestrator: dbt builds the cache table on schedule, Honeydew reads its update time to detect freshness.

**Honeydew side**:
```yaml
type: perspective
name: agg_bookings_by_property_date
attributes:
  - properties.property_id
  - date.date
metrics:
  - bookings.count
  - bookings.confirmed_revenue
delivery:
  use_for_cache: dbt
  dbt:
    enabled: true
    dbt_model: agg_bookings_by_property_date
```

**dbt side** (`models/caches/agg_bookings_by_property_date.sql`):
```sql
{{ config(materialized='table') }}

{{ honeydew.get_dataset_sql('agg_bookings_by_property_date') }}
```

Pre-aggregate caches are usually full-refresh (`materialized='table'`), not incremental. Refresh cadence is up to your dbt schedule.

For incremental refresh patterns, see Honeydew's dbt integration docs — but be careful: incremental caches need to detect when the underlying logic changed between runs to avoid mixing different definitions in the same table.

---

## Example 6 — Updating an existing perspective

Use `update_object` with the perspective's `object_key`. To find the key, use `search_model`:

```
search_model(query="agg_bookings_by_property_date", search_mode="EXACT")
```

Then `update_object` with the new YAML. Preserve field order from the existing YAML (use `get_entity` or fetch via `search_model` first) — minimal diffs are easier to review and don't create noisy git history.

```
update_object(
  object_key="<key from search_model>",
  yaml_text="<full updated perspective YAML>"
)
```

Updates that change the perspective's logic (added groups, added metrics, changed filters) require the cache table to be rebuilt — Honeydew detects logic drift and won't route to a stale table. Trigger a rebuild from the UI deploy action or your orchestrator.

---

## When You're Stuck

- Cache isn't routing as expected? Run `get_sql_from_fields` on the user query and on the perspective separately. Compare entities used and join paths. The cache only matches if Honeydew sees the same shape.
- Metric not auto-routing despite seeming additive? Check the metric YAML for an explicit `rollup:` field. Honeydew's auto-detection is conservative; complex metrics need explicit `rollup: sum` (or other) to participate.
- Domain mismatch? Confirm both the cache's `domain:` and the user query's domain context are the same. Source filters must match exactly.
- Cache deployed but Honeydew says it's stale? The underlying perspective definition changed since the table was built. Redeploy.
