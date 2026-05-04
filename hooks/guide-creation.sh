#!/bin/bash
set -euo pipefail

input=$(cat)
tool_name=$(printf '%s' "$input" | jq -r '.tool_name // ""')
yaml_text=$(printf '%s' "$input" | jq -r '.tool_input.yaml_text // .tool_input.entity_yaml // ""')

skill_hint=""

case "$tool_name" in
  *create_context_item*|*update_context_item*)
    skill_hint="honeydew-ai:context-item-creation"
    ;;
  *import_tables*)
    skill_hint="honeydew-ai:entity-creation"
    ;;
  *create_entity*)
    skill_hint="honeydew-ai:entity-creation"
    ;;
  *create_object*|*update_object*)
    # Detect object type by searching yaml_text using jq (avoids newline issues)
    if printf '%s' "$input" | jq -e '.tool_input.yaml_text // "" | test("type:\\s*metric")' > /dev/null 2>&1; then
      skill_hint="honeydew-ai:metric-creation"
    elif printf '%s' "$input" | jq -e '.tool_input.yaml_text // "" | test("type:\\s*attribute")' > /dev/null 2>&1; then
      skill_hint="honeydew-ai:attribute-creation"
    elif printf '%s' "$input" | jq -e '.tool_input.yaml_text // "" | test("type:\\s*domain")' > /dev/null 2>&1; then
      skill_hint="honeydew-ai:domain-creation"
    elif printf '%s' "$input" | jq -e '.tool_input.yaml_text // "" | test("type:\\s*entity")' > /dev/null 2>&1; then
      skill_hint="honeydew-ai:entity-creation"
    elif printf '%s' "$input" | jq -e '.tool_input.yaml_text // "" | test("relations:")' > /dev/null 2>&1; then
      skill_hint="honeydew-ai:relation-creation"
    fi
    ;;
esac

if [ -n "$skill_hint" ]; then
  printf '{"systemMessage": "You are about to create or modify a Honeydew object. If you have not already loaded the relevant skill, invoke the Skill tool with skill '"'"'%s'"'"' BEFORE proceeding. The skill contains critical guidance on required fields, naming conventions, and correct YAML structure. After creation, always run the '"'"'honeydew-ai:validation'"'"' skill to verify the object works correctly."}\n' "$skill_hint"
else
  printf '%s\n' '{"systemMessage": "You are about to create or modify a Honeydew object. If you have not already loaded the relevant skill, invoke the appropriate Skill tool BEFORE proceeding. Available skills: honeydew-ai:metric-creation (metrics), honeydew-ai:attribute-creation (attributes), honeydew-ai:entity-creation (entities), honeydew-ai:relation-creation (relations), honeydew-ai:domain-creation (domains), honeydew-ai:context-item-creation (context items). After creation, always run honeydew-ai:validation."}'
fi
