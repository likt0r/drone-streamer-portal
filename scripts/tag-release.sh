#!/usr/bin/env bash
# =============================================================================
# tag-release.sh – Create and push a version tag from package.json
#
# Usage:
#   bash scripts/tag-release.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Read version from package.json
VERSION="v$(node -p "require('${PROJECT_DIR}/package.json').version")"

echo "Version from package.json: ${VERSION}"

# Check tag doesn't already exist
if git -C "${PROJECT_DIR}" tag | grep -q "^${VERSION}$"; then
    echo "Error: tag ${VERSION} already exists." >&2
    exit 1
fi

# Confirm
read -r -p "Create and push tag ${VERSION}? [y/N] " CONFIRM
[[ "${CONFIRM}" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

git -C "${PROJECT_DIR}" tag "${VERSION}"
git -C "${PROJECT_DIR}" push origin "${VERSION}"

echo "✅ Tagged and pushed ${VERSION}"
echo "   CI will now build and publish the GitHub Release."
