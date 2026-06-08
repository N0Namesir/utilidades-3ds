#!/usr/bin/env bash
# lib/apache-php.sh — Apache (httpd) + PHP para Arch/CachyOS.
#
# Diferencias clave respecto a la versión Ubuntu:
#   - Paquete: apache  →  servicio: httpd
#   - Config:  /etc/httpd/conf/httpd.conf  (no /etc/apache2/)
#   - Web user/group: http:http  (no www-data)
#   - Sin a2enmod/a2dismod: se edita httpd.conf directamente con sed
#   - DocumentRoot por defecto en Arch: /srv/http → usamos /var/www/html

# ---------------------------------------------------------------------------
# Constantes internas
# ---------------------------------------------------------------------------
_HTTPD_CONF="/etc/httpd/conf/httpd.conf"
_PHP_INI="/etc/php/php.ini"
_WEBROOT="/var/www/html"

# ---------------------------------------------------------------------------
# Pasos privados (prefijo _)
# ---------------------------------------------------------------------------

_apache_install() {
    step "Apache (httpd) + PHP"

    pacman_install apache php php-apache php-gd php-intl

    # Crear webroot si no existe (Arch por defecto usa /srv/http)
    mkdir -p "$_WEBROOT"
    chown root:http "$_WEBROOT"
    chmod 755 "$_WEBROOT"

    # --- httpd.conf: DocumentRoot → /var/www/html ----------------------------
    # Arch trae /srv/http por defecto; reemplazamos ambas ocurrencias relevantes.
    sed -i 's|DocumentRoot "/srv/http"|DocumentRoot "/var/www/html"|g' "$_HTTPD_CONF"
    sed -i 's|<Directory "/srv/http">|<Directory "/var/www/html">|g'   "$_HTTPD_CONF"

    # --- httpd.conf: AllowOverride All para el webroot -----------------------
    # La directiva está dentro del bloque <Directory "/var/www/html">.
    # Cambia 'AllowOverride None' por 'AllowOverride All' solo en ese bloque.
    # Usamos perl para editar en contexto multi-línea de forma portátil.
    perl -i -0pe \
        's|(<Directory "/var/www/html">.*?AllowOverride\s+)None|\1All|s' \
        "$_HTTPD_CONF"

    # --- httpd.conf: mod_rewrite ---------------------------------------------
    # En Arch la línea viene comentada; la descomentamos.
    sed -i 's|^#LoadModule rewrite_module|LoadModule rewrite_module|' "$_HTTPD_CONF"

    # --- httpd.conf: módulo PHP ----------------------------------------------
    # php-apache instala modules/libphp.so y conf/extra/php_module.conf.
    # Solo añadimos las líneas si no están ya presentes (idempotente).
    if ! grep -q 'LoadModule php_module' "$_HTTPD_CONF"; then
        cat >> "$_HTTPD_CONF" << 'EOF'

# --- PHP (añadido por setup-estudiante-arch) ---
LoadModule php_module modules/libphp.so
AddHandler php-script .php
Include conf/extra/php_module.conf
EOF
    fi

    # Verificar la configuración antes de arrancar
    httpd -t || err "httpd.conf tiene errores de sintaxis. Revisá $_HTTPD_CONF."

    systemctl enable httpd
    systemctl start  httpd
    assert_service_active httpd

    ok "Apache (httpd) iniciado"
}

_apache_php_extensions() {
    info "Habilitando extensiones PHP en $_PHP_INI..."

    # Descomenta las líneas que empiezan con ';extension=<nombre>'
    # sed: reemplaza '^;extension=X' → 'extension=X' (solo si está comentada)
    for ext in mysqli mbstring zip curl gd dom xml simplexml; do
        sed -i "s|^;extension=${ext}$|extension=${ext}|" "$_PHP_INI"
    done

    # Reiniciar httpd para que PHP cargue las extensiones nuevas
    systemctl restart httpd
    assert_service_active httpd

    ok "Extensiones PHP habilitadas: mysqli mbstring zip curl gd dom xml simplexml"
}

_apache_rewrite() {
    # En Arch, mod_rewrite ya se habilitó en _apache_install editando httpd.conf.
    # Este paso separado verifica el estado y hace restart si es necesario,
    # manteniendo la granularidad de pasos igual que la versión Ubuntu.
    info "Verificando mod_rewrite..."

    if ! grep -q '^LoadModule rewrite_module' "$_HTTPD_CONF"; then
        # Por si el paso anterior no lo hizo (re-run parcial)
        sed -i 's|^#LoadModule rewrite_module|LoadModule rewrite_module|' "$_HTTPD_CONF"
        httpd -t || err "httpd.conf tiene errores de sintaxis tras habilitar rewrite."
        systemctl restart httpd
        assert_service_active httpd
    else
        # Ya está habilitado; aseguramos que el servicio esté corriendo
        systemctl is-active --quiet httpd || systemctl restart httpd
    fi

    ok "mod_rewrite habilitado"
}

# ---------------------------------------------------------------------------
# Funciones públicas
# ---------------------------------------------------------------------------

setup_apache_php() {
    run_step "apache-php-install"    _apache_install
    run_step "apache-php-extensions" _apache_php_extensions
    run_step "apache-php-rewrite"    _apache_rewrite
}

verify_apache_php() {
    verify_check "httpd activo" \
        "systemctl is-active --quiet httpd" \
        "sudo systemctl restart httpd  &&  sudo journalctl -u httpd -n 50"

    verify_check "mod_rewrite habilitado" \
        "httpd -M 2>/dev/null | grep -q rewrite_module" \
        "sudo sed -i 's|^#LoadModule rewrite_module|LoadModule rewrite_module|' $_HTTPD_CONF && sudo systemctl restart httpd"

    verify_check "DocumentRoot apunta a /var/www/html" \
        "grep -q 'DocumentRoot \"/var/www/html\"' $_HTTPD_CONF" \
        "sudo sed -i 's|DocumentRoot \"/srv/http\"|DocumentRoot \"/var/www/html\"|g' $_HTTPD_CONF && sudo systemctl restart httpd"

    verify_check "módulo PHP cargado en httpd" \
        "httpd -M 2>/dev/null | grep -q php_module" \
        "Verificá que LoadModule php_module esté en $_HTTPD_CONF y reiniciá httpd"

    verify_check "php CLI funciona" \
        "php -r 'echo PHP_VERSION;'" \
        "sudo pacman -S --noconfirm php php-apache"

    verify_check "extensión mysqli activa" \
        "php -m 2>/dev/null | grep -q mysqli" \
        "sudo sed -i 's|^;extension=mysqli|extension=mysqli|' $_PHP_INI && sudo systemctl restart httpd"

    verify_check "Apache responde HTTP 200 en /" \
        "curl -fsS -o /dev/null http://localhost/" \
        "sudo systemctl status httpd"
}
