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

_nodejs_user_prefix() {
    info "Configurando prefix global de npm para $REAL_USER..."
    local npm_dir="$REAL_HOME/.npm-global"
    local profile="$REAL_HOME/.profile"
    # Queremos $HOME/$PATH LITERAL en el .profile (los expande el shell del
    # usuario al login), no expandirlos ahora.
    # shellcheck disable=SC2016
    local path_line='export PATH="$HOME/.npm-global/bin:$PATH"'

    sudo -u "$REAL_USER" mkdir -p "$npm_dir"
    sudo -u "$REAL_USER" npm config set prefix "$npm_dir"

    # Idempotente: solo agregar la línea si no existe ya.
    if ! grep -qF "$path_line" "$profile" 2>/dev/null; then
        {
            echo ""
            echo "# npm globals sin sudo (setup-estudiante)"
            echo "$path_line"
        } >> "$profile"
        chown "$REAL_USER:$REAL_USER" "$profile"
    fi
    ok "Prefix npm → $npm_dir (PATH actualizado en ~/.profile)"
}

_nodejs_globals() {
    info "Instalando paquetes npm globales como $REAL_USER..."
    # PATH inline para que `npm install -g` apunte al prefix del usuario.
    sudo -u "$REAL_USER" \
        env "PATH=$REAL_HOME/.npm-global/bin:$PATH" \
        npm install -g serve nodemon prettier eslint json-server
    ok "Globals npm instalados: serve, nodemon, prettier, eslint, json-server"
}

setup_nodejs() {
    run_step "nodejs-install"     _nodejs_install
    run_step "nodejs-pnpm"        _nodejs_pnpm
    run_step "nodejs-user-prefix" _nodejs_user_prefix
    run_step "nodejs-globals"     _nodejs_globals
}

verify_nodejs() {
    verify_check "node en PATH"  "command -v node" "sudo bash setup.sh --only=nodejs"
    verify_check "node v22.x"    "node -v | grep -q '^v22'" \
        "sudo bash setup.sh --only=nodejs  (versión actual: \$(node -v 2>/dev/null))"
    verify_check "pnpm en PATH"  "command -v pnpm" "sudo bash setup.sh --only=nodejs"
    verify_check ".npm-global existe para $REAL_USER" \
        "[[ -d '$REAL_HOME/.npm-global' ]]" \
        "sudo bash setup.sh --only=nodejs"
    verify_check_warn "PATH del usuario incluye ~/.npm-global/bin" \
        "grep -qF '.npm-global/bin' '$REAL_HOME/.profile'" \
        "sudo bash setup.sh --only=nodejs"
}

