#!/usr/bin/env bash
# lib/nodejs.sh — Node.js 22 LTS (NodeSource) + pnpm.

_nodejs_install() {
    step "Node.js 22 LTS"
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    apt_install nodejs
    ok "Node.js $(node -v) instalado"
}

_nodejs_pnpm() {
    info "Instalando pnpm..."
    npm install -g pnpm
    ok "pnpm $(pnpm -v) instalado"
}

setup_nodejs() {
    run_step "nodejs-install" _nodejs_install
    run_step "nodejs-pnpm"    _nodejs_pnpm
}

