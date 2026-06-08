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

verify_apache_php() {
    verify_check "apache2 activo"          "systemctl is-active --quiet apache2" \
        "sudo systemctl restart apache2  &&  sudo journalctl -u apache2 -n 50"
    verify_check "mod_rewrite habilitado"  "apache2ctl -M 2>/dev/null | grep -q rewrite_module" \
        "sudo a2enmod rewrite && sudo systemctl restart apache2"
    verify_check "php CLI funciona"        "php -r 'echo PHP_VERSION;'" \
        "sudo apt install --reinstall php libapache2-mod-php"
    verify_check "Apache responde HTTP 200 en /"  "curl -fsS -o /dev/null http://localhost/" \
        "sudo systemctl status apache2"
}

