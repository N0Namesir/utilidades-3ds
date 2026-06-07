#!/usr/bin/env bash
# lib/apache-php.sh — Apache + PHP + mod_rewrite.

_apache_install() {
    step "Apache + PHP"
    apt_install apache2 php libapache2-mod-php \
        php-mysql php-mbstring php-zip php-gd php-curl php-xml
    systemctl enable apache2
    systemctl start apache2
    ok "Apache y PHP instalados"
}

_apache_rewrite() {
    info "Habilitando mod_rewrite..."
    a2enmod rewrite
    systemctl restart apache2
    ok "mod_rewrite habilitado"
}

setup_apache_php() {
    run_step "apache-php-install" _apache_install
    run_step "apache-php-rewrite" _apache_rewrite
}

