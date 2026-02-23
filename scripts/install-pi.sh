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
#   1. Installs system packages (nginx, ffmpeg, v4l-utils, python3-venv)
#   2. Downloads & installs MediaMTX v1.16.1 (linux_arm64)
#   3. Creates a systemd service for MediaMTX and enables it
#   4. Downloads the latest Vue build from GitHub and deploys it
#   5. Copies nginx prod config and enables the site
#   6. Installs the FastAPI backend and creates a systemd service for it
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

info "Installing nginx, ffmpeg, v4l-utils, python3…"
apt-get install -y --no-install-recommends \
    nginx \
    ffmpeg \
    v4l-utils \
    curl \
    wget \
    tar \
    python3 \
    python3-pip \
    python3-venv

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
    install -m 644 "${PROJECT_DIR}/mediamtx/mediamtx.yml" "${INSTALL_DIR}/mediamtx.yml"
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

# ── 4. Vue app – download latest release from GitHub ─────────────────────────
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

info "Extracting to ${WEB_ROOT}…"
mkdir -p "${WEB_ROOT}"
tar -xzf "${TMP_WEB}/portal.tar.gz" -C "${WEB_ROOT}"
chown -R www-data:www-data "${WEB_ROOT}"
rm -rf "${TMP_WEB}"
info "Vue build (${LATEST_TAG}) deployed to ${WEB_ROOT}."

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

# ── 6. FastAPI backend ────────────────────────────────────────────────────────
BACKEND_INSTALL_DIR="/opt/drone-streamer-backend"

info "Installing FastAPI backend to ${BACKEND_INSTALL_DIR}…"
mkdir -p "${BACKEND_INSTALL_DIR}"
cp -r "${PROJECT_DIR}/backend/"* "${BACKEND_INSTALL_DIR}/"

info "Creating Python virtual environment…"
python3 -m venv "${BACKEND_INSTALL_DIR}/venv"

info "Installing Python dependencies…"
"${BACKEND_INSTALL_DIR}/venv/bin/pip" install --upgrade pip -q
"${BACKEND_INSTALL_DIR}/venv/bin/pip" install -r "${BACKEND_INSTALL_DIR}/requirements.txt" -q

info "Creating drone-stats systemd service…"
cat > /etc/systemd/system/drone-stats.service << EOF
[Unit]
Description=Drone Streamer FastAPI Hardware Stats backend
After=network.target

[Service]
User=root
WorkingDirectory=${BACKEND_INSTALL_DIR}
Environment="PATH=${BACKEND_INSTALL_DIR}/venv/bin"
ExecStart=${BACKEND_INSTALL_DIR}/venv/bin/uvicorn main:app --host 0.0.0.0 --port 5002
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable drone-stats
systemctl restart drone-stats
info "drone-stats backend service enabled and started."

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
info "✅ Installation complete!"
echo ""
echo "  MediaMTX config : ${INSTALL_DIR}/mediamtx.yml"
echo "  Web root        : ${WEB_ROOT}"
echo "  Nginx site      : ${NGINX_SITE}"
echo "  Backend         : ${BACKEND_INSTALL_DIR}"
echo ""
echo "  Service status:"
echo "    sudo systemctl status mediamtx"
echo "    sudo systemctl status nginx"
echo "    sudo systemctl status drone-stats"
echo ""
echo "  Access the portal at: http://$(hostname -I | awk '{print $1}')/"
