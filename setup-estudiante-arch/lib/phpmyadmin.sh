#!/usr/bin/env bash
# lib/phpmyadmin.sh — phpMyAdmin + symlink en webroot.
# Variante Arch/CachyOS.
#
# Diferencias clave respecto a Ubuntu:
#   - Paquete en extra repo: phpmyadmin  (sin debconf)
#   - Instalado en:  /usr/share/webapps/phpMyAdmin  (no /usr/share/phpmyadmin)
#   - Requiere configuración manual de Apache (Include en httpd.conf)
#   - Requiere crear/copiar config.inc.php desde el archivo de ejemplo

# ---------------------------------------------------------------------------
# Constantes internas
# ---------------------------------------------------------------------------
_PMA_DIR="/usr/share/webapps/phpMyAdmin"
_PMA_CONF_EXTRA="/etc/httpd/conf/extra/phpmyadmin.conf"
_HTTPD_CONF="/etc/httpd/conf/httpd.conf"
_WEBROOT="/var/www/html"

# ---------------------------------------------------------------------------
# Pasos privados (prefijo _)
# ---------------------------------------------------------------------------

_phpmyadmin_install() {
    step "phpMyAdmin"
    pacman_install phpmyadmin
    ok "Paquete phpMyAdmin instalado en $_PMA_DIR"
}

_phpmyadmin_apache_conf() {
    info "Configurando Apache para phpMyAdmin..."

    # Crear directorio extra si no existe
    mkdir -p /etc/httpd/conf/extra

    # Escribir el bloque de configuración de phpMyAdmin.
    # Idempotente: sobreescribir con el mismo contenido es seguro.
    cat > "$_PMA_CONF_EXTRA" << 'EOF'
# phpMyAdmin — generado por setup-estudiante-arch
Alias /phpmyadmin "/usr/share/webapps/phpMyAdmin"
<Directory "/usr/share/webapps/phpMyAdmin">
    DirectoryIndex index.php
    AllowOverride All
    Options FollowSymlinks
    Require all granted
</Directory>
EOF

    # Añadir Include a httpd.conf solo si no está ya presente (idempotente).
    if ! grep -q 'Include conf/extra/phpmyadmin.conf' "$_HTTPD_CONF"; then
        echo '' >> "$_HTTPD_CONF"
        echo '# phpMyAdmin (añadido por setup-estudiante-arch)' >> "$_HTTPD_CONF"
        echo 'Include conf/extra/phpmyadmin.conf' >> "$_HTTPD_CONF"
    fi

    # Verificar la configuración de httpd antes de reiniciar
    httpd -t || err "httpd.conf tiene errores de sintaxis tras añadir Include de phpMyAdmin."

    systemctl restart httpd
    assert_service_active httpd

    ok "Apache configurado para phpMyAdmin"
}

_phpmyadmin_config() {
    info "Creando config.inc.php de phpMyAdmin..."

    local config_file="$_PMA_DIR/config.inc.php"
    local sample_file="$_PMA_DIR/config.sample.inc.php"

    # Idempotente: si ya existe config.inc.php lo dejamos intacto
    # (puede tener personalizaciones del usuario).
    if [[ -f "$config_file" ]]; then
        info "config.inc.php ya existe — preservando configuración existente."
        return 0
    fi

    if [[ ! -f "$sample_file" ]]; then
        err "No se encontró $sample_file. ¿Está el paquete phpmyadmin instalado correctamente?"
    fi

    cp "$sample_file" "$config_file"

    # Generar un blowfish_secret aleatorio de 32 caracteres.
    local blowfish_secret
    blowfish_secret=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-32)

    # Reemplazar el placeholder vacío del blowfish_secret.
    sed -i "s|\(\$cfg\['blowfish_secret'\]\s*=\s*\)''|\1'${blowfish_secret}'|" "$config_file"

    # Ajustar permisos: httpd (usuario http) debe poder leer la config.
    chown root:http "$config_file"
    chmod 640 "$config_file"

    ok "config.inc.php creado con blowfish_secret aleatorio"
}

_phpmyadmin_symlink() {
    info "Creando symlink /var/www/html/phpmyadmin → $_PMA_DIR..."

    # ln -sf sobreescribe un symlink existente → idempotente
    ln -sf "$_PMA_DIR" "$_WEBROOT/phpmyadmin"

    ok "Symlink creado: $_WEBROOT/phpmyadmin → $_PMA_DIR"
}

_phpmyadmin_adminer() {
    info "Descargando Adminer..."

    # wget -O sobreescribe el destino → idempotente por construcción.
    wget -qO "$_WEBROOT/adminer.php" https://www.adminer.org/latest.php \
        || err "No se pudo descargar Adminer. Comprobá la conexión a internet."

    chown "$REAL_USER:http" "$_WEBROOT/adminer.php"
    chmod 644 "$_WEBROOT/adminer.php"

    ok "Adminer instalado → http://localhost/adminer.php"
}

# ---------------------------------------------------------------------------
# Funciones públicas
# ---------------------------------------------------------------------------

setup_phpmyadmin() {
    run_step "phpmyadmin-install"     _phpmyadmin_install
    run_step "phpmyadmin-apache-conf" _phpmyadmin_apache_conf
    run_step "phpmyadmin-config"      _phpmyadmin_config
    run_step "phpmyadmin-symlink"     _phpmyadmin_symlink
    run_step "phpmyadmin-adminer"     _phpmyadmin_adminer
}

verify_phpmyadmin() {
    verify_check "directorio phpMyAdmin existe" \
        "[[ -d $_PMA_DIR ]]" \
        "sudo pacman -S --noconfirm phpmyadmin"

    verify_check "config.inc.php existe" \
        "[[ -f $_PMA_DIR/config.inc.php ]]" \
        "sudo cp $_PMA_DIR/config.sample.inc.php $_PMA_DIR/config.inc.php"

    verify_check "Include phpmyadmin.conf en httpd.conf" \
        "grep -q 'Include conf/extra/phpmyadmin.conf' $_HTTPD_CONF" \
        "sudo bash setup.sh --only=phpmyadmin"

    verify_check "symlink /var/www/html/phpmyadmin" \
        "[[ -L $_WEBROOT/phpmyadmin ]]" \
        "sudo ln -sf $_PMA_DIR $_WEBROOT/phpmyadmin"

    verify_check "phpMyAdmin responde HTTP 200" \
        "curl -fsS -o /dev/null http://localhost/phpmyadmin/" \
        "sudo bash setup.sh --only=phpmyadmin"

    verify_check "/var/www/html/adminer.php existe" \
        "[[ -f $_WEBROOT/adminer.php ]]" \
        "sudo bash setup.sh --only=phpmyadmin"

    verify_check "Adminer responde HTTP 200" \
        "curl -fsS -o /dev/null http://localhost/adminer.php" \
        "sudo bash setup.sh --only=phpmyadmin"
}
