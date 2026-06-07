#!/usr/bin/env bash
# lib/tools-cli.sh — Herramientas de línea de comandos.
# NOTA: earlyoom NO está aquí — es un daemon de sistema, se instala y
# configura en lib/tuning.sh (paso 6).

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
    ok "Micro $(micro --version | head -n1) instalado en /usr/local/bin/micro"
}

# ---------------------------------------------------------------------------
# Esenciales
# ---------------------------------------------------------------------------
_tools_essentials() {
    info "Instalando paquetes esenciales..."
    apt_install \
        build-essential \
        jq \
        tree \
        zip \
        p7zip-full \
        ncdu
    ok "Esenciales instalados"
}

# ---------------------------------------------------------------------------
# Composer (instalador oficial con verificación de checksum)
# ---------------------------------------------------------------------------
_tools_composer() {
    info "Instalando Composer (instalador oficial)..."
    local tmp expected actual
    tmp=$(mktemp -d)

    expected=$(curl -fsSL https://composer.github.io/installer.sig)
    curl -fsSL https://getcomposer.org/installer -o "$tmp/composer-setup.php"
    actual=$(php -r "echo hash_file('sha384', '$tmp/composer-setup.php');")

    if [[ "$expected" != "$actual" ]]; then
        rm -rf "$tmp"
        err "Composer: checksum mismatch (esperado $expected, actual $actual)"
    fi

    php "$tmp/composer-setup.php" --install-dir=/usr/local/bin --filename=composer --quiet
    rm -rf "$tmp"
    ok "Composer $(composer --version --no-ansi 2>/dev/null | head -n1)"
}

# ---------------------------------------------------------------------------
# Recomendados (CLIs de búsqueda + utilitarios)
# ---------------------------------------------------------------------------
_tools_recommended() {
    info "Instalando herramientas recomendadas..."
    apt_install \
        ripgrep \
        fd-find \
        bat \
        fzf \
        tldr \
        mkcert \
        httpie \
        imagemagick \
        php-imagick
    ok "Recomendadas instaladas"
}

# En Ubuntu/Debian, fd-find y bat instalan binarios con nombres alternativos
# (fdfind, batcat) por conflicto con paquetes preexistentes. Creamos symlinks
# para que `fd` y `bat` funcionen como en el resto de las distros.
_tools_fd_bat_symlinks() {
    info "Symlinks fd → fdfind, bat → batcat..."
    local fd_bin bat_bin
    fd_bin=$(command -v fdfind || true)
    bat_bin=$(command -v batcat || true)
    [[ -n "$fd_bin"  ]] && ln -sf "$fd_bin"  /usr/local/bin/fd
    [[ -n "$bat_bin" ]] && ln -sf "$bat_bin" /usr/local/bin/bat
    ok "Symlinks creados (fd, bat)"
}

_tools_mkcert_install() {
    # mkcert -install registra el CA local en el trust store del sistema y
    # en NSS (Firefox/Chrome). Sin este paso los certificados son válidos
    # pero los navegadores los marcan como no confiables.
    # Se corre como REAL_USER: mkcert gestiona internamente la parte que
    # requiere permisos elevados. Idempotente: si ya está instalado, sale 0.
    info "Registrando CA local de mkcert..."
    sudo -u "$REAL_USER" mkcert -install
    ok "CA de mkcert instalado en el trust store"
}

# ---------------------------------------------------------------------------
# GitHub CLI (repo oficial)
# ---------------------------------------------------------------------------
_tools_gh() {
    info "Instalando GitHub CLI (repo oficial)..."
    mkdir -p /etc/apt/keyrings
    wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        > /etc/apt/keyrings/githubcli-archive-keyring.gpg
    chmod a+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list
    apt update
    apt_install gh
    ok "GitHub CLI instalado ($(gh --version | head -n1))"
}

# ---------------------------------------------------------------------------
# Fuentes monoespaciadas
# ---------------------------------------------------------------------------
_tools_fonts() {
    info "Instalando fuentes monoespaciadas..."
    apt_install fonts-firacode fonts-jetbrains-mono
    ok "Fuentes instaladas (Fira Code, JetBrains Mono)"
}

setup_tools_cli() {
    run_step "tools-cli-tilix"        _tools_tilix
    run_step "tools-cli-micro"        _tools_micro
    run_step "tools-cli-essentials"   _tools_essentials
    run_step "tools-cli-composer"     _tools_composer
    run_step "tools-cli-recommended"  _tools_recommended
    run_step "tools-cli-fd-bat-syms"  _tools_fd_bat_symlinks
    run_step "tools-cli-mkcert"       _tools_mkcert_install
    run_step "tools-cli-gh"           _tools_gh
    run_step "tools-cli-fonts"        _tools_fonts
}
