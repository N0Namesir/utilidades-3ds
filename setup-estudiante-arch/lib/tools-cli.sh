#!/usr/bin/env bash
# lib/tools-cli.sh — Herramientas de línea de comandos.
# Variante Arch Linux / CachyOS — usa pacman + yay.
#
# Diferencias clave respecto a la versión Ubuntu:
#   - tilix: AUR (yay_install)
#   - fd: paquete 'fd', binario ya es 'fd' (sin symlink fdfind→fd)
#   - bat: paquete 'bat', binario ya es 'bat' (sin symlink batcat→bat)
#   - tldr: paquete 'tealdeer' (oficial), binario es 'tldr'; requiere 'tldr --update'
#   - mkcert: AUR (yay_install)
#   - httpie: paquete 'python-httpie' (oficial), binario es 'http'
#   - gh: paquete 'github-cli' (oficial), sin repo externo
#   - php-imagick: AUR (yay_install), activa extension en /etc/php/php.ini
#   - fuentes: ttf-fira-code, ttf-jetbrains-mono (pacman)

_tools_tilix() {
    step "Tilix"
    yay_install tilix
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

_tools_essentials() {
    info "Instalando paquetes esenciales..."
    pacman_install base-devel jq tree zip p7zip ncdu
    ok "Esenciales instalados"
}

_tools_composer() {
    info "Instalando Composer (instalador oficial)..."
    local tmp expected actual
    tmp=$(mktemp -d)
    local attempt
    for attempt in 1 2 3; do
        if curl -fsSL --retry 3 --retry-delay 2 \
                https://getcomposer.org/installer -o "$tmp/composer-setup.php"; then
            break
        fi
        warn "Intento $attempt/3 fallido al descargar el instalador de Composer. Reintentando..."
        sleep 5
        if [[ $attempt -eq 3 ]]; then
            rm -rf "$tmp"
            err "No se pudo descargar el instalador de Composer tras 3 intentos."
        fi
    done
    actual=$(php -r "echo hash_file('sha384', '$tmp/composer-setup.php');")
    if expected=$(curl -fsSL --max-time 10 https://composer.github.io/installer.sig 2>/dev/null); then
        if [[ "$expected" != "$actual" ]]; then
            rm -rf "$tmp"
            err "Composer: checksum mismatch."
        fi
        info "Checksum de Composer verificado."
    else
        warn "No se pudo verificar el checksum. Instalando de todos modos."
    fi
    info "Descargando composer.phar..."
    php "$tmp/composer-setup.php" --install-dir=/usr/local/bin --filename=composer --quiet
    rm -rf "$tmp"
    ok "Composer $(composer --version --no-ansi 2>/dev/null | head -n1)"
}

_tools_recommended() {
    info "Instalando herramientas recomendadas (pacman)..."
    # tealdeer: binario 'tldr'; mkcert y php-imagick van como pasos separados (AUR)
    pacman_install ripgrep fd bat fzf tealdeer python-httpie imagemagick
    ok "Herramientas recomendadas instaladas (ripgrep, fd, bat, fzf, tealdeer, httpie, imagemagick)"
}

_tools_tldr_update() {
    info "Actualizando base de datos de tldr (tealdeer)..."
    # tldr --update debe ejecutarse como usuario no-root para escribir en ~/.cache
    sudo -u "$REAL_USER" tldr --update || warn "tldr --update falló; la cache se actualizará en el primer uso."
    ok "Base de datos tldr actualizada"
}

_tools_mkcert_aur() {
    info "Instalando mkcert desde AUR..."
    yay_install mkcert
    ok "mkcert instalado"
}

_tools_php_imagick_aur() {
    info "Instalando php-imagick desde AUR..."
    yay_install php-imagick

    local php_ini="/etc/php/php.ini"
    # Descomenta 'extension=imagick' si está comentada
    if grep -q '^;extension=imagick' "$php_ini"; then
        sed -i 's|^;extension=imagick$|extension=imagick|' "$php_ini"
        info "extension=imagick habilitada en $php_ini"
    elif grep -q '^extension=imagick' "$php_ini"; then
        info "extension=imagick ya estaba habilitada en $php_ini"
    else
        # Si la línea no existe en ninguna forma, la añadimos al final
        echo "extension=imagick" >> "$php_ini"
        info "extension=imagick añadida a $php_ini"
    fi

    ok "php-imagick instalado y extensión habilitada"
}

_tools_fd_bat_symlinks() {
    # En Arch, 'fd' y 'bat' ya son los nombres nativos de los binarios.
    # No se necesitan symlinks. Este paso verifica que estén en PATH.
    info "Verificando fd y bat en PATH (Arch: binarios nativos, sin symlinks)..."
    command -v fd  &>/dev/null || warn "fd no encontrado en PATH; verificá la instalación."
    command -v bat &>/dev/null || warn "bat no encontrado en PATH; verificá la instalación."
    ok "fd y bat disponibles en PATH"
}

_tools_mkcert_install() {
    info "Registrando CA local de mkcert..."
    local caroot="$REAL_HOME/.local/share/mkcert"
    mkdir -p "$caroot"
    CAROOT="$caroot" mkcert -install
    chown -R "$REAL_USER:$REAL_USER" "$caroot"
    ok "CA de mkcert instalada (CAROOT: $caroot)"
}

_tools_gh() {
    info "Instalando GitHub CLI (repositorio oficial de Arch)..."
    # En Arch, 'github-cli' está en los repos oficiales; no se necesita repo externo.
    pacman_install github-cli
    ok "GitHub CLI instalado"
}

_tools_fonts() {
    info "Instalando fuentes monoespaciadas..."
    pacman_install ttf-fira-code ttf-jetbrains-mono
    ok "Fuentes instaladas (Fira Code, JetBrains Mono)"
}

_tools_filezilla() {
    info "Instalando FileZilla..."
    pacman_install filezilla
    ok "FileZilla instalado"
}

# ---------------------------------------------------------------------------
# Funciones públicas
# ---------------------------------------------------------------------------

setup_tools_cli() {
    run_step "tools-cli-tilix"        _tools_tilix
    run_step "tools-cli-micro"        _tools_micro
    run_step "tools-cli-essentials"   _tools_essentials
    run_step "tools-cli-composer"     _tools_composer
    run_step "tools-cli-recommended"  _tools_recommended
    run_step "tools-cli-tldr-update"  _tools_tldr_update
    run_step "tools-cli-mkcert-aur"   _tools_mkcert_aur
    run_step "tools-cli-php-imagick"  _tools_php_imagick_aur
    run_step "tools-cli-fd-bat-syms"  _tools_fd_bat_symlinks
    run_step "tools-cli-mkcert"       _tools_mkcert_install
    run_step "tools-cli-gh"           _tools_gh
    run_step "tools-cli-fonts"        _tools_fonts
    run_step "tools-cli-filezilla"    _tools_filezilla
}

verify_tools_cli() {
    # Binarios directos (sin aliases de Ubuntu)
    local bins=(micro composer jq tree ncdu rg fd bat fzf tldr mkcert http gh filezilla)
    for bin in "${bins[@]}"; do
        verify_check "$bin en PATH" "command -v $bin" "sudo bash setup.sh --only=tools-cli"
    done

    # tilix: verificar que el binario exista (puede no estar en PATH de root)
    verify_check "tilix instalado" \
        "pacman -Qi tilix &>/dev/null" \
        "sudo bash setup.sh --only=tools-cli"

    # mkcert CA
    verify_check "CA mkcert registrada" \
        "[[ -f \"\$(sudo -u '$REAL_USER' mkcert -CAROOT 2>/dev/null)/rootCA.pem\" ]]" \
        "sudo -u '$REAL_USER' mkcert -install"

    # php-imagick: extensión habilitada en php.ini
    verify_check "extension=imagick habilitada en php.ini" \
        "grep -q '^extension=imagick' /etc/php/php.ini" \
        "sudo sed -i 's|^;extension=imagick|extension=imagick|' /etc/php/php.ini"

    # Fuentes con pacman -Qi (no dpkg)
    verify_check_warn "ttf-fira-code instalado" \
        "pacman -Qi ttf-fira-code &>/dev/null" \
        "sudo pacman -S --noconfirm --needed ttf-fira-code"
    verify_check_warn "ttf-jetbrains-mono instalado" \
        "pacman -Qi ttf-jetbrains-mono &>/dev/null" \
        "sudo pacman -S --noconfirm --needed ttf-jetbrains-mono"
}
