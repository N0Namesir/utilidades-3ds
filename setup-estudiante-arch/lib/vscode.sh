#!/usr/bin/env bash
# lib/vscode.sh — Visual Studio Code (versión propietaria via AUR)
# Variante Arch Linux / CachyOS — usa yay (AUR), no repositorios de Microsoft.

_vscode_install() {
    step "Visual Studio Code (visual-studio-code-bin)"
    # visual-studio-code-bin es la versión oficial propietaria de Microsoft,
    # la más completa en cuanto a extensiones y características (Copilot, etc.).
    # yay DEBE ejecutarse como usuario no-root.
    yay_install visual-studio-code-bin
    ok "VS Code instalado"
}

_vscode_extensions() {
    info "Instalando extensiones de VS Code para $REAL_USER..."
    local extensions=(
        bmewburn.vscode-intelephense-client
        esbenp.prettier-vscode
        dbaeumer.vscode-eslint
        eamodio.gitlens
        ritwickdey.LiveServer
        usernamehw.errorlens
    )
    for ext in "${extensions[@]}"; do
        sudo -u "$REAL_USER" code --install-extension "$ext" --force
    done
    ok "Extensiones VS Code instaladas (${#extensions[@]})"
}

setup_vscode() {
    # No se necesita paso de repo: el AUR lo gestiona todo.
    run_step "vscode-install"    _vscode_install
    run_step "vscode-extensions" _vscode_extensions
}

verify_vscode() {
    verify_check "code en PATH" \
        "command -v code" \
        "sudo bash setup.sh --only=vscode"
    verify_check_warn "extensión intelephense instalada" \
        "sudo -u '$REAL_USER' code --list-extensions 2>/dev/null | grep -q bmewburn.vscode-intelephense-client" \
        "sudo bash setup.sh --only=vscode"
    verify_check_warn "extensión prettier instalada" \
        "sudo -u '$REAL_USER' code --list-extensions 2>/dev/null | grep -q esbenp.prettier-vscode" \
        "sudo bash setup.sh --only=vscode"
}
