#!/usr/bin/env bash
# lib/phpmyadmin.sh — phpMyAdmin + symlink en webroot.

_phpmyadmin_install() {
    step "phpMyAdmin"
    export DEBIAN_FRONTEND=noninteractive
    echo "phpmyadmin phpmyadmin/dbconfig-install boolean true"                        | debconf-set-selections
    echo "phpmyadmin phpmyadmin/app-password-confirm password ${PHPMYADMIN_PASSWORD}" | debconf-set-selections
    echo "phpmyadmin phpmyadmin/mysql/admin-pass password ${MARIADB_ROOT_PASSWORD}"   | debconf-set-selections
    echo "phpmyadmin phpmyadmin/mysql/app-pass password ${PHPMYADMIN_PASSWORD}"       | debconf-set-selections
    echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2"            | debconf-set-selections
    apt_install phpmyadmin
    ln -sf /usr/share/phpmyadmin /var/www/html/phpmyadmin
    ok "phpMyAdmin instalado → http://localhost/phpmyadmin"
}

setup_phpmyadmin() {
    run_step "phpmyadmin-install" _phpmyadmin_install
}

