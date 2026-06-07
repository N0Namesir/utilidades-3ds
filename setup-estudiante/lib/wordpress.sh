#!/usr/bin/env bash
# lib/wordpress.sh — Descarga de WordPress + permisos en /var/www/html.
# (La base de datos 'wordpress' se crea en lib/mariadb.sh.)

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
    chown -R "$REAL_USER":www-data "$WORDPRESS_DIR"
    chmod -R 775 "$WORDPRESS_DIR"
    ok "WordPress descargado → http://localhost/wordpress"
}

_wordpress_apache_override() {
    # Fix bug #3: sin AllowOverride All los permalinks de WordPress
    # devuelven 404 aunque mod_rewrite esté habilitado. El .htaccess
    # de WP necesita poder reescribir reglas.
    info "Configurando AllowOverride para WordPress..."
    cat > /etc/apache2/conf-available/wordpress-overrides.conf << 'CONF'
<Directory /var/www/html/wordpress>
    AllowOverride All
    Require all granted
</Directory>
CONF
    a2enconf wordpress-overrides
    systemctl reload apache2
    ok "AllowOverride habilitado para /var/www/html/wordpress"
}

_wordpress_webroot_perms() {
    info "Configurando permisos en /var/www/html para $REAL_USER..."
    backup_webroot
    usermod -aG www-data "$REAL_USER"
    chown -R "$REAL_USER":www-data /var/www/html
    chmod -R 775 /var/www/html
    ok "Permisos configurados (grupo www-data)"
}

setup_wordpress() {
    run_step "wordpress-download"        _wordpress_download
    run_step "wordpress-apache-override" _wordpress_apache_override
    run_step "wordpress-webroot-perm"    _wordpress_webroot_perms
}

