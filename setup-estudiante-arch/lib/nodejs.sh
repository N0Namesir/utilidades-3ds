#!/usr/bin/env bash
# lib/nodejs.sh — Node.js, pnpm y paquetes npm globales
# Variante Arch Linux / CachyOS — usa pacman (repos oficiales).

_nodejs_install() {
    step "Node.js LTS"
    # En Arch, nodejs y npm están en los repositorios oficiales.
    # No se necesita script externo de NodeSource.
    pacman_install nodejs npm
    ok "Node.js $(node -v) instalado"
}

_nodejs_pnpm() {
    info "Instalando pnpm..."
    # pnpm también está disponible en los repos oficiales de Arch.
    pacman_install pnpm
    ok "pnpm $(pnpm -v) instalado"
}

_nodejs_user_prefix() {
    info "Configurando prefix global de npm para $REAL_USER..."
    local npm_dir="$REAL_HOME/.npm-global"
    local profile="$REAL_HOME/.profile"
    # shellcheck disable=SC2016
    local path_line='export PATH="$HOME/.npm-global/bin:$PATH"'
    sudo -u "$REAL_USER" mkdir -p "$npm_dir"
    sudo -u "$REAL_USER" npm config set prefix "$npm_dir"
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
    # En Arch se distribuye el LTS actual; no necesariamente v22.
    # Se verifica que node esté presente y devuelva una versión semántica.
    verify_check "node en PATH" \
        "command -v node" \
        "sudo bash setup.sh --only=nodejs"
    verify_check "node tiene versión válida" \
        "node -v | grep -q '^v[0-9]'" \
        "sudo bash setup.sh --only=nodejs  (versión actual: \$(node -v 2>/dev/null))"
    verify_check "pnpm en PATH" \
        "command -v pnpm" \
        "sudo bash setup.sh --only=nodejs"
    verify_check ".npm-global existe para $REAL_USER" \
        "[[ -d '$REAL_HOME/.npm-global' ]]" \
        "sudo bash setup.sh --only=nodejs"
    verify_check_warn "PATH del usuario incluye ~/.npm-global/bin" \
        "grep -qF '.npm-global/bin' '$REAL_HOME/.profile'" \
        "sudo bash setup.sh --only=nodejs"
}
