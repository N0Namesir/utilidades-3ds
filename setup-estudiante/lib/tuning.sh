#!/usr/bin/env bash
# lib/tuning.sh — Tuning para máquinas con 4 GB de RAM.
# Cada step deja el sistema en su estado final (reinicia los servicios
# que correspondan); NO requiere reboot del usuario.

# ---------------------------------------------------------------------------
# zram (compresión en RAM, sustituye swap a disco)
# ---------------------------------------------------------------------------
_tuning_zram() {
    info "Configurando zram..."
    apt_install zram-tools

    # PERCENT=50 es un arranque conservador para 4 GB. Si el rendimiento
    # con Chrome Dev + VS Code abiertos sigue siendo malo, probar 75:
    # las páginas comprimidas en RAM son ~3x más rápidas que swap a disco,
    # así que más zram suele ganarle al thrashing.
    cat > /etc/default/zramswap << 'EOF'
ALGO=zstd
PERCENT=50
EOF
    systemctl enable --now zramswap
    ok "zram habilitado (zstd, 50% de RAM)"
}

# ---------------------------------------------------------------------------
# MariaDB con footprint reducido
# ---------------------------------------------------------------------------
_tuning_mariadb_lowram() {
    info "Configurando MariaDB para 4 GB de RAM..."
    cat > /etc/mysql/mariadb.conf.d/99-low-ram.cnf << 'EOF'
[mysqld]
innodb_buffer_pool_size = 128M
key_buffer_size = 16M
max_connections = 30
performance_schema = OFF
EOF
    systemctl restart mariadb
    ok "MariaDB con tuning low-RAM aplicado (drop-in 99-low-ram.cnf)"
}

# ---------------------------------------------------------------------------
# Apache: deshabilitar módulos innecesarios
# ---------------------------------------------------------------------------
_tuning_apache_disable_mods() {
    info "Deshabilitando módulos Apache innecesarios..."
    # -q silencia "Module XX already disabled" en re-ejecuciones.
    # `|| true` por si algún módulo no existe en una distro futura.
    a2dismod -q autoindex cgi status || true
    systemctl restart apache2
    ok "Módulos Apache deshabilitados: autoindex, cgi, status"
}

# ---------------------------------------------------------------------------
# earlyoom (mata procesos antes del freeze por swap thrashing)
# ---------------------------------------------------------------------------
_tuning_earlyoom() {
    info "Instalando y configurando earlyoom..."
    apt_install earlyoom

    # Tuning explícito para 4 GB con zram:
    #   -r 60        : reporta cada 60s al log
    #   -m 15,10     : warn cuando RAM disponible < 15%, mata a < 10%
    #   -s 15,10     : idem para swap (con zram, esto se alcanza más tarde)
    # Los defaults de earlyoom (10% RAM Y 10% swap) son tarde con zram;
    # queremos matar Chrome/VS Code antes del freeze por thrashing.
    cat > /etc/default/earlyoom << 'EOF'
EARLYOOM_ARGS="-r 60 -m 15,10 -s 15,10"
EOF
    systemctl enable --now earlyoom
    # En re-ejecuciones, --now no relee /etc/default; forzamos restart
    # para que la nueva EARLYOOM_ARGS se aplique.
    systemctl restart earlyoom
    ok "earlyoom activo (RAM warn 15% / kill 10%)"
}

setup_tuning() {
    run_step "tuning-zram"           _tuning_zram
    run_step "tuning-mariadb-lowram" _tuning_mariadb_lowram
    run_step "tuning-apache-dismods" _tuning_apache_disable_mods
    run_step "tuning-earlyoom"       _tuning_earlyoom
}
