# Changelog

All notable changes to the Honeydew AI Plugins for Coding Agents are documented in this file.

## [0.4.1] - 2026-03-02

### Added

- **Distinct values tip** in the query skill — how to retrieve unique values for a field by combining it as an attribute with a COUNT metric
- Cross-references from the filtering skill (discover filter values) and attribute-creation skill (validate attribute output) to the new tip

## [0.4.0] - 2026-03-01

### Changed

- Updated MCP tool names and added warehouse discovery tools

## [0.3.1] - 2026-03-01

### Changed

- Removed `rollup` and `hidden` fields from all skill documentation, YAML templates, and examples — these fields are not needed for AI-driven modeling

## [0.3.0] - 2026-02-27

### Added

- **Honeydew documentation MCP** (`honeydew-docs`) bundled out of the box in both plugins — provides access to Honeydew documentation search with no authentication required
- **Documentation Lookup** sections in 7 skills (model-exploration, entity-creation, relation-creation, domain-creation, metric-creation, attribute-creation, query) — guiding when and what to search in the docs

## [0.2.0] - 2026-02-27

### Added

- **domain-creation** skill — create, update, and delete Honeydew domains with entity selection, field selectors, semantic filters, source filters, and parameter overrides
- Domain validation section in the **validation** skill

## [0.1.1] - 2026-02-25

### Added

- `import_tables` tool as a new entity creation method in the entity-creation skill

## [0.1.0] - 2026-02-24

### Added

- Plugin marketplace setup with `marketplace.json`
- **Semantic Modeling Tools** plugin with 6 skills:
  - **model-exploration** — explore entities, search fields, inspect relationships
  - **entity-creation** — create entities from data warehouse tables
  - **relation-creation** — define joins between entities with type, cardinality, and conditions
  - **attribute-creation** — create calculated attributes (dimensions) with SQL expressions
  - **metric-creation** — create business metrics (aggregations) like totals, averages, and ratios
  - **validation** — post-creation validation with type-specific sanity checks
- **Data Analysis Tools** plugin with 2 skills:
  - **query** — structured YAML perspectives, natural language questions, and deep analysis
  - **filtering** — advanced filter syntax for comparisons, dates, nulls, and full-text search
