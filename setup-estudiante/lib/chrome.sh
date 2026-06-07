#!/usr/bin/env bash
# lib/chrome.sh — Google Chrome Dev (.deb oficial).

_chrome_install() {
    step "Google Chrome Dev"
    local CHROME_TMP
    CHROME_TMP=$(mktemp -d)
    wget -qO "$CHROME_TMP/chrome-dev.deb" \
        "https://dl.google.com/linux/direct/google-chrome-unstable_current_amd64.deb"
    apt_install "$CHROME_TMP/chrome-dev.deb"
    rm -rf "$CHROME_TMP"
    ok "Google Chrome Dev instalado"
}

setup_chrome() {
    run_step "chrome-install" _chrome_install
}

