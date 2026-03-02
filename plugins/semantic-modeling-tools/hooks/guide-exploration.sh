#!/bin/bash
set -euo pipefail

cat <<'EOF'
{"systemMessage": "You are exploring the Honeydew semantic model. If you have not already loaded the 'semantic-modeling-tools:model-exploration' skill, invoke the Skill tool with skill 'semantic-modeling-tools:model-exploration' to get guidance on discovery workflows and available MCP tools."}
EOF
