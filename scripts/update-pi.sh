#!/usr/bin/env bash
# =============================================================================
# update-pi.sh – Raspberry Pi 4 update script for drone-streamer-portal
#
# Usage:
#   sudo bash scripts/update-pi.sh
#
# What this does:
#   1. Resolves the latest version of the drone streamer portal from GitHub.
#   2. Downloads and extracts the Vue build package over the current installation.
#   3. Sets the proper permissions to www-data.
# =============================================================================

set -euo pipefail

# ── Colour helpers ────────────────────────────────────────────────────────────
info()  { echo -e "\e[32m[INFO]\e[0m  $*"; }
warn()  { echo -e "\e[33m[WARN]\e[0m  $*"; }
error() { echo -e "\e[31m[ERROR]\e[0m $*" >&2; exit 1; }

WEB_ROOT="/var/www/drone-streamer-portal/dist"

[[ $EUID -ne 0 ]] && error "Please run as root: sudo bash $0"

# ── 1. Vue app – download latest release from GitHub ─────────────────────────
REPO="likt0r/drone-streamer-portal"

info "Resolving latest release from github.com/${REPO}…"
LATEST_TAG=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
    | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"\(.*\)".*/\1/')

if [[ -z "${LATEST_TAG}" ]]; then
    error "Could not resolve latest release tag. Check your internet connection or ensure a release has been published."
fi

info "Latest release: ${LATEST_TAG}"
PACKAGE_URL="https://github.com/${REPO}/releases/download/${LATEST_TAG}/drone-streamer-portal-${LATEST_TAG}.tar.gz"

info "Downloading Vue build package…"
TMP_WEB=$(mktemp -d)
curl -fsSL "${PACKAGE_URL}" -o "${TMP_WEB}/portal.tar.gz" \
    || error "Failed to download ${PACKAGE_URL}"

info "Evaluating existing installation..."
if [[ ! -d "${WEB_ROOT}" ]]; then
    warn "Web root ${WEB_ROOT} does not exist. Is the portal installed?"
    warn "Creating ${WEB_ROOT} anyway, but please consider running install-pi.sh instead."
fi

info "Extracting to ${WEB_ROOT}…"
mkdir -p "${WEB_ROOT}"
# Extract the new build directly over the previous one
tar -xzf "${TMP_WEB}/portal.tar.gz" -C "${WEB_ROOT}"
chown -R www-data:www-data "${WEB_ROOT}"
rm -rf "${TMP_WEB}"
info "Vue build (${LATEST_TAG}) deployed to ${WEB_ROOT}."

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
info "✅ Update complete!"
echo ""
echo "  Web root        : ${WEB_ROOT}"
echo ""
echo "  Access the portal at: http://$(hostname -I | awk '{print $1}')/"
