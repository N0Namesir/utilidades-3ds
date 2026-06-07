#!/usr/bin/env bash
# lib/system.sh — Actualización del sistema y paquetes base.

_system_update() {
    step "Actualizando sistema"
    apt update && apt upgrade -y
    ok "Sistema actualizado"
}

_system_base_packages() {
    step "Paquetes base"
    apt_install \
        curl \
        wget \
        git \
        unzip \
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        gnupg \
        lsb-release
    ok "Paquetes base instalados"
}

setup_system() {
    run_step "system-update"   _system_update
    run_step "system-base-pkg" _system_base_packages
}

verify_system() {
    verify_check "curl en PATH"  "command -v curl"  "sudo apt install curl"
    verify_check "wget en PATH"  "command -v wget"  "sudo apt install wget"
    verify_check "git en PATH"   "command -v git"   "sudo apt install git"
    verify_check "unzip en PATH" "command -v unzip" "sudo apt install unzip"
    verify_check "gnupg en PATH" "command -v gpg"   "sudo apt install gnupg"
}

