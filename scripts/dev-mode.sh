#!/usr/bin/env bash
# =============================================================================
# dev-mode.sh — switch the Pi between PRODUCTION and DEV for the streamer portal.
#
#   prod : nginx serves the built dist/ ; backend = drone-stats (static uvicorn)
#   dev  : nginx reverse-proxies "/" to the Vite dev server (HMR) ;
#          backend = uvicorn --reload running from the repo source
#
# The two modes are mutually exclusive (they share :80 and :5002). The selected
# mode is persistent across reboots (services are enabled/disabled accordingly).
#
# Usage (run as your normal user, NOT root — it calls sudo itself):
#   scripts/dev-mode.sh dev      # switch to dev (Vite HMR + backend reload)
#   scripts/dev-mode.sh prod     # switch back to production
#   scripts/dev-mode.sh status   # show the current mode
# =============================================================================
set -euo pipefail

info()  { echo -e "\e[32m[dev-mode]\e[0m $*"; }
warn()  { echo -e "\e[33m[dev-mode]\e[0m $*"; }
error() { echo -e "\e[31m[dev-mode]\e[0m $*" >&2; exit 1; }

[[ ${EUID:-$(id -u)} -eq 0 ]] && error "Run as your normal user (e.g. pi), not root — the script uses sudo itself."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

NGINX_AVAIL="/etc/nginx/sites-available"
ENABLED_LINK="/etc/nginx/sites-enabled/drone-streamer-portal"
PROD_SITE="${NGINX_AVAIL}/drone-streamer-portal"
DEV_SITE="${NGINX_AVAIL}/drone-streamer-portal-dev"
SYSTEMD_DIR="/etc/systemd/system"

detect_node_dir() {
    # Find a directory containing both `node` and `npm`. The Pi may have no
    # system Node — Node is often only the Zed-bundled one — so we don't rely on
    # the caller's PATH; we probe the filesystem too.
    # 1) explicit override
    if [[ -n "${NODE_DIR:-}" ]]; then echo "${NODE_DIR}"; return; fi
    # 2) already on PATH
    local n; n="$(command -v node 2>/dev/null || true)"
    if [[ -n "${n}" ]]; then dirname "${n}"; return; fi
    # 3) newest Zed-bundled Node
    local zed; zed="$(ls -d "${HOME}"/.local/share/zed/node/node-v*/bin 2>/dev/null | sort -V | tail -1)"
    if [[ -n "${zed}" && -x "${zed}/node" && -x "${zed}/npm" ]]; then echo "${zed}"; return; fi
    # 4) nvm / fnm (newest) and system locations
    local c
    for c in \
        $(ls -d "${HOME}"/.nvm/versions/node/v*/bin 2>/dev/null | sort -V | tail -1) \
        $(ls -d "${HOME}"/.fnm/node-versions/v*/installation/bin 2>/dev/null | sort -V | tail -1) \
        /usr/local/bin /usr/bin ; do
        if [[ -n "${c}" && -x "${c}/node" && -x "${c}/npm" ]]; then echo "${c}"; return; fi
    done
    echo ""
}

ensure_prod_site() {
    # Keep a prod site available so we can always switch back.
    if [[ ! -f "${PROD_SITE}" ]]; then
        sudo install -m 644 "${REPO_DIR}/nginx/prod.conf" "${PROD_SITE}"
    fi
}

cmd_dev() {
    local node_dir
    node_dir="$(detect_node_dir)"
    [[ -z "${node_dir}" || ! -x "${node_dir}/npm" ]] && \
        error "Could not find node/npm. Retry in a shell where 'node' works, or run: NODE_DIR=/path/to/node/bin $0 dev"
    info "Using Node from: ${node_dir}"

    # Render + install the dev systemd units (placeholders filled in here).
    sed -e "s|__REPO_DIR__|${REPO_DIR}|g" \
        "${REPO_DIR}/scripts/systemd/drone-dev-api.service" | sudo tee "${SYSTEMD_DIR}/drone-dev-api.service" >/dev/null
    sed -e "s|__REPO_DIR__|${REPO_DIR}|g" -e "s|__NODE_DIR__|${node_dir}|g" \
        "${REPO_DIR}/scripts/systemd/drone-dev-web.service" | sudo tee "${SYSTEMD_DIR}/drone-dev-web.service" >/dev/null

    # Install + activate the dev nginx config.
    ensure_prod_site
    sudo install -m 644 "${REPO_DIR}/nginx/dev-pi.conf" "${DEV_SITE}"
    sudo ln -sfn "${DEV_SITE}" "${ENABLED_LINK}"
    if ! sudo nginx -t; then
        sudo ln -sfn "${PROD_SITE}" "${ENABLED_LINK}"
        error "nginx config test failed — reverted to prod."
    fi

    sudo systemctl daemon-reload
    info "Stopping production backend (drone-stats)…"
    sudo systemctl disable --now drone-stats 2>/dev/null || true
    info "Starting dev services (Vite + uvicorn --reload)…"
    sudo systemctl enable --now drone-dev-api drone-dev-web
    sudo systemctl reload nginx

    info "DEV mode active. Open http://$(hostname -I | awk '{print $1}')/ — Vite HMR is live."
    info "Backend reloads on changes to ${REPO_DIR}/backend/. Tail: journalctl -u drone-dev-api -f"
    cmd_status
}

cmd_prod() {
    info "Stopping dev services…"
    sudo systemctl disable --now drone-dev-web drone-dev-api 2>/dev/null || true

    ensure_prod_site
    sudo ln -sfn "${PROD_SITE}" "${ENABLED_LINK}"
    if ! sudo nginx -t; then
        error "nginx config test failed for prod config."
    fi

    info "Starting production backend (drone-stats)…"
    sudo systemctl enable --now drone-stats
    sudo systemctl reload nginx

    info "PRODUCTION mode active — nginx serves the built dist/. http://$(hostname -I | awk '{print $1}')/"
    cmd_status
}

cmd_status() {
    local target mode
    target="$(readlink -f "${ENABLED_LINK}" 2>/dev/null || echo '?')"
    case "${target}" in
        *-dev) mode="DEV" ;;
        *)     mode="PROD" ;;
    esac
    echo "──────────────────────────────────────────────"
    echo "  Mode (nginx):     ${mode}   (${target})"
    echo "  drone-stats:      $(systemctl is-active drone-stats 2>/dev/null || :)"
    echo "  drone-dev-api:    $(systemctl is-active drone-dev-api 2>/dev/null || :)"
    echo "  drone-dev-web:    $(systemctl is-active drone-dev-web 2>/dev/null || :)"
    echo "──────────────────────────────────────────────"
}

case "${1:-}" in
    dev)    cmd_dev ;;
    prod)   cmd_prod ;;
    status) cmd_status ;;
    *)      error "Usage: $0 {dev|prod|status}" ;;
esac
