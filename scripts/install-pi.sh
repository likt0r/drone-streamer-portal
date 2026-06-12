#!/usr/bin/env bash
# =============================================================================
# install-pi.sh – Install/update drone-streamer-portal on a Raspberry Pi
#
# Usage:
#   # Latest release from GitHub (no repo clone needed):
#   curl -fsSL https://raw.githubusercontent.com/likt0r/drone-streamer-portal/main/scripts/install-pi.sh | sudo bash
#
#   # Or from a checkout / with a locally built package:
#   sudo bash scripts/install-pi.sh
#   sudo bash scripts/install-pi.sh path/to/drone-streamer-portal_x.y.z_arm64.deb
#
# Everything (frontend, backend, MediaMTX, nginx site, systemd units) ships in
# one Debian package; apt resolves the system dependencies. Re-running this
# script updates an existing installation in place. A user-edited
# /opt/mediamtx/mediamtx.yml is preserved across updates.
# =============================================================================
set -euo pipefail

info()  { echo -e "\e[32m[INFO]\e[0m  $*"; }
error() { echo -e "\e[31m[ERROR]\e[0m $*" >&2; exit 1; }

REPO="likt0r/drone-streamer-portal"
ARCH="arm64"

[[ $EUID -ne 0 ]] && error "Please run as root: sudo bash $0"

DEB="${1:-}"

if [[ -z "${DEB}" ]]; then
    info "Resolving latest release from github.com/${REPO}…"
    LATEST_TAG=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
        | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"\(.*\)".*/\1/')
    [[ -n "${LATEST_TAG}" ]] || \
        error "Could not resolve latest release tag. Check your internet connection."

    VERSION="${LATEST_TAG#v}"
    ASSET="drone-streamer-portal_${VERSION}_${ARCH}.deb"
    URL="https://github.com/${REPO}/releases/download/${LATEST_TAG}/${ASSET}"

    TMP=$(mktemp -d)
    trap 'rm -rf "${TMP}"' EXIT
    DEB="${TMP}/${ASSET}"

    info "Downloading ${ASSET}…"
    curl -fsSL "${URL}" -o "${DEB}" || error "Failed to download ${URL}"
    # apt downloads run as the _apt user, which must be able to read the file
    chmod 644 "${DEB}"
fi

[[ -f "${DEB}" ]] || error "Package not found: ${DEB}"
DEB="$(readlink -f "${DEB}")"

info "Installing $(basename "${DEB}")…"
apt-get update -qq
apt-get install -y "${DEB}"

echo ""
info "✅ Done!"
echo ""
echo "  Service status:"
echo "    sudo systemctl status mediamtx drone-stats nginx"
echo "    sudo systemctl status mediamtx-watchdog.timer"
echo ""
echo "  Access the portal at: http://$(hostname -I | awk '{print $1}')/"
