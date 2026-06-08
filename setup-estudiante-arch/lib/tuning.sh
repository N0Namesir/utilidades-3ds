#!/usr/bin/env bash
# lib/tuning.sh — Ajustes de rendimiento para bajo consumo de RAM.
# Variante Arch Linux / CachyOS.
#
# Diferencias clave respecto a la versión Ubuntu:
#   - zram: paquete 'zram-generator' (no 'zram-tools')
#           config en /etc/systemd/zram-generator.conf (formato INI)
#           servicio gestionado por systemd (socket-activated: systemd-zram-setup@zram0)
#   - mariadb: drop-in en /etc/my.cnf.d/ (no /etc/mysql/mariadb.conf.d/)
#   - apache: sin a2dismod; se comentan LoadModule en /etc/httpd/conf/httpd.conf
#             servicio: httpd (no apache2)
#   - earlyoom: AUR (yay_install); config /etc/default/earlyoom (mismo formato)

_HTTPD_CONF="/etc/httpd/conf/httpd.conf"

# ---------------------------------------------------------------------------
# Pasos privados (prefijo _)
# ---------------------------------------------------------------------------

_tuning_zram() {
    info "Configurando zram..."

    pacman_install zram-generator

    # zram-generator usa /etc/systemd/zram-generator.conf (formato INI)
    cat > /etc/systemd/zram-generator.conf << 'EOF'
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
EOF

    # Recargar para que systemd descubra la nueva configuración
    systemctl daemon-reload

    # El servicio es socket-activated; arrancarlo explícitamente la primera vez.
    # En reinicios posteriores, systemd lo gestiona automáticamente.
    systemctl start systemd-zram-setup@zram0.service

    ok "zram habilitado (zstd, 50% de RAM)"
}

_tuning_mariadb_lowram() {
    info "Configurando MariaDB para bajo consumo de RAM..."

    # En Arch los drop-ins van en /etc/my.cnf.d/ (no /etc/mysql/mariadb.conf.d/)
    local dropin="/etc/my.cnf.d/99-low-ram.cnf"
    mkdir -p /etc/my.cnf.d

    cat > "$dropin" << 'EOF'
[mysqld]
innodb_buffer_pool_size = 128M
key_buffer_size = 16M
max_connections = 30
performance_schema = OFF
EOF

    systemctl restart mariadb
    ok "MariaDB con tuning low-RAM aplicado ($dropin)"
}

_tuning_apache_disable_mods() {
    info "Deshabilitando módulos Apache innecesarios..."

    # En Arch no existe a2dismod; comentamos las líneas LoadModule en httpd.conf.
    # Los sed son idempotentes: si la línea ya está comentada, no cambia nada.
    sed -i 's|^LoadModule autoindex_module|#LoadModule autoindex_module|' "$_HTTPD_CONF"
    sed -i 's|^LoadModule cgi_module|#LoadModule cgi_module|'             "$_HTTPD_CONF"
    sed -i 's|^LoadModule status_module|#LoadModule status_module|'       "$_HTTPD_CONF"

    # Verificar sintaxis antes de reiniciar
    httpd -t || err "httpd.conf tiene errores de sintaxis tras deshabilitar módulos. Revisá $_HTTPD_CONF."

    systemctl restart httpd
    ok "Módulos Apache deshabilitados: autoindex, cgi, status"
}

_tuning_earlyoom() {
    info "Instalando y configurando earlyoom..."

    # earlyoom está en el AUR; debe instalarse como usuario no-root
    yay_install earlyoom

    # El formato de /etc/default/earlyoom es idéntico al de Ubuntu
    cat > /etc/default/earlyoom << 'EOF'
EARLYOOM_ARGS="-r 60 -m 15,10 -s 15,10"
EOF

    systemctl enable --now earlyoom
    systemctl restart earlyoom
    ok "earlyoom activo (RAM warn 15% / kill 10%)"
}

# ---------------------------------------------------------------------------
# Funciones públicas
# ---------------------------------------------------------------------------

setup_tuning() {
    run_step "tuning-zram"           _tuning_zram
    run_step "tuning-mariadb-lowram" _tuning_mariadb_lowram
    run_step "tuning-apache-dismods" _tuning_apache_disable_mods
    run_step "tuning-earlyoom"       _tuning_earlyoom
}

verify_tuning() {
    # zram: verificar que el dispositivo /dev/zram0 esté presente y activo como swap
    verify_check "zram0 activo como swap" \
        "grep -q zram /proc/swaps" \
        "sudo systemctl start systemd-zram-setup@zram0.service"

    verify_check "zram-generator.conf presente" \
        "[[ -f /etc/systemd/zram-generator.conf ]]" \
        "sudo bash setup.sh --only=tuning"

    verify_check "MariaDB low-ram drop-in presente" \
        "[[ -f /etc/my.cnf.d/99-low-ram.cnf ]]" \
        "sudo bash setup.sh --only=tuning"

    verify_check "earlyoom activo" \
        "systemctl is-active --quiet earlyoom" \
        "sudo systemctl enable --now earlyoom"

    verify_check "Apache: autoindex_module deshabilitado" \
        "! httpd -M 2>/dev/null | grep -q autoindex_module" \
        "sudo sed -i 's|^LoadModule autoindex_module|#LoadModule autoindex_module|' $_HTTPD_CONF && sudo systemctl restart httpd"

    verify_check "Apache: cgi_module deshabilitado" \
        "! httpd -M 2>/dev/null | grep -q cgi_module" \
        "sudo sed -i 's|^LoadModule cgi_module|#LoadModule cgi_module|' $_HTTPD_CONF && sudo systemctl restart httpd"
}
