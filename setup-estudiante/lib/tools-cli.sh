#!/usr/bin/env bash
# lib/tools-cli.sh — Tilix + Micro (binario oficial).
# En el paso 5 se agregarán build-essential, jq, ripgrep, etc.

_tools_tilix() {
    step "Tilix"
    apt_install tilix
    ok "Tilix instalado"
}

_tools_micro() {
    info "Instalando Micro desde binario oficial..."
    local MICRO_VERSION="2.0.15"
    local MICRO_URL="https://github.com/micro-editor/micro/releases/download/v${MICRO_VERSION}/micro-${MICRO_VERSION}-linux64.tar.gz"
    local MICRO_TMP
    MICRO_TMP=$(mktemp -d)

    wget -qO "$MICRO_TMP/micro.tar.gz" "$MICRO_URL"
    tar -xzf "$MICRO_TMP/micro.tar.gz" -C "$MICRO_TMP"
    install -m 755 "$MICRO_TMP/micro-${MICRO_VERSION}/micro" /usr/local/bin/micro
    rm -rf "$MICRO_TMP"
    # Fix bug #5: `micro --version` imprime varias líneas (version, commit, build date).
    ok "Micro $(micro --version | head -n1) instalado en /usr/local/bin/micro"
}

setup_tools_cli() {
    run_step "tools-cli-tilix" _tools_tilix
    run_step "tools-cli-micro" _tools_micro
}

