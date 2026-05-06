#!/usr/bin/env bash
# Build a release zip for upload to the claude.ai private marketplace.
#
# Produces dist/honeydew-ai-<version>.zip from the repo root plugin, with
# the .claude-plugin/ directory and other plugin files at the zip root
# (the layout claude.ai expects).
#
# Whitelist-based: only files matching the patterns below are included. To
# ship a new kind of file, add it to one of the copy_* functions.
#
# Usage: ./scripts/build-release.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${REPO_ROOT}/dist"

command -v zip >/dev/null 2>&1 || { echo "error: 'zip' is required" >&2; exit 1; }

read_version() {
  local plugin_json="$1"
  sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${plugin_json}" | head -n1
}

# Copy a file if the source exists. Creates the destination directory.
copy_if_exists() {
  local src="$1" dst="$2"
  if [[ -f "${src}" ]]; then
    mkdir -p "$(dirname "${dst}")"
    cp "${src}" "${dst}"
  fi
}

# Copy every file in src_dir matching one of the given globs into dst_dir.
# Usage: copy_glob <src_dir> <dst_dir> <glob> [<glob>...]
copy_glob() {
  local src_dir="$1" dst_dir="$2"; shift 2
  [[ -d "${src_dir}" ]] || return 0
  local pattern matched=0
  for pattern in "$@"; do
    shopt -s nullglob
    local matches=( "${src_dir}"/${pattern} )
    shopt -u nullglob
    for f in "${matches[@]}"; do
      [[ -f "${f}" ]] || continue
      mkdir -p "${dst_dir}"
      cp "${f}" "${dst_dir}/"
      matched=1
    done
  done
  return 0
}

stage_plugin() {
  local src="$1" stage="$2"

  # Manifest: only plugin.json belongs in .claude-plugin/ per Claude Code docs.
  copy_if_exists "${src}/.claude-plugin/plugin.json" "${stage}/.claude-plugin/plugin.json"

  # MCP config: .mcp.json must sit at the plugin root (not inside .claude-plugin/).
  copy_if_exists "${src}/.mcp.json" "${stage}/.mcp.json"

  # Hooks: JSON config + shell scripts.
  copy_glob "${src}/hooks" "${stage}/hooks" "*.json" "*.sh"

  # Assets: logos / images.
  copy_glob "${src}/assets" "${stage}/assets" "*.svg" "*.png" "*.jpg" "*.jpeg"

  # Skills: each subdir contributes its markdown files.
  if [[ -d "${src}/skills" ]]; then
    for skill_dir in "${src}/skills"/*/; do
      [[ -d "${skill_dir}" ]] || continue
      local name
      name="$(basename "${skill_dir}")"
      copy_glob "${skill_dir%/}" "${stage}/skills/${name}" "*.md"
    done
  fi
}

plugin_json="${REPO_ROOT}/.claude-plugin/plugin.json"
if [[ ! -f "${plugin_json}" ]]; then
  echo "error: missing ${plugin_json}" >&2
  exit 1
fi

version="$(read_version "${plugin_json}")"
if [[ -z "${version}" ]]; then
  echo "error: could not read version from ${plugin_json}" >&2
  exit 1
fi

rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}"

zip_path="${OUT_DIR}/honeydew-ai-${version}.zip"
echo "==> Building ${zip_path}"

stage="$(mktemp -d)"
trap 'rm -rf "${stage}"' EXIT

stage_plugin "${REPO_ROOT}" "${stage}"
(cd "${stage}" && zip -rq "${zip_path}" .)

rm -rf "${stage}"
trap - EXIT

echo "    $(cd "${OUT_DIR}" && ls -lh "$(basename "${zip_path}")" | awk '{print $5, $9}')"
echo
echo "Done. Artifacts:"
ls -1 "${OUT_DIR}"
