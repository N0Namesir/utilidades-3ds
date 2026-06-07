#!/usr/bin/env bash
# lib/credentials.sh — Generación de ~/credenciales-instalacion.txt,
# gitignore global y git config interactivo.

CRED_FILE="$REAL_HOME/credenciales-instalacion.txt"

# ---------------------------------------------------------------------------
# Paso 1: archivo de credenciales
# ---------------------------------------------------------------------------
_credentials_write() {
    step "Archivo de credenciales"

    cat > "$CRED_FILE" << EOF
# =============================================================================
#  CREDENCIALES DE INSTALACIÓN — ENTORNO DE DESARROLLO ESTUDIANTIL v2.0
# =============================================================================
#  Generado : $(date '+%Y-%m-%d %H:%M:%S')
#  Hostname : $(hostname)
#  Usuario  : $REAL_USER
# =============================================================================
#  IMPORTANTE: guardá este archivo en un lugar seguro (gestor de contraseñas)
#  y después borralo con:  shred -u ~/credenciales-instalacion.txt
#  Para limpiar también el estado del instalador (passwords persistidos):
#    sudo bash setup.sh --purge-state
# =============================================================================

── MariaDB ───────────────────────────────────────────────────────────────────
  Root password   : $MARIADB_ROOT_PASSWORD
  Acceso          : mysql -u root -p

── phpMyAdmin ────────────────────────────────────────────────────────────────
  URL             : http://localhost/phpmyadmin
  Usuario DB      : root
  Password        : $MARIADB_ROOT_PASSWORD
  App password    : $PHPMYADMIN_PASSWORD

── Base de datos WordPress ───────────────────────────────────────────────────
  Base            : wordpress
  Usuario         : $REAL_USER
  Password        : $USER_DB_PASSWORD
  Completar en    : http://localhost/wordpress

── Base de datos personal ────────────────────────────────────────────────────
  Base            : desarrollo
  Usuario         : $REAL_USER
  Password        : $USER_DB_PASSWORD

── Adminer ───────────────────────────────────────────────────────────────────
  URL             : http://localhost/adminer.php
  (usa las mismas credenciales de MariaDB)

── Accesos rápidos ───────────────────────────────────────────────────────────
  Apache          : http://localhost
  WordPress       : http://localhost/wordpress
  phpMyAdmin      : http://localhost/phpmyadmin
  Adminer         : http://localhost/adminer.php

── Log de instalación ────────────────────────────────────────────────────────
  Archivo         : /var/log/setup-estudiante.log  (chmod 600, solo root)

── Diagnóstico ───────────────────────────────────────────────────────────────
  Doctor          : sudo bash setup.sh --verify

EOF

    chmod 600 "$CRED_FILE"
    chown "$REAL_USER:$REAL_USER" "$CRED_FILE"
    ok "Credenciales guardadas en $CRED_FILE (chmod 600)"
}

# ---------------------------------------------------------------------------
# Paso 2: gitignore global
# ---------------------------------------------------------------------------
_credentials_gitignore() {
    info "Configurando gitignore global..."
    local gitignore="$REAL_HOME/.gitignore_global"

    # Aseguramos cada entrada sin duplicar si ya existe.
    for entry in "credenciales-instalacion.txt" "*.env" ".env.local" ".env.*.local"; do
        grep -qxF "$entry" "$gitignore" 2>/dev/null || echo "$entry" >> "$gitignore"
    done

    sudo -u "$REAL_USER" git config --global core.excludesfile "$gitignore"
    ok "gitignore global configurado en $gitignore"
}

# ---------------------------------------------------------------------------
# Paso 3: git config interactivo
# ---------------------------------------------------------------------------
_credentials_git_config() {
    info "Configuración de identidad git..."

    # -t 0 comprueba que stdin sea un TTY real. Sin TTY el `read` lee EOF
    # inmediatamente o se bloquea para siempre dependiendo del contexto
    # (cron, SSH no interactivo, pipe). El warn le dice al estudiante qué
    # comando ejecutar manualmente.
    if [[ ! -t 0 ]]; then
        warn "Sin TTY: saltando configuración de git."
        warn "Ejecutá manualmente:"
        warn "  git config --global user.name  'Tu Nombre'"
        warn "  git config --global user.email 'tu@email.com'"
        return 0
    fi

    local current_name current_email
    current_name=$(sudo -u "$REAL_USER" git config --global user.name  2>/dev/null || true)
    current_email=$(sudo -u "$REAL_USER" git config --global user.email 2>/dev/null || true)

    if [[ -n "$current_name" && -n "$current_email" ]]; then
        info "Git ya configurado: $current_name <$current_email>"
        return 0
    fi

    # Lee desde /dev/tty explícitamente para no consumir stdin del script
    # principal (que puede estar siendo redirigido por tee).
    local git_name git_email
    read -r -p "  Nombre para git (ej. Juan López): " git_name  < /dev/tty
    read -r -p "  Email  para git (ej. juan@mail.com): " git_email < /dev/tty

    if [[ -n "$git_name" ]]; then
        sudo -u "$REAL_USER" git config --global user.name  "$git_name"
    fi
    if [[ -n "$git_email" ]]; then
        sudo -u "$REAL_USER" git config --global user.email "$git_email"
    fi
    ok "Git configurado: $git_name <$git_email>"
}

# ---------------------------------------------------------------------------
# Función pública
# ---------------------------------------------------------------------------
setup_credentials() {
    # No se usa run_step aquí: las credenciales deben regenerarse en cada
    # re-run (en caso de --purge-state + nueva ejecución los passwords
    # cambian, y el archivo debe reflejarlos). El marcador de idempotencia
    # no tiene sentido para un archivo que es puramente derivado.
    _credentials_write
    run_step "credentials-gitignore"  _credentials_gitignore
    run_step "credentials-git-config" _credentials_git_config
}
