#!/bin/bash
set -euo pipefail

cat <<'EOF'
{"systemMessage": "You are exploring the Honeydew semantic model. If you have not already loaded the 'honeydew-ai:model-exploration' skill, invoke the Skill tool with skill 'honeydew-ai:model-exploration' to get guidance on discovery workflows and available MCP tools."}
EOF
