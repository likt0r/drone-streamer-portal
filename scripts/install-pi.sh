#!/usr/bin/env bash
# =============================================================================
# install-pi.sh – Install/update drone-streamer-portal on a Raspberry Pi
#
# Usage:
#   # Register the apt repository and install (no repo clone needed):
#   curl -fsSL https://raw.githubusercontent.com/likt0r/drone-streamer-portal/main/scripts/install-pi.sh | sudo bash
#
#   # Offline / manual: install a locally built .deb instead:
#   sudo bash scripts/install-pi.sh path/to/drone-streamer-portal_x.y.z_arm64.deb
#
# Default path registers the signed apt repo on GitHub Pages, so future updates
# are just `sudo apt update && sudo apt upgrade`. Everything (frontend, backend,
# MediaMTX, nginx site, systemd units) ships in one Debian package; apt resolves
# the system dependencies. A user-edited /opt/mediamtx/mediamtx.yml is preserved
# across updates.
# =============================================================================
set -euo pipefail

info()  { echo -e "\e[32m[INFO]\e[0m  $*"; }
error() { echo -e "\e[31m[ERROR]\e[0m $*" >&2; exit 1; }

PAGES_URL="https://likt0r.github.io/drone-streamer-portal"
KEYRING="/usr/share/keyrings/drone-streamer-portal.gpg"
SOURCES_LIST="/etc/apt/sources.list.d/drone-streamer-portal.list"

[[ $EUID -ne 0 ]] && error "Please run as root: sudo bash $0"

DEB="${1:-}"

if [[ -n "${DEB}" ]]; then
    # ── Offline / manual: install a local .deb directly ──────────────────────
    [[ -f "${DEB}" ]] || error "Package not found: ${DEB}"
    DEB="$(readlink -f "${DEB}")"
    chmod 644 "${DEB}"  # _apt must be able to read it
    info "Installing $(basename "${DEB}")…"
    apt-get update -qq
    apt-get install -y "${DEB}"
else
    # ── Default: register the apt repository, then install ───────────────────
    info "Registering apt repository ${PAGES_URL}…"
    curl -fsSL "${PAGES_URL}/public.key" | gpg --dearmor -o "${KEYRING}" \
        || error "Failed to fetch the repository signing key from ${PAGES_URL}/public.key"
    echo "deb [signed-by=${KEYRING}] ${PAGES_URL} stable main" > "${SOURCES_LIST}"

    info "Installing drone-streamer-portal…"
    apt-get update -qq
    apt-get install -y drone-streamer-portal
fi

echo ""
info "✅ Done!"
echo ""
echo "  Update later with:  sudo apt update && sudo apt upgrade"
echo ""
echo "  Service status:"
echo "    sudo systemctl status mediamtx drone-stats nginx"
echo "    sudo systemctl status mediamtx-watchdog.timer"
echo ""
echo "  Access the portal at: http://$(hostname -I | awk '{print $1}')/"
