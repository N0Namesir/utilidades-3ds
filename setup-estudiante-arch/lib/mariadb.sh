#!/usr/bin/env bash
# lib/mariadb.sh — MariaDB server + secure + DBs por defecto.
# Variante Arch/CachyOS.
#
# Diferencia clave respecto a Ubuntu:
#   - Después de instalar el paquete, y ANTES del primer 'systemctl start mariadb',
#     hay que inicializar el directorio de datos con mariadb-install-db.
#   - El drop-in de configuración va en /etc/my.cnf.d/ (no /etc/mysql/mariadb.conf.d/).

# ---------------------------------------------------------------------------
# Pasos privados (prefijo _)
# ---------------------------------------------------------------------------

_mariadb_install() {
    step "MariaDB"
    pacman_install mariadb
    systemctl enable mariadb
    ok "Paquete mariadb instalado"
}

_mariadb_init_db() {
    info "Inicializando directorio de datos de MariaDB..."

    # Idempotente: si /var/lib/mysql/mysql/ ya existe, el directorio ya fue
    # inicializado (ya sea por esta función o por una instalación previa).
    if [[ -d /var/lib/mysql/mysql ]]; then
        info "Directorio de datos ya inicializado — saltando mariadb-install-db."
        return 0
    fi

    mariadb-install-db \
        --user=mysql \
        --basedir=/usr \
        --datadir=/var/lib/mysql \
        || err "mariadb-install-db falló. Revisá los logs."

    ok "Directorio de datos de MariaDB inicializado"
}

_mariadb_start() {
    info "Iniciando MariaDB..."
    systemctl start mariadb
    assert_service_active mariadb
    ok "MariaDB iniciado"
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

# ---------------------------------------------------------------------------
# Funciones públicas
# ---------------------------------------------------------------------------

setup_mariadb() {
    run_step "mariadb-install"    _mariadb_install
    run_step "mariadb-init-db"    _mariadb_init_db
    run_step "mariadb-start"      _mariadb_start
    run_step "mariadb-secure"     _mariadb_secure
    run_step "mariadb-create-dbs" _mariadb_create_dbs
}

verify_mariadb() {
    verify_check "mariadb activo" \
        "systemctl is-active --quiet mariadb" \
        "sudo systemctl restart mariadb  &&  sudo journalctl -u mariadb -n 50"

    verify_check "root conecta con MARIADB_ROOT_PASSWORD" \
        "mysql -u root -p\"\$MARIADB_ROOT_PASSWORD\" -e 'SELECT 1' 2>/dev/null" \
        "sudo bash setup.sh --only=mariadb"

    verify_check "DB 'wordpress' existe" \
        "mysql -u root -p\"\$MARIADB_ROOT_PASSWORD\" -e 'USE wordpress' 2>/dev/null" \
        "sudo bash setup.sh --only=mariadb"

    verify_check "DB 'desarrollo' existe" \
        "mysql -u root -p\"\$MARIADB_ROOT_PASSWORD\" -e 'USE desarrollo' 2>/dev/null" \
        "sudo bash setup.sh --only=mariadb"

    verify_check "directorio de datos inicializado" \
        "[[ -d /var/lib/mysql/mysql ]]" \
        "sudo mariadb-install-db --user=mysql --basedir=/usr --datadir=/var/lib/mysql"

    verify_check_warn "drop-in de bajo RAM presente" \
        "[[ -f /etc/my.cnf.d/99-low-ram.cnf ]]" \
        "sudo bash setup.sh --only=tuning"
}
