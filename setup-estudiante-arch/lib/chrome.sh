#!/usr/bin/env bash
# lib/chrome.sh — Google Chrome (stable) via AUR
# Variante Arch Linux / CachyOS — usa yay (AUR), no descarga .deb manual.

_chrome_install() {
    step "Google Chrome (stable)"
    # El paquete AUR 'google-chrome' instala la versión estable oficial.
    # El binario resultante es 'google-chrome-stable'.
    # yay DEBE ejecutarse como usuario no-root.
    yay_install google-chrome
    ok "Google Chrome instalado"
}

setup_chrome() {
    run_step "chrome-install" _chrome_install
}

verify_chrome() {
    verify_check "google-chrome-stable en PATH" \
        "command -v google-chrome-stable" \
        "sudo bash setup.sh --only=chrome"
}
