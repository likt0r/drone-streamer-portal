#!/usr/bin/env bash
# =============================================================================
# build-deb.sh – Build the drone-streamer-portal Debian package
#
# Usage:
#   npm run build-only          # dist/ must exist first
#   bash scripts/build-deb.sh [version]
#
# version defaults to package.json's version. DEB_ARCH overrides the target
# architecture (default arm64 for the Raspberry Pi).
#
# The package contains everything the Pi needs: frontend build, FastAPI
# backend, MediaMTX binary, nginx site, systemd units. Configuration that is
# rewritten at runtime (mediamtx.yml) ships as a template and is only copied
# on first install (see packaging/postinst).
# =============================================================================
set -euo pipefail

info()  { echo -e "\e[32m[INFO]\e[0m  $*"; }
error() { echo -e "\e[31m[ERROR]\e[0m $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

ARCH="${DEB_ARCH:-arm64}"
MEDIAMTX_VERSION="v1.16.1"

case "${ARCH}" in
    arm64) MEDIAMTX_ARCH="linux_arm64" ;;
    amd64) MEDIAMTX_ARCH="linux_amd64" ;;
    *) error "Unsupported architecture: ${ARCH}" ;;
esac

VERSION="${1:-$(node -p "require('${PROJECT_DIR}/package.json').version")}"
VERSION="${VERSION#v}"
[[ -n "${VERSION}" ]] || error "Could not determine version"

[[ -f "${PROJECT_DIR}/dist/index.html" ]] || \
    error "dist/ is missing or incomplete – run 'npm run build-only' first"

PKG="${PROJECT_DIR}/build/deb/drone-streamer-portal"
OUT="${PROJECT_DIR}/build/drone-streamer-portal_${VERSION}_${ARCH}.deb"
rm -rf "${PROJECT_DIR}/build/deb"
mkdir -p "${PKG}/DEBIAN"

# ── Frontend ──────────────────────────────────────────────────────────────────
info "Adding frontend build…"
mkdir -p "${PKG}/var/www/drone-streamer-portal/dist"
cp -r "${PROJECT_DIR}/dist/." "${PKG}/var/www/drone-streamer-portal/dist/"

# ── Backend (without venv – created by postinst on the Pi) ───────────────────
info "Adding FastAPI backend…"
mkdir -p "${PKG}/opt/drone-streamer-backend"
(cd "${PROJECT_DIR}/backend" && tar cf - \
    --exclude venv --exclude __pycache__ \
    --exclude drone-stats.service --exclude stream_settings.json .) \
    | tar xf - -C "${PKG}/opt/drone-streamer-backend"

# ── MediaMTX binary + helper scripts ──────────────────────────────────────────
info "Downloading MediaMTX ${MEDIAMTX_VERSION} (${MEDIAMTX_ARCH})…"
MEDIAMTX_URL="https://github.com/bluenviron/mediamtx/releases/download/${MEDIAMTX_VERSION}/mediamtx_${MEDIAMTX_VERSION}_${MEDIAMTX_ARCH}.tar.gz"
TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT
curl -fsSL "${MEDIAMTX_URL}" -o "${TMP}/mediamtx.tar.gz"
tar -xzf "${TMP}/mediamtx.tar.gz" -C "${TMP}"

mkdir -p "${PKG}/opt/mediamtx"
install -m 755 "${TMP}/mediamtx" "${PKG}/opt/mediamtx/mediamtx"
install -m 755 "${PROJECT_DIR}/mediamtx/wait-for-video.sh" "${PKG}/opt/mediamtx/wait-for-video.sh"
install -m 755 "${PROJECT_DIR}/scripts/mediamtx-watchdog.sh" "${PKG}/opt/mediamtx/mediamtx-watchdog.sh"

# mediamtx.yml template (postinst copies it to /opt/mediamtx on first install)
mkdir -p "${PKG}/usr/share/drone-streamer-portal"
install -m 644 "${PROJECT_DIR}/mediamtx/mediamtx.yml" \
    "${PKG}/usr/share/drone-streamer-portal/mediamtx.yml"

# ── nginx site ────────────────────────────────────────────────────────────────
info "Adding nginx site…"
mkdir -p "${PKG}/etc/nginx/sites-available"
install -m 644 "${PROJECT_DIR}/nginx/prod.conf" \
    "${PKG}/etc/nginx/sites-available/drone-streamer-portal"

# ── systemd units (production only – dev units stay out) ─────────────────────
info "Adding systemd units…"
mkdir -p "${PKG}/usr/lib/systemd/system"
for unit in mediamtx.service drone-stats.service \
            mediamtx-watchdog.service mediamtx-watchdog.timer; do
    install -m 644 "${PROJECT_DIR}/scripts/systemd/${unit}" \
        "${PKG}/usr/lib/systemd/system/${unit}"
done

# ── DEBIAN control files ──────────────────────────────────────────────────────
info "Adding package metadata…"
sed -e "s/__VERSION__/${VERSION}/" -e "s/__ARCH__/${ARCH}/" \
    "${PROJECT_DIR}/packaging/control.in" > "${PKG}/DEBIAN/control"
install -m 644 "${PROJECT_DIR}/packaging/conffiles" "${PKG}/DEBIAN/conffiles"
install -m 755 "${PROJECT_DIR}/packaging/postinst"  "${PKG}/DEBIAN/postinst"
install -m 755 "${PROJECT_DIR}/packaging/prerm"     "${PKG}/DEBIAN/prerm"
install -m 755 "${PROJECT_DIR}/packaging/postrm"    "${PKG}/DEBIAN/postrm"

# ── Build ─────────────────────────────────────────────────────────────────────
info "Building ${OUT}…"
dpkg-deb --build --root-owner-group "${PKG}" "${OUT}" > /dev/null

info "✅ $(du -h "${OUT}" | cut -f1) $(basename "${OUT}")"
echo "${OUT}"
