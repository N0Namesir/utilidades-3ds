#!/usr/bin/env bash
# lib/wordpress.sh

WORDPRESS_DIR="/var/www/html/wordpress"

_wordpress_download() {
    step "WordPress"
    if [[ -d "$WORDPRESS_DIR" ]]; then
        warn "WordPress ya existe en $WORDPRESS_DIR, omitiendo descarga"
        return 0
    fi
    wget -qO /tmp/wordpress.tar.gz https://wordpress.org/latest.tar.gz
    tar -xzf /tmp/wordpress.tar.gz -C /var/www/html/
    rm -f /tmp/wordpress.tar.gz
    chown -R "$REAL_USER":http "$WORDPRESS_DIR"
    chmod -R 775 "$WORDPRESS_DIR"
    ok "WordPress descargado → http://localhost/wordpress"
}

_wordpress_apache_override() {
    info "Configurando AllowOverride para WordPress..."
    cat > /etc/httpd/conf/extra/wordpress.conf << 'CONF'
<Directory /var/www/html/wordpress>
    AllowOverride All
    Require all granted
</Directory>
CONF

    # Incluir wordpress.conf en httpd.conf si aún no está incluido
    if ! grep -qF 'Include conf/extra/wordpress.conf' /etc/httpd/conf/httpd.conf; then
        echo 'Include conf/extra/wordpress.conf' >> /etc/httpd/conf/httpd.conf
        info "Añadida línea Include conf/extra/wordpress.conf en httpd.conf"
    fi

    systemctl reload httpd
    ok "AllowOverride habilitado para /var/www/html/wordpress"
}

_wordpress_webroot_perms() {
    info "Configurando permisos en /var/www/html para $REAL_USER..."
    backup_webroot
    usermod -aG http "$REAL_USER"
    chown -R "$REAL_USER":http /var/www/html
    chmod -R 775 /var/www/html
    ok "Permisos configurados (grupo http)"
}

setup_wordpress() {
    run_step "wordpress-download"        _wordpress_download
    run_step "wordpress-apache-override" _wordpress_apache_override
    run_step "wordpress-webroot-perm"    _wordpress_webroot_perms
}

verify_wordpress() {
    verify_check "directorio /var/www/html/wordpress" \
        "[[ -d '$WORDPRESS_DIR' ]]" \
        "sudo bash setup.sh --only=wordpress"
    verify_check "wp-includes/version.php (WP descargado)" \
        "[[ -f '$WORDPRESS_DIR/wp-includes/version.php' ]]" \
        "sudo bash setup.sh --only=wordpress"
    verify_check "WP responde HTTP 200" \
        "curl -fsS -o /dev/null http://localhost/wordpress/" \
        "sudo systemctl status httpd"
    verify_check "AllowOverride habilitado (/etc/httpd/conf/extra/wordpress.conf)" \
        "[[ -f /etc/httpd/conf/extra/wordpress.conf ]]" \
        "sudo bash setup.sh --only=wordpress"
    verify_check_warn "user $REAL_USER en grupo http" \
        "id -nG '$REAL_USER' | tr ' ' '\n' | grep -qx http" \
        "sudo usermod -aG http $REAL_USER  (cerrar sesión para que aplique)"
}
