#!/usr/bin/env bash
# lib/mariadb.sh — MariaDB server + secure + DBs por defecto.

_mariadb_install() {
    step "MariaDB"
    apt_install mariadb-server
    systemctl enable mariadb
    systemctl start mariadb
    ok "MariaDB instalado"
}

_mariadb_secure() {
    info "Asegurando MariaDB..."
    sudo mysql << EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MARIADB_ROOT_PASSWORD}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
    ok "MariaDB asegurado"
}

_mariadb_create_dbs() {
    info "Creando bases de datos 'wordpress' y 'desarrollo'..."
    run_sql << EOF
CREATE DATABASE IF NOT EXISTS wordpress  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS desarrollo CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${REAL_USER}'@'localhost' IDENTIFIED BY '${REAL_USER}';
GRANT ALL PRIVILEGES ON wordpress.*  TO '${REAL_USER}'@'localhost';
GRANT ALL PRIVILEGES ON desarrollo.* TO '${REAL_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF
    ok "Bases 'wordpress' y 'desarrollo' creadas (user: $REAL_USER)"
}

setup_mariadb() {
    run_step "mariadb-install"    _mariadb_install
    run_step "mariadb-secure"     _mariadb_secure
    run_step "mariadb-create-dbs" _mariadb_create_dbs
}

