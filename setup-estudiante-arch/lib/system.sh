#!/usr/bin/env bash
# lib/system.sh — Actualización del sistema y paquetes base.
# Variante Arch Linux / CachyOS — usa pacman.

_system_update() {
    step "Actualizando sistema"
    pacman -Syu --noconfirm
    ok "Sistema actualizado"
}

_system_base_packages() {
    step "Paquetes base"
    pacman_install \
        curl \
        wget \
        git \
        unzip \
        gnupg
    ok "Paquetes base instalados"
}

setup_system() {
    run_step "system-update"   _system_update
    run_step "system-base-pkg" _system_base_packages
}

verify_system() {
    verify_check "curl en PATH"  "command -v curl"  "sudo pacman -S curl"
    verify_check "wget en PATH"  "command -v wget"  "sudo pacman -S wget"
    verify_check "git en PATH"   "command -v git"   "sudo pacman -S git"
    verify_check "unzip en PATH" "command -v unzip" "sudo pacman -S unzip"
    verify_check "gnupg en PATH" "command -v gpg"   "sudo pacman -S gnupg"
}
