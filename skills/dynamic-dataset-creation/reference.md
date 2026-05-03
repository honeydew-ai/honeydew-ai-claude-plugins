# Dynamic Dataset Reference

## Perspective YAML Schema

```yaml
type: perspective
name: <snake_case_name>
display_name: <Human Readable Name>
description: |-
  <business description>
owner: <owner_email_or_team>
folder: <folder>            # optional, group in UI
hidden: <true/false>        # optional, hide from listings
labels: [label1, label2]    # optional
domain: <domain_name>       # optional, run in domain context

# What the dataset contains
attributes:
  - <entity.attribute_name>     # named attribute
  - <entity.attribute_name as "alias">  # aliased
  - <ad-hoc SQL expression>     # ad-hoc, not reusable elsewhere
metrics:
  - <entity.metric_name>
  - <SUM(entity.field) as "alias">
filters:
  - <filter expression>
parameters:
  - name: <parameter_name>
    value: <parameter_value>

# Whether to use entity / aggregate caches when serving this dataset
use_cache: true               # default true; rarely changed

# Optional SQL transform applied last (e.g. ORDER BY, LIMIT)
transform_sql: |-
  ORDER BY ...

# Group all attributes when no metrics provided (deduplication)
group_by_all: false           # default false

# Where the dataset gets materialized — see "Delivery" below
delivery:
  ...
```

## Delivery — Two YAML Shapes

The `delivery` block has two valid shapes depending on the dataset's purpose. Pick one.

### Shape A — Aggregate cache form (use this for caches)

When the perspective is meant to serve as an aggregate-aware cache, use the cache-form. This shape supports `use_for_cache`, which is required for the cache routing engine to recognize the perspective.

```yaml
delivery:
  use_for_cache: <snowflake | databricks | dbt>
  snowflake:                  # only one warehouse block, matching use_for_cache
    enabled: true
    target: table             # caches must be tables, not views
    name: <table name>
    schema: <schema name>
    database: <db name>       # optional
    warehouse: <wh name>      # optional, Snowflake compute
  # OR
  databricks:
    enabled: true
    target: table
    name: <table name>
    schema: <schema name>
    catalog: <catalog name>
    http_path: <warehouse path>  # optional
  # OR
  dbt:
    enabled: true
    dbt_model: <name of dbt model that builds the cache table>
```

### Shape B — Multi-target sharing form (general datasets)

For datasets intended to be shared (BI tools, exports, multiple downstream consumers), use the list form. This lets one perspective deploy to multiple warehouses or as multiple object types simultaneously.

```yaml
delivery:
  - snowflake:
      target: <view | table | dynamic_table | interactive_table>
      name: <name>
      schema: <schema>
      database: <db>
      warehouse: <wh>
      table_settings:                    # if target = table
        transient: true
        cluster_by: <comma-separated keys>
      dynamic_table_settings:            # if target = dynamic_table
        lag:
          num: 5
          units: minutes
        downstream: false
        refresh_mode: AUTO               # AUTO | FULL | INCREMENTAL
        initialize: ON_CREATE            # ON_CREATE | ON_SCHEDULE
        cluster_by: <keys>
      enabled: true
  - databricks:
      target: <view | table>
      name: <name>
      schema: <schema>
      catalog: <catalog>
      http_path: <warehouse path>
      table_settings:                    # if target = table
        cluster_by: <keys>
      enabled: true
```

The list form does **not** support `use_for_cache`. If you need both cache routing and direct sharing, create two perspectives — one in cache-form, one in list-form — pointing to the same underlying logic.

## Delivery Targets by Warehouse

| Warehouse | Targets supported | Auto-refresh option |
|---|---|---|
| Snowflake | view, table, dynamic_table, interactive_table | dynamic_table (refresh_mode: AUTO) |
| Databricks | view, table | None native — refresh via dbt or external orchestration |
| dbt | (model) | Refresh on dbt run |

For Databricks aggregate caches, the typical pattern is to use dbt as the orchestrator (`use_for_cache: dbt`) since Databricks doesn't have a native auto-refreshing dynamic-table equivalent.

## Use_for_cache Values

| Value | Meaning |
|---|---|
| `snowflake` | Honeydew expects a Snowflake table at the configured location. Routes matching queries to it. |
| `databricks` | Honeydew expects a Databricks table at the configured location. Routes matching queries to it. |
| `dbt` | Honeydew expects a dbt model to materialize the table; routing engine uses table-update-time to detect cache validity. |

In all cases, the table must physically exist in the warehouse for routing to occur. A perspective configured with `use_for_cache` but not deployed will not be used.

## Cache Matching Rules (summary)

Aggregate routing requires:

1. **Group match** — the user query's groups are derivable from the cache's groups, either by exact match, partial-group roll-up (additive metrics only), or entity-key projection (any attribute on an entity whose key is in the cache).
2. **Filter match** — the cache's filters are a subset of the user query's filters. Cache filters narrow what the cache can serve; user-query filters can be additional.
3. **Domain match** — cache and user query are in the same domain (or at least share the same source filters).

The fewer filters a cache has, the more queries it can serve. Prefer scoping via domain over scoping via cache filters.

## Metric Additivity Reference

| Aggregation | Additive? | Cache behavior |
|---|---|---|
| `COUNT(*)` | Yes | Auto-detected, full roll-up |
| `SUM(x)` | Yes | Auto-detected, full roll-up |
| `MIN(x)`, `MAX(x)` | Yes | Auto-detected, full roll-up |
| `COUNT(DISTINCT x)` | No | Exact-match groups only |
| `AVG(x)` | No | Exact-match groups only |
| `STDDEV(x)`, `MEDIAN(x)`, percentiles | No | Exact-match groups only |
| `APPROX_COUNT_DISTINCT(x)` | Approximate | Exact-match groups only (HLL roll-up coming) |
| Filtered aggregations: `SUM(x) FILTER (...)` | Yes if base is additive | Same as base aggregation |
| Derived metrics (`a / b`, `a - b`) | Depends on operands | Set `rollup` explicitly |

For derived metrics that are mathematically additive but Honeydew can't auto-detect, set the `rollup` field on the metric definition (`rollup: sum`). For non-additive metrics, set `rollup: no_rollup` to make intent explicit.

## Querying a Perspective via SQL Interface

Once deployed, dynamic datasets are queryable via the SQL interface as if they were tables in a `dynamic_datasets` schema:

```sql
SELECT
  "destinations.country",
  AGG("bookings.confirmed_revenue") AS revenue
FROM dynamic_datasets.executive_kpi_dashboard
GROUP BY 1
```

Aggregate caches are typically not queried directly — Honeydew routes queries on entities to them transparently.

## Common Quick-Reference Pairs

**Daily aggregate cache (entity-key form, recommended):**
```yaml
attributes:
  - <dim_entity>.<dim_entity_key>     # not <fact>.<fk_to_dim>
  - date.date                         # not <fact>.<date_field>
metrics:
  - <fact>.count
  - <fact>.<sum_metric_1>
  - <fact>.<sum_metric_2>
delivery:
  use_for_cache: <warehouse>
  <warehouse>:
    enabled: true
    target: table
    name: agg_<fact>_by_<dim>_date
    ...
```

**Domain-scoped cache:**
```yaml
domain: <domain_name>
attributes: [<dim>.<key>, date.date]
metrics: [<fact>.count, ...]
delivery:
  use_for_cache: <warehouse>
  ...
```

**Sharing dataset (live view):**
```yaml
attributes: [<entity>.<attr>, ...]
metrics: [<entity>.<metric>, ...]
filters: [<filter expression>]
delivery:
  - <warehouse>:
      target: view
      name: <view_name>
      schema: <schema>
      enabled: true
```
