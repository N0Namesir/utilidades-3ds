#!/usr/bin/env bash
# lib/vscode.sh — VS Code (repo oficial Microsoft).

_vscode_repo() {
    step "Repositorio VS Code"
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc \
        | gpg --dearmor > /etc/apt/keyrings/microsoft.gpg
    chmod a+r /etc/apt/keyrings/microsoft.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
        | tee /etc/apt/sources.list.d/vscode.list > /dev/null
    apt update
    ok "Repo VS Code agregado"
}

_vscode_install() {
    info "Instalando VS Code..."
    apt_install code
    ok "VS Code instalado"
}

setup_vscode() {
    run_step "vscode-repo"    _vscode_repo
    run_step "vscode-install" _vscode_install
}

