#!/usr/bin/env bash
# =============================================================================
# setup.sh — Orquestador principal
# Versión: 2.0 — Junio 2026
# Uso: sudo bash setup.sh [--skip-wordpress] [--only=mod1,mod2] [--verify]
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Directorio base del proyecto (relativo a este archivo)
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

source "$LIB_DIR/common.sh"

# ---------------------------------------------------------------------------
# Logging: todo stdout/stderr va al log Y a la terminal
# ---------------------------------------------------------------------------
LOG_FILE="/var/log/setup-estudiante.log"
mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

# ---------------------------------------------------------------------------
# Parseo de flags
# ---------------------------------------------------------------------------
FLAG_VERIFY=false
FLAG_SKIP_WORDPRESS=false
ONLY_MODULES=""

FLAG_PURGE_STATE=false

for arg in "$@"; do
    case "$arg" in
        --verify)           FLAG_VERIFY=true ;;
        --purge-state)      FLAG_PURGE_STATE=true ;;
        --skip-wordpress)   FLAG_SKIP_WORDPRESS=true ;;
        --only=*)           ONLY_MODULES="${arg#--only=}" ;;
        --help|-h)
            cat << 'HELP'
Uso: sudo bash setup.sh [opciones]

Opciones:
  --verify              Modo doctor: chequea servicios y reporta estado.
  --purge-state         Borra /var/lib/setup-estudiante/ (markers + passwords).
  --skip-wordpress      Saltea la instalación de WordPress.
  --only=mod1,mod2      Ejecuta solo los módulos indicados (fuerza re-ejecución
                        borrando sus markers). Excluyente con --skip-*.
  -h, --help            Esta ayuda.

Módulos disponibles:
  system apache-php mariadb phpmyadmin nodejs vscode
  tools-cli chrome wordpress tuning welcome-page credentials
HELP
            exit 0
            ;;
        *) err "Flag desconocido: $arg" ;;
    esac
done

# --- Validación de combinaciones de flags ---
if [[ -n "$ONLY_MODULES" && "$FLAG_SKIP_WORDPRESS" == true ]]; then
    err "--only y --skip-wordpress son mutuamente excluyentes."
fi

# ---------------------------------------------------------------------------
# Validaciones iniciales
# ---------------------------------------------------------------------------
require_root
require_debian
detect_real_user

# ---------------------------------------------------------------------------
# --purge-state: borrar markers + passwords y salir
# ---------------------------------------------------------------------------
if [[ "$FLAG_PURGE_STATE" == true ]]; then
    if [[ -d "$STATE_DIR" ]]; then
        warn "Borrando $STATE_DIR (markers + passwords)..."
        rm -rf "$STATE_DIR"
        ok "Estado purgado. Próxima ejecución generará nuevos passwords."
    else
        info "No hay estado previo en $STATE_DIR."
    fi
    exit 0
fi

info "Log: $LOG_FILE"
info "Usuario: $REAL_USER (home: $REAL_HOME)"

# ---------------------------------------------------------------------------
# Cabecera
# ---------------------------------------------------------------------------
echo ""
echo "=============================================="
echo "  Configuración Entorno Estudiantil v2.0"
echo "  Desarrollo Web — $(date '+%Y-%m-%d %H:%M')"
echo "=============================================="
echo ""

# ---------------------------------------------------------------------------
# Modo --verify (doctor)
# ---------------------------------------------------------------------------
if [[ "$FLAG_VERIFY" == true ]]; then
    source "$LIB_DIR/verify.sh"
    run_verify
    exit $?
fi

# ---------------------------------------------------------------------------
# Generación de passwords aleatorios (una sola vez)
# ---------------------------------------------------------------------------
if [[ -f "$STATE_DIR/passwords.env" ]]; then
    warn "Usando passwords generados en ejecución anterior."
    # shellcheck source=/dev/null
    source "$STATE_DIR/passwords.env"
else
    MARIADB_ROOT_PASSWORD=$(gen_password)
    PHPMYADMIN_PASSWORD=$(gen_password)
    USER_DB_PASSWORD=$(gen_password)
    mkdir -p "$STATE_DIR"
    chmod 700 "$STATE_DIR"
    cat > "$STATE_DIR/passwords.env" << EOF
MARIADB_ROOT_PASSWORD=${MARIADB_ROOT_PASSWORD}
PHPMYADMIN_PASSWORD=${PHPMYADMIN_PASSWORD}
USER_DB_PASSWORD=${USER_DB_PASSWORD}
EOF
    chmod 600 "$STATE_DIR/passwords.env"
    ok "Passwords generados y guardados en $STATE_DIR/passwords.env"
fi

export MARIADB_ROOT_PASSWORD PHPMYADMIN_PASSWORD USER_DB_PASSWORD

# ---------------------------------------------------------------------------
# Carga y ejecución de módulos
# ---------------------------------------------------------------------------

# Función auxiliar: decide si un módulo debe ejecutarse según --only=
should_run() {
    local mod="$1"
    [[ -z "$ONLY_MODULES" ]] && return 0
    echo "$ONLY_MODULES" | tr ',' '\n' | grep -qx "$mod"
}

run_module() {
    local mod="$1"
    local file="$LIB_DIR/${mod}.sh"
    [[ -f "$file" ]] || err "Módulo no encontrado: $file"
    # shellcheck source=/dev/null
    source "$file"
}

# --- Módulos en orden ---

# Si --only=X, borrar markers de esos módulos para forzar re-ejecución.
if [[ -n "$ONLY_MODULES" ]]; then
    info "Modo --only: forzando re-ejecución de módulos seleccionados."
    while IFS= read -r mod; do
        # Cada módulo puede tener varios markers internos; los borramos por prefijo.
        find "$STATE_DIR" -maxdepth 1 -name "${mod}*.done" -delete 2>/dev/null || true
    done < <(echo "$ONLY_MODULES" | tr ',' '\n')
fi

should_run system      && run_module system
should_run apache-php  && run_module apache-php
should_run mariadb     && run_module mariadb
should_run phpmyadmin  && run_module phpmyadmin
should_run nodejs      && run_module nodejs
should_run vscode      && run_module vscode
should_run tools-cli   && run_module tools-cli
should_run chrome      && run_module chrome

if [[ "$FLAG_SKIP_WORDPRESS" == false ]]; then
    should_run wordpress   && run_module wordpress
fi

should_run tuning      && run_module tuning
should_run welcome-page && run_module welcome-page
should_run credentials && run_module credentials

# ---------------------------------------------------------------------------
# Limpieza final
# ---------------------------------------------------------------------------
step "Limpieza final"
apt clean
apt autoremove -y
journalctl --vacuum-time=7d
ok "Sistema limpio"

# ---------------------------------------------------------------------------
# Resumen
# ---------------------------------------------------------------------------
echo ""
echo "=============================================="
echo -e "${GREEN}  Configuración completada exitosamente${NC}"
echo "=============================================="
echo ""
echo "  Log completo:    $LOG_FILE"
echo "  Credenciales:    $REAL_HOME/credenciales-instalacion.txt"
echo ""
echo "  Apache:          http://localhost"
echo "  phpMyAdmin:      http://localhost/phpmyadmin"
echo "  Adminer:         http://localhost/adminer.php"
echo "  WordPress:       http://localhost/wordpress"
echo ""
echo -e "${YELLOW}  Consejo:${NC} ejecutá  sudo bash setup.sh --verify  para diagnóstico"
echo ""

# Mostrar credenciales al final
if [[ -f "$REAL_HOME/credenciales-instalacion.txt" ]]; then
    echo "━━━ CREDENCIALES ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    cat "$REAL_HOME/credenciales-instalacion.txt"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi
