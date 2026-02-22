#!/usr/bin/env bash
# =============================================================================
# install-pi.sh – Raspberry Pi 4 deployment script for drone-streamer-portal
#
# Usage:
#   # Clone the repo first:
#   git clone https://github.com/likt0r/drone-streamer-portal.git
#   cd drone-streamer-portal
#
#   # Standard install (keeps existing mediamtx.yml if present):
#   sudo bash scripts/install-pi.sh
#
#   # Force install (overwrites mediamtx.yml with repo version):
#   sudo bash scripts/install-pi.sh --force
#
# What this does:
#   1. Installs system packages (nginx, ffmpeg, v4l-utils)
#   2. Downloads & installs MediaMTX v1.16.1 (linux_arm64)
#   3. Installs the Vue build from ../dist into /var/www/drone-streamer-portal
#   4. Copies nginx prod config and enables the site
#   5. Creates a systemd service for MediaMTX and enables it
# =============================================================================

set -euo pipefail

# ── Colour helpers ────────────────────────────────────────────────────────────
info()  { echo -e "\e[32m[INFO]\e[0m  $*"; }
warn()  { echo -e "\e[33m[WARN]\e[0m  $*"; }
error() { echo -e "\e[31m[ERROR]\e[0m $*" >&2; exit 1; }

# ── Parse arguments ───────────────────────────────────────────────────────────
FORCE=false
for arg in "$@"; do
    case $arg in
        --force) FORCE=true ;;
        *) error "Unknown argument: $arg" ;;
    esac
done

MEDIAMTX_VERSION="v1.16.1"
MEDIAMTX_ARCH="linux_arm64"
MEDIAMTX_URL="https://github.com/bluenviron/mediamtx/releases/download/${MEDIAMTX_VERSION}/mediamtx_${MEDIAMTX_VERSION}_${MEDIAMTX_ARCH}.tar.gz"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

INSTALL_DIR="/opt/mediamtx"
WEB_ROOT="/var/www/drone-streamer-portal"
NGINX_SITE="/etc/nginx/sites-available/drone-streamer-portal"


[[ $EUID -ne 0 ]] && error "Please run as root: sudo bash $0"


# ── 1. System packages ────────────────────────────────────────────────────────
info "Updating package lists…"
apt-get update -qq

info "Installing nginx, ffmpeg, v4l-utils…"
apt-get install -y --no-install-recommends \
    nginx \
    ffmpeg \
    v4l-utils \
    curl \
    wget \
    tar

# ── 2. MediaMTX ───────────────────────────────────────────────────────────────
info "Downloading MediaMTX ${MEDIAMTX_VERSION} (arm64)…"
TMP=$(mktemp -d)
wget -q --show-progress -O "${TMP}/mediamtx.tar.gz" "${MEDIAMTX_URL}"

info "Installing MediaMTX to ${INSTALL_DIR}…"
mkdir -p "${INSTALL_DIR}"
tar -xzf "${TMP}/mediamtx.tar.gz" -C "${TMP}"
install -m 755 "${TMP}/mediamtx" /usr/local/bin/mediamtx

# Copy config — overwrite only if it doesn't exist yet, or --force is set
if [[ ! -f "${INSTALL_DIR}/mediamtx.yml" ]] || [[ "${FORCE}" == true ]]; then
    install -m 644 "${PROJECT_DIR}/mediamtx_v1.16.1/mediamtx.yml" "${INSTALL_DIR}/mediamtx.yml"
    info "Installed mediamtx.yml to ${INSTALL_DIR}/mediamtx.yml"
else
    warn "mediamtx.yml already exists – skipping (use --force to overwrite)"
fi

rm -rf "${TMP}"

# ── 3. MediaMTX systemd service ───────────────────────────────────────────────
info "Creating mediamtx systemd service…"
cat > /etc/systemd/system/mediamtx.service << EOF
[Unit]
Description=MediaMTX streaming server
After=network.target

[Service]
WorkingDirectory=${INSTALL_DIR}
ExecStart=/usr/local/bin/mediamtx ${INSTALL_DIR}/mediamtx.yml
Restart=always
RestartSec=5
# Give access to video devices
SupplementaryGroups=video
# Resource limits
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable mediamtx
systemctl restart mediamtx
info "MediaMTX service enabled and started."

# ── 4. Vue app (dist/) ────────────────────────────────────────────────────────
DIST_DIR="${PROJECT_DIR}/dist"

if [[ -d "${DIST_DIR}" ]]; then
    info "Deploying Vue build to ${WEB_ROOT}…"
    mkdir -p "${WEB_ROOT}"
    rsync -a --delete "${DIST_DIR}/" "${WEB_ROOT}/"
    chown -R www-data:www-data "${WEB_ROOT}"
    info "Vue build deployed."
else
    warn "dist/ not found – skipping Vue deployment."
    warn "Build first with: bun run build  (then re-run this script)"
fi

# ── 5. Nginx ──────────────────────────────────────────────────────────────────
info "Installing nginx site config…"
install -m 644 "${PROJECT_DIR}/nginx/prod.conf" "${NGINX_SITE}"

# Enable site (remove default if still linked)
ln -sf "${NGINX_SITE}" /etc/nginx/sites-enabled/drone-streamer-portal
rm -f /etc/nginx/sites-enabled/default

nginx -t
systemctl enable nginx
systemctl reload nginx
info "Nginx configured and reloaded."

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
info "✅ Installation complete!"
echo ""
echo "  MediaMTX config : ${INSTALL_DIR}/mediamtx.yml"
echo "  Web root        : ${WEB_ROOT}"
echo "  Nginx site      : ${NGINX_SITE}"
echo ""
echo "  Service status:"
echo "    sudo systemctl status mediamtx"
echo "    sudo systemctl status nginx"
echo ""
echo "  Access the portal at: http://$(hostname -I | awk '{print $1}')/"
