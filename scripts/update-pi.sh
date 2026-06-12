#!/usr/bin/env bash
# =============================================================================
# update-pi.sh – Update drone-streamer-portal on a Raspberry Pi
#
# Install and update are the same operation now: fetch the latest Debian
# package from GitHub and install it (frontend, backend, configs, units –
# everything). This wrapper exists for familiarity.
#
# Usage:
#   sudo bash scripts/update-pi.sh
# =============================================================================
set -euo pipefail
exec bash "$(dirname "${BASH_SOURCE[0]}")/install-pi.sh" "$@"
