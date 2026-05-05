# Dynamic Dataset Examples

## Shared analytics dataset (live view)

Call `create_object` with yaml_text:

```yaml
type: perspective
name: executive_kpi_dashboard
display_name: Executive KPI Dashboard
owner: analytics@company.com
description: |-
  Top-line revenue, bookings, and host metrics for the executive dashboard.
  Live view — updates with the underlying data.
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

## Aggregate cache — canonical pattern

Groups by entity keys (`properties.property_id`, `date.date`) so entity-key matching applies:
any attribute reachable from properties or date rolls up from this cache automatically.

Call `create_object` with yaml_text:

```yaml
type: perspective
name: agg_bookings_by_property_date
display_name: Bookings Aggregate (Property × Date)
owner: analytics@company.com
description: |-
  Pre-aggregate cache of bookings at property × day grain.

  Groups use entity keys — properties.property_id and date.date — so any query grouping
  by a property attribute (type, host, destination, country, continent) or a date attribute
  (month, quarter, year, week) rolls up from this cache.

  Additive metrics only. Non-additive metrics (avg_*, distinct_*, derived ratios) won't
  auto-route; decompose those into additive components first.
hidden: true
attributes:
  - properties.property_id    # entity key — not bookings.property_id
  - date.date                 # time spine entity key — not bookings.check_in
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

## Aggregate cache — additive-metric decomposition for ratio metrics

To make a non-additive ratio metric (e.g. `cancellation_rate`) benefit from a cache, decompose
it: store the additive components in the cache, and have the ratio re-derive from them.

**Step 1** — define additive components on the entity:

```yaml
type: metric
name: total_bookings_count
sql: bookings.count
rollup: sum

type: metric
name: cancelled_bookings_count
sql: bookings.count FILTER (WHERE bookings.status = 'cancelled')
rollup: sum
```

**Step 2** — define the ratio in terms of the components:

```yaml
type: metric
name: cancellation_rate
sql: |-
  TRY_DIVIDE(bookings.cancelled_bookings_count, bookings.total_bookings_count)
rollup: no_rollup
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
delivery:
  use_for_cache: databricks
  databricks:
    enabled: true
    target: table
    name: agg_bookings_by_property_date
    catalog: analytics
    schema: caches
```

## Domain-scoped cache

Use a domain (not an explicit filter) to scope the cache. Both the cache and user queries
inherit the domain's filter automatically — routing engages for any in-domain query.

Call `create_object` with yaml_text:

```yaml
type: perspective
name: agg_bookings_us_by_property_date
display_name: Bookings Aggregate — US (Property × Date)
owner: analytics@company.com
domain: bookings_us
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

## dbt-orchestrated cache (Databricks)

dbt builds the cache table on schedule; Honeydew reads its update time to detect freshness.

**Honeydew side** — call `create_object` with yaml_text:

```yaml
type: perspective
name: agg_bookings_by_property_date
owner: analytics@company.com
hidden: true
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

## Update existing perspective

1. Use `search_model` (with `search_mode: EXACT`) to find the perspective's `object_key`.
2. Call `update_object` with `object_key` and yaml_text (full YAML, preserve field order).

Updates that change the perspective's logic require the cache table to be rebuilt — Honeydew
detects logic drift and won't route to a stale table.

## Delete perspective

1. Use `search_model` (with `search_mode: EXACT`) to find the perspective's `object_key`.
2. Call `delete_object` with that `object_key`.
