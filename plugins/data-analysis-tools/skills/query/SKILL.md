---
name: query
description: Use when the user wants to query, analyze, or explore data through the Honeydew semantic layer. Covers structured queries, natural-language questions, and multi-step deep analysis.
---

## Overview

Honeydew provides three ways to query data through the semantic layer. Each method suits a different situation — pick the right one based on how well you understand the model and how complex the question is.

| Method               | Tool                                             | Best For                                                 |
| -------------------- | ------------------------------------------------ | -------------------------------------------------------- |
| **Structured query** | `get_data_from_fields` / `get_sql_from_fields`   | You know the exact fields. Deterministic, full control.  |
| **Natural language** | `ask_question_get_data` / `ask_question_get_sql` | Plain English question. Single query, fast answer.       |
| **Deep analysis**    | `ask_deep_analysis_question`                     | Complex, multi-step, "why" questions. Agentic reasoning. |

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

- You don't know the field names and the user is asking in plain English
- The question requires multi-step reasoning or investigation

**How it works:**

- `get_data_from_fields` — executes the query and returns data rows
- `get_sql_from_fields` — returns the generated SQL without executing (useful for review, debugging, or handing off to other tools)

Both take the same field parameters.

### 2. Natural Language (`ask_question_get_data` / `ask_question_get_sql`)

**Use when:**

- The user asks a question in plain English
- It's a single, straightforward question that maps to one query
- You don't know or aren't sure of the exact field names
- The user wants a quick answer without worrying about model details

**Do NOT use when:**

- The question involves multiple steps, comparisons across time periods, or root cause analysis
- You already know the exact fields — use a structured query instead for precision

**How it works:**

- `ask_question_get_data` — translates the question to SQL, executes it, and returns results
- `ask_question_get_sql` — translates the question to SQL and returns the SQL only

### 3. Deep Analysis (`ask_deep_analysis_question`)

**Use when:**

- The question requires multiple steps or investigative reasoning
- The user asks "why" something happened (e.g., "why did revenue drop in Q3?")
- The user wants trend analysis, anomaly detection, or root cause investigation
- The question is open-ended and may require looking at the data from multiple angles
- Follow-up questions build on prior analysis (use `conversation_id`)

**Do NOT use when:**

- The question is simple and can be answered with a single query
- You just need to fetch specific data points

---

## Decision Flow

```
User asks a data question
    │
    ├─► Do you know the exact field names?
    │       │
    │       ├─► YES → get_data_from_fields (structured, deterministic)
    │       │
    │       └─► NO → Can you quickly discover them?
    │               │
    │               ├─► YES → list_entities / get_entity → then get_data_from_fields
    │               │
    │               └─► NO → ask_question_get_data (let Honeydew resolve fields)
    │
    ├─► Is it a simple, single-query question in plain English?
    │       └─► YES → ask_question_get_data
    │
    ├─► Does it require investigation, "why", trends, or multi-step reasoning?
    │       └─► YES → ask_deep_analysis_question
    │
    └─► Does the user want to see the SQL without running it?
            ├─► From known fields → get_sql_from_fields
            └─► From plain English → ask_question_get_sql
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
4. `search_model` with a keyword — find fields across the model

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

## Method 2: Natural Language Query

### ask_question_get_data

Call with:

- `question` (required): the question in plain English
- `max_rows` (required): maximum number of rows to return
- `domain` (required): domain name for query context

```
question: "What are the top 10 neighbourhoods by number of listings?"
max_rows: 10
domain: "my_domain"
```

Returns the query results directly.

### ask_question_get_sql

Call with:

- `question` (required): the question in plain English
- `domain` (required): domain name for query context

```
question: "What are the top 10 neighbourhoods by number of listings?"
domain: "my_domain"
```

Returns the generated SQL without executing.

### Tips for Natural Language Queries

- Be specific: "average price per room type" is better than "show me prices"
- Mention the entity/domain if ambiguous: "average listing price" not just "average price"
- Include time ranges explicitly: "in the last 12 months" or "for 2024"
- Specify limits: "top 10", "bottom 5"

---

## Method 3: Deep Analysis

### ask_deep_analysis_question

Call with:

- `question` (required): the analysis question
- `domain` (required): domain name for query context
- `conversation_id` (optional): ID from a previous deep analysis call, for follow-up questions

```
question: "Analyze the relationship between host response time and review scores. Are there significant patterns?"
domain: "my_domain"
```

Returns:

- Markdown analysis report with findings
- Supporting data
- Suggested follow-up questions
- `conversation_id` for continuing the conversation

### After Deep Analysis: Display the UI Link

After a successful `ask_deep_analysis_question` call, the response includes a `ui_url` field. **Always display this URL to the user** so they can view the full analysis in the Honeydew application.

### Follow-up Questions

Use `conversation_id` from the previous response to ask follow-up questions that build on the prior analysis:

```
question: "Now break this down by room type — does the pattern hold across all types?"
domain: "my_domain"
conversation_id: "<id from previous response>"
```

### Good Deep Analysis Questions

- "Why did the average review score drop for listings in Brooklyn?"
- "What factors most influence listing price? Analyze the key drivers."
- "Compare superhost vs non-superhost performance across all metrics."
- "Identify unusual patterns in listing availability over the past year."
- "What are the characteristics of top-performing listings?"

---

## Combining Methods

For complex tasks, combine methods in sequence:

1. **Discover** — Use `list_entities` / `get_entity` to understand the model
2. **Explore** — Use `ask_question_get_data` to get a quick feel for the data
3. **Drill down** — Use `get_data_from_fields` for precise, targeted queries
4. **Investigate** — Use `ask_deep_analysis_question` for root cause or trend analysis

### Example Workflow

User: "Help me understand pricing patterns for Airbnb listings."

1. Discover entities: `list_entities` → find `detailed_listings`
2. Explore fields: `get_entity` for `detailed_listings` → find `price`, `room_type`, `neighbourhood_cleansed`
3. Quick overview: `ask_question_get_data` → "What is the average listing price by room type?"
4. Targeted query: `get_data_from_fields` → price distribution by neighbourhood for Entire homes only
5. Deep dive: `ask_deep_analysis_question` → "What factors most influence listing price? Analyze correlations with room type, location, amenities, and reviews."

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
- **Use natural language for speed** — when the user asks a quick question and you don't need to control every detail
- **Use deep analysis for insight** — when the question is about "why" or requires investigating multiple dimensions
- **Paginate large results** — use `limit` and `offset` in `get_data_from_fields` to avoid overwhelming output
- **Show SQL when debugging** — use `get_sql_from_fields` or `ask_question_get_sql` to inspect the generated query
- **Reference fields correctly** — always use `entity.field_name` syntax in field parameters
