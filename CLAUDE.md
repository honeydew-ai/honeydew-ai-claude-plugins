# Honeydew AI Plugins for Coding Agents

## Repo Structure

```
plugins/
  data-analysis-tools/        # Query, filtering skills
  semantic-modeling-tools/     # Entity, attribute, metric, relation, domain, validation, exploration skills
```

Each plugin has mirrored `.claude-plugin/`, `.cursor-plugin/`, and `.github/plugin/` directories containing `plugin.json` and `.mcp.json`. The Cursor variants add `displayName` and `logo` fields. The GitHub Copilot variants add a `skills` array and `repository` field. A root-level GitHub Copilot marketplace is at `.github/plugin/marketplace.json`.

## Version Bump Checklist

When releasing a new version, update **all** of these files:

1. `CHANGELOG.md` — add a new entry at the top (format: `## [X.Y.Z] - YYYY-MM-DD`)
2. `.claude-plugin/marketplace.json` — `metadata.version` + each plugin's `version`
3. `.cursor-plugin/marketplace.json` — `metadata.version` + each plugin's `version`
4. `.github/plugin/marketplace.json` — `metadata.version` + each plugin's `version`
5. `plugins/data-analysis-tools/.claude-plugin/plugin.json`
6. `plugins/data-analysis-tools/.cursor-plugin/plugin.json`
7. `plugins/data-analysis-tools/.github/plugin/plugin.json`
8. `plugins/semantic-modeling-tools/.claude-plugin/plugin.json`
9. `plugins/semantic-modeling-tools/.cursor-plugin/plugin.json`
10. `plugins/semantic-modeling-tools/.github/plugin/plugin.json`
11. `gemini-extension.json` — `version`

## Skill Conventions

- Each skill lives in `plugins/<plugin>/skills/<skill-name>/`
- `.cursor/skills/` and `.gemini/skills/` contain relative symlinks to every skill directory.
  When adding, renaming, or deleting a skill, update the symlinks in both:
  - `.cursor/skills/`: `ln -s ../../plugins/<plugin>/skills/<skill-name>/ .cursor/skills/<skill-name>`
  - `.gemini/skills/`: `ln -s ../../plugins/<plugin>/skills/<skill-name>/ .gemini/skills/<skill-name>`
- `SKILL.md` (uppercase) is required — has YAML frontmatter with `name` and `description`
- Optional companion files: `examples.md`, `reference.md` (lowercase)
- Field references always use `entity.field_name` (fully qualified)
- YAML object names use `snake_case`; display names use Title Case
- Cross-reference other skills by name in backticks (e.g., "see the **filtering** skill")
- Creation skills must end with a "MANDATORY: Validate After Creating" section pointing to the `validation` skill
- After `create_object`/`update_object`, always display the `ui_url` from the response

## .claude-plugin vs .cursor-plugin vs .github/plugin

- `plugin.json`: Cursor adds `displayName` and `logo`; GitHub adds `skills` array and `repository`; Claude has neither
- `.mcp.json`: identical across Claude and Cursor (GitHub does not use `.mcp.json`)
- `marketplace.json`: all three (`.claude-plugin/`, `.cursor-plugin/`, `.github/plugin/`) must be kept in sync

## CI

- GitHub Actions validates YAML frontmatter on PRs (uses `bun` + `.github/scripts/validate-frontmatter.ts`)
