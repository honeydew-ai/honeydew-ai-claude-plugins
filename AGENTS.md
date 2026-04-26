# Honeydew AI Plugins for Coding Agents

## Repo Structure

```
skills/                          # All 9 skills (single honeydew-ai plugin)
  filtering/
  query/
  attribute-creation/
  domain-creation/
  entity-creation/
  metric-creation/
  model-exploration/
  relation-creation/
  validation/
hooks/                           # PreToolUse hook scripts
assets/                          # logo.svg
plugins/honeydew-ai/             # Codex marketplace wrapper path (symlinks to root plugin files)
.agents/plugins/                 # Codex marketplace config (marketplace.json)
.claude-plugin/                  # Claude plugin config (plugin.json, .mcp.json, marketplace.json)
.cursor-plugin/                  # Cursor plugin config (plugin.json, .mcp.json, marketplace.json)
.github/plugin/                  # GitHub Copilot config (plugin.json, marketplace.json)
.codex-plugin/                   # Codex plugin config (plugin.json)
.mcp.json                        # Root-level MCP config (honeydew + honeydew-docs servers)
```

The repo root IS the single `honeydew-ai` plugin. Codex marketplace entries must point to a non-empty plugin path, so `plugins/honeydew-ai/` is a wrapper made of relative symlinks back to the canonical root plugin files. `.cursor/skills/` and `.gemini/skills/` contain symlinks to `skills/<name>`.

## Version Bump Checklist

When releasing a new version, update **all** of these files:

1. `CHANGELOG.md` — add a new entry at the top (format: `## [X.Y.Z] - YYYY-MM-DD`)
2. `.claude-plugin/marketplace.json` — `metadata.version` + plugin `version`
3. `.cursor-plugin/marketplace.json` — `metadata.version` + plugin `version`
4. `.github/plugin/marketplace.json` — `metadata.version` + plugin `version`
5. `.agents/plugins/marketplace.json` — marketplace entry if install policy/category/source changes (Codex source path must stay `./plugins/honeydew-ai`)
6. `.claude-plugin/plugin.json` — `version`
7. `.cursor-plugin/plugin.json` — `version`
8. `.github/plugin/plugin.json` — `version`
9. `.codex-plugin/plugin.json` — `version`
10. `gemini-extension.json` — `version`

## Skill Conventions

- Each skill lives in `skills/<skill-name>/`
- `.cursor/skills/` and `.gemini/skills/` contain relative symlinks to every skill directory.
  When adding, renaming, or deleting a skill, update the symlinks in both:
  - `.cursor/skills/`: `ln -s ../../skills/<skill-name>/ .cursor/skills/<skill-name>`
  - `.gemini/skills/`: `ln -s ../../skills/<skill-name> .gemini/skills/<skill-name>`
- `SKILL.md` (uppercase) is required — has YAML frontmatter with `name` and `description`
- Optional companion files: `examples.md`, `reference.md` (lowercase)
- Field references always use `entity.field_name` (fully qualified)
- YAML object names use `snake_case`; display names use Title Case
- Cross-reference other skills by name in backticks (e.g., "see the **filtering** skill")
- Creation skills must end with a "MANDATORY: Validate After Creating" section pointing to the `validation` skill
- After `create_object`/`update_object`, always display the `ui_url` from the response

## .claude-plugin vs .cursor-plugin vs .github/plugin vs .codex-plugin

- `plugin.json`: Cursor adds `displayName` and `logo`; GitHub adds `skills` array and `repository`; Claude has neither
- Codex uses `.codex-plugin/plugin.json` with `skills`, `mcpServers`, and `interface` metadata
- Codex marketplace metadata lives in `.agents/plugins/marketplace.json`
- `.mcp.json`: present in Claude, Cursor, and root (`.mcp.json`); GitHub does not use `.mcp.json`
- `marketplace.json`: all three (`.claude-plugin/`, `.cursor-plugin/`, `.github/plugin/`) must be kept in sync

## CI

- GitHub Actions validates YAML frontmatter on PRs (uses `bun` + `.github/scripts/validate-frontmatter.ts`)
