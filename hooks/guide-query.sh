#!/bin/bash
set -euo pipefail

input=$(cat)
tool_name=$(printf '%s' "$input" | jq -r '.tool_name // ""')

case "$tool_name" in
  *ask_deep_analysis*)
    cat <<'EOF'
{"systemMessage": "You are about to run a deep analysis query. If you have not already loaded the 'honeydew-ai:query' skill, invoke the Skill tool with skill 'honeydew-ai:query' BEFORE proceeding. The skill explains the three query methods (structured, natural language, deep analysis) and their correct parameters."}
EOF
    ;;
  *get_data_from_fields*|*get_sql_from_fields*)
    cat <<'EOF'
{"systemMessage": "You are about to query data through Honeydew. If you have not already loaded the 'honeydew-ai:query' skill, invoke the Skill tool with skill 'honeydew-ai:query' BEFORE proceeding. The skill explains the three query methods and their correct parameters. For filter expressions, also load 'honeydew-ai:filtering'."}
EOF
    ;;
  *)
    cat <<'EOF'
{"systemMessage": "You are about to query data through Honeydew. If you have not already loaded the 'honeydew-ai:query' skill, invoke the Skill tool with skill 'honeydew-ai:query' BEFORE proceeding. The skill explains the three query methods and their correct parameters."}
EOF
    ;;
esac
