# Metric Reference

## Aggregation Functions

| Category               | Functions                                                                                                    |
| ---------------------- | ------------------------------------------------------------------------------------------------------------ |
| **Numeric**            | `AVG`, `COUNT`, `MAX`, `MIN`, `MEDIAN`, `SUM`                                                                |
| **Max/min by column**  | `MIN_BY`, `MAX_BY`                                                                                           |
| **Concatenate**        | `LISTAGG`                                                                                                    |
| **Statistics**         | `CORR`, `COVAR_POP`, `COVAR_SAMP`, `MODE`, `STDDEV`, `STDDEV_POP`, `VAR_POP`, `VAR_SAMP`, `KURTOSIS`, `SKEW` |
| **Approximate**        | `APPROX_COUNT_DISTINCT`, `APPROXIMATE_SIMILARITY`, `APPROX_PERCENTILE`                                       |
| **Bitwise**            | `BITAND_AGG`, `BITOR_AGG`, `BITXOR_AGG`                                                                      |
| **Boolean**            | `BOOLAND_AGG`, `BOOLOR_AGG`, `BOOLXOR_AGG`                                                                   |
| **Text summarization** | `AI_SUMMARIZE_AGG`, `AI_AGG`                                                                                 |

## Composing from Existing Metrics

Honeydew accepts named metric references nearly everywhere you'd otherwise write a raw
aggregation — inside `FILTER (WHERE ...)`, inside `GROUP BY (...)` (both fixed and
nested), and as operands in derived arithmetic. Whenever an existing metric can be the
building block of your new metric, **prefer the named-metric form**. It expresses business
intent, inherits future changes to the base metric, and keeps the model DRY.

| New metric pattern                            | Preferred (named-metric form)                       | Raw fallback                                          |
| --------------------------------------------- | --------------------------------------------------- | ----------------------------------------------------- |
| Filtered version of a base metric             | `orders.revenue FILTER (WHERE orders.region='US')`  | `SUM(orders.amount) FILTER (WHERE orders.region='US')` |
| Same metric at a fixed grouping               | `orders.revenue GROUP BY (orders.region)`           | `SUM(orders.amount) GROUP BY (orders.region)`         |
| Same metric inside a nested grouping (`*, x`) | `orders.revenue GROUP BY (*, orders.order_date)`    | `SUM(orders.amount) GROUP BY (*, orders.order_date)`  |
| Distinct count of a related entity            | `customers.count FILTER (WHERE orders.order_id IS NOT NULL)` | `COUNT(DISTINCT orders.customer_id)`        |
| Arithmetic on existing metrics                | `orders.revenue - orders.cost`                      | (no raw equivalent)                                   |

The raw fallback is the right choice **only** when no named metric for the base
aggregation exists, or — for cross-entity counts — when there's no relation between the
two entities. Otherwise, prefer the named-metric form.

> Most imported entities auto-generate a `count` metric. Check before reaching for
> `COUNT(*)` or `COUNT(entity.key_field)` — `entity.count` is almost always already there.

### Filtered aggregations

Apply a filter to any named metric or raw aggregation with `FILTER (WHERE ...)`:

```sql
-- Preferred: named-metric form
orders.revenue FILTER (WHERE orders.color = 'red')
orders.count FILTER (WHERE orders.status = 'completed')

-- Even better: also reference a boolean calc attribute as the predicate when one exists
orders.count FILTER (WHERE orders.is_completed)
bookings.count FILTER (WHERE bookings.is_cancelled)
hosts.count FILTER (WHERE hosts.is_top_rated)

-- Raw aggregation fallback
SUM(orders.price) FILTER (WHERE orders.color = 'red')
```

The reuse principle applies to filter predicates the same way it applies to base
aggregations. If a boolean calculated attribute already encodes the predicate (e.g.
`bookings.is_cancelled = bookings.status = 'cancelled'`), reference it by name instead
of inlining the comparison. The metric reads as business intent and inherits any future
changes to the attribute definition.

> For complete filter expression syntax (comparisons, strings, SEARCH, dates, booleans, combined conditions) and date handling functions, see the **filtering** skill.

### Fixed and nested grouping

Wrap any named metric or raw aggregation with `GROUP BY (...)` to lock its grain. Use
`GROUP BY (*, dim)` when you want the inner grouping to inherit the user's current
context plus an additional dimension (the dynamic-grouping recipe — inner half of
average-daily-revenue, peak-daily-revenue, and similar metrics).

```sql
-- Preferred: named-metric form
orders.revenue GROUP BY (orders.customer_id)
orders.revenue GROUP BY (*, orders.order_date)
orders.count GROUP BY (*, orders.order_date)

-- Raw aggregation fallback
SUM(orders.amount) GROUP BY (orders.customer_id)
SUM(orders.amount) GROUP BY (*, orders.order_date)
```

### Cross-entity distinct counts

When the question is "how many distinct X are reachable from this set" and X is a
related entity, prefer the related entity's `count` metric over `COUNT(DISTINCT)` on the
foreign-key column. **Crucially: add a `FILTER` that references a non-null column on the
source entity** (typically the source entity's primary key). Without that filter, the
Honeydew optimizer may prune the join entirely when the metric is queried on its own,
and the result becomes the related entity's standalone total — not what the metric
description promises.

```sql
-- Preferred: filter forces the join, semantic always matches description
users.count FILTER (WHERE bookings.booking_id IS NOT NULL)
properties.count FILTER (WHERE bookings.booking_id IS NOT NULL)

-- DON'T do this — looks right, breaks under standalone queries
users.count                            -- optimizer prunes bookings join → returns ALL users (124K), not just users with bookings (54K)

-- DON'T do this either — the predicate evaluates as a global scalar, not per-row
users.count FILTER (WHERE bookings.count > 0)   -- bookings.count > 0 is true globally, filter is no-op

-- Raw fallback when the named-metric form isn't viable
COUNT(DISTINCT bookings.user_id)
```

**Why the filter matters:** in `users.count FILTER (WHERE bookings.booking_id IS NOT NULL)`,
the FILTER predicate references `bookings.booking_id` (a per-row column on bookings).
This forces Honeydew to actually join users to bookings on the relation key — the SQL
becomes `LEFT JOIN bookings ON bookings.user_id = users.user_id`, then filter, then count
distinct users. The result correctly equals "users with at least one booking."

The named form requires a relation between the source entity and the target entity. If
the relation isn't there or doesn't carry the join semantics you need, fall back to the
explicit `COUNT(DISTINCT)` form.

## Text Summarization

- `AI_SUMMARIZE_AGG(account.churn_reason)` — get a summary of a text column
- `AI_AGG(reservation.reviews, 'Describe common complaints')` — reduce text with a natural language instruction

## Data Types

Every metric has a data type. Choose based on the aggregation result:

| Data Type   | When to use                                                 |
| ----------- | ----------------------------------------------------------- |
| `float`     | **Default for most metrics.** SUM, AVG, ratios, percentages |
| `number`    | Integer results: COUNT, COUNT DISTINCT                      |
| `string`    | Text aggregations: LISTAGG, AI_SUMMARIZE_AGG, AI_AGG        |
| `bool`      | Boolean aggregations: BOOLAND_AGG, BOOLOR_AGG               |
| `date`      | Date aggregations: MIN/MAX on dates                         |
| `timestamp` | Timestamp aggregations                                      |
| `time`      | Time aggregations                                           |

> **Default to `float`** unless the metric is clearly a count (use `number`) or text (use `string`).

## Metric Types

| Type                   | Purpose                            | Example                                |
| ---------------------- | ---------------------------------- | -------------------------------------- |
| **Basic**              | Standard SQL aggregation           | `SUM(orders.amount)`                   |
| **Derived**            | Arithmetic on existing metrics     | `orders.revenue - orders.cost`         |
| **Filtered**           | Aggregation with fixed WHERE       | `orders.revenue FILTER (WHERE ...)` or `SUM(orders.price) FILTER (WHERE ...)` |
| **Fixed Grouping**     | Always grouped by a dimension      | `orders.revenue GROUP BY (orders.region)` or `SUM(orders.amount) GROUP BY (orders.region)` |
| **Nested Aggregation** | Aggregation of grouped aggregation | `AVG(orders.revenue GROUP BY (*, orders.order_date))` |

## Format Strings

Use `format_string` to control how metric values display in BI tools. Uses spreadsheet-style format expressions (Excel syntax). See https://customformats.com/ to help build expressions.

| Format      | Renders as | Use for                          |
| ----------- | ---------- | -------------------------------- |
| `#,##0`     | 1,234      | Integer with thousands separator |
| `#,##0.00`  | 1,234.56   | Two decimal places               |
| `$#,##0`    | $1,234     | Currency without decimals        |
| `$#,##0.00` | $1,234.56  | Currency with decimals           |
| `0%`        | 12%        | Percentage without decimals      |
| `0.00%`     | 12.34%     | Percentage with decimals         |
