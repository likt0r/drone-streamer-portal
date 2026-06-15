#!/usr/bin/env bash
# =============================================================================
# update-pi.sh – Update drone-streamer-portal on a Raspberry Pi
#
# Once the apt repository is registered (install-pi.sh does this), updating is
# just an apt upgrade. If the repo is not registered yet, fall back to
# install-pi.sh which registers it and installs.
#
# Usage:
#   sudo bash scripts/update-pi.sh
# =============================================================================
set -euo pipefail

info()  { echo -e "\e[32m[INFO]\e[0m  $*"; }
error() { echo -e "\e[31m[ERROR]\e[0m $*" >&2; exit 1; }

[[ $EUID -ne 0 ]] && error "Please run as root: sudo bash $0"

if [[ -f /etc/apt/sources.list.d/drone-streamer-portal.list ]]; then
    info "Updating via apt…"
    apt-get update -qq
    apt-get install -y --only-upgrade drone-streamer-portal
    info "✅ Up to date."
else
    info "apt repository not registered yet – running install-pi.sh…"
    exec bash "$(dirname "${BASH_SOURCE[0]}")/install-pi.sh"
fi
