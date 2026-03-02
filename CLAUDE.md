# Honeydew AI Plugins for Coding Agents

## Repo Structure

```
plugins/
  data-analysis-tools/        # Query, filtering skills
  semantic-modeling-tools/     # Entity, attribute, metric, relation, domain, validation, exploration skills
```

Each plugin has mirrored `.claude-plugin/` and `.cursor-plugin/` directories containing `plugin.json` and `.mcp.json`. The Cursor variants add `displayName` and `logo` fields.

## Version Bump Checklist

When releasing a new version, update **all** of these files:

1. `CHANGELOG.md` — add a new entry at the top (format: `## [X.Y.Z] - YYYY-MM-DD`)
2. `.claude-plugin/marketplace.json` — `metadata.version` + each plugin's `version`
3. `.cursor-plugin/marketplace.json` — `metadata.version` + each plugin's `version`
4. `plugins/data-analysis-tools/.claude-plugin/plugin.json`
5. `plugins/data-analysis-tools/.cursor-plugin/plugin.json`
6. `plugins/semantic-modeling-tools/.claude-plugin/plugin.json`
7. `plugins/semantic-modeling-tools/.cursor-plugin/plugin.json`

## Skill Conventions

- Each skill lives in `plugins/<plugin>/skills/<skill-name>/`
- `SKILL.md` (uppercase) is required — has YAML frontmatter with `name` and `description`
- Optional companion files: `examples.md`, `reference.md` (lowercase)
- Field references always use `entity.field_name` (fully qualified)
- YAML object names use `snake_case`; display names use Title Case
- Cross-reference other skills by name in backticks (e.g., "see the **filtering** skill")
- Creation skills must end with a "MANDATORY: Validate After Creating" section pointing to the `validation` skill
- After `create_object`/`update_object`, always display the `ui_url` from the response

## .claude-plugin vs .cursor-plugin

- `plugin.json`: Cursor adds `displayName` and `logo`; Claude does not
- `.mcp.json`: identical across both platforms
- `marketplace.json`: both must be kept in sync

## CI

- GitHub Actions validates YAML frontmatter on PRs (uses `bun` + `.github/scripts/validate-frontmatter.ts`)
