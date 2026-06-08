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

# LIB_DIR se resuelve en runtime via realpath del script; shellcheck no puede seguirlo.
# shellcheck disable=SC1091
source "$LIB_DIR/common.sh"

# ---------------------------------------------------------------------------
# Logging: todo stdout/stderr va al log Y a la terminal.
# CRÍTICO: el log puede contener fragmentos sensibles (paths a passwords.env,
# mensajes de error de SQL con la pass en el comando, etc.) y en el paso 4
# se sumará el cat del archivo de credenciales. Por eso forzamos modo 600
# root:root ANTES del exec, para que ninguna línea posterior pueda quedar
# en un archivo mundo-legible.
# ---------------------------------------------------------------------------
LOG_FILE="/var/log/setup-estudiante.log"
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"
chown root:root "$LOG_FILE"
chmod 600 "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

# ---------------------------------------------------------------------------
# Parseo de flags
# ---------------------------------------------------------------------------
FLAG_VERIFY=false
FLAG_SKIP_WORDPRESS=false
ONLY_MODULES=""
VERIFY_ONLY=""
FLAG_VERBOSE=false
FLAG_PURGE_STATE=false

for arg in "$@"; do
    case "$arg" in
        --verify)           FLAG_VERIFY=true ;;
        --verify=*)         FLAG_VERIFY=true; VERIFY_ONLY="${arg#--verify=}" ;;
        --verbose)          FLAG_VERBOSE=true ;;
        --purge-state)      FLAG_PURGE_STATE=true ;;
        --skip-wordpress)   FLAG_SKIP_WORDPRESS=true ;;
        --only=*)           ONLY_MODULES="${arg#--only=}" ;;
        --help|-h)
            cat << 'HELP'
Uso: sudo bash setup.sh [opciones]

Opciones:
  --verify              Modo doctor: chequea TODOS los módulos.
  --verify=mod1,mod2    Modo doctor filtrado por módulos.
  --verbose             En --verify, imprime cada comando ejecutado.
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
    # shellcheck disable=SC1091
    source "$LIB_DIR/verify.sh"
    run_verify "$VERIFY_ONLY" "$FLAG_VERBOSE"
    exit $?
fi

# ---------------------------------------------------------------------------
# Generación / elección de passwords (una sola vez)
# ---------------------------------------------------------------------------

# Pide una password al usuario con confirmación. Si el usuario deja el campo
# vacío o la confirmación no coincide tras 3 intentos, devuelve una aleatoria.
# Lee siempre desde /dev/tty para no consumir stdin del script principal.
_prompt_password() {
    local label="$1"
    local pass confirm
    local -i _tries=3
    while (( _tries-- > 0 )); do
        IFS= read -r -s -p "  $label (Enter para aleatoria): " pass < /dev/tty
        echo "" > /dev/tty
        if [[ -z "$pass" ]]; then
            printf '%s' "$(gen_password)"
            return 0
        fi
        if [[ ${#pass} -lt 8 ]]; then
            echo "  Mínimo 8 caracteres. Intentá de nuevo." > /dev/tty
            continue
        fi
        IFS= read -r -s -p "  Confirmá $label: " confirm < /dev/tty
        echo "" > /dev/tty
        if [[ "$pass" == "$confirm" ]]; then
            printf '%s' "$pass"
            return 0
        fi
        echo "  Las contraseñas no coinciden. Intentá de nuevo." > /dev/tty
    done
    # Tras 3 fallos usar aleatoria
    warn "Demasiados intentos fallidos para '$label'. Usando contraseña aleatoria." > /dev/tty
    printf '%s' "$(gen_password)"
}

if [[ -f "$STATE_DIR/passwords.env" ]]; then
    warn "Usando passwords generados en ejecución anterior."
    # shellcheck source=/dev/null
    source "$STATE_DIR/passwords.env"
else
    # Ofrecer elección manual solo si hay TTY interactivo.
    if [[ -t 0 ]]; then
        echo "" > /dev/tty
        echo "  ┌──────────────────────────────────────────────────────┐" > /dev/tty
        echo "  │  Configuración de contraseñas                        │" > /dev/tty
        echo "  │  Podés elegir tus contraseñas o dejar que el script  │" > /dev/tty
        echo "  │  genere unas seguras automáticamente.                │" > /dev/tty
        echo "  │  (Mín. 8 caracteres. Enter = contraseña aleatoria)   │" > /dev/tty
        echo "  └──────────────────────────────────────────────────────┘" > /dev/tty
        echo "" > /dev/tty
        MARIADB_ROOT_PASSWORD=$(_prompt_password "Contraseña root de MariaDB")
        PHPMYADMIN_PASSWORD=$(_prompt_password "Contraseña de phpMyAdmin")
        USER_DB_PASSWORD=$(_prompt_password "Contraseña de bases de datos del usuario")
        echo "" > /dev/tty
    else
        warn "Sin TTY: generando contraseñas aleatorias automáticamente."
        MARIADB_ROOT_PASSWORD=$(gen_password)
        PHPMYADMIN_PASSWORD=$(gen_password)
        USER_DB_PASSWORD=$(gen_password)
    fi

    mkdir -p "$STATE_DIR"
    chmod 700 "$STATE_DIR"
    cat > "$STATE_DIR/passwords.env" << EOF
MARIADB_ROOT_PASSWORD=${MARIADB_ROOT_PASSWORD}
PHPMYADMIN_PASSWORD=${PHPMYADMIN_PASSWORD}
USER_DB_PASSWORD=${USER_DB_PASSWORD}
EOF
    chmod 600 "$STATE_DIR/passwords.env"
    ok "Passwords guardados en $STATE_DIR/passwords.env"
fi

export MARIADB_ROOT_PASSWORD PHPMYADMIN_PASSWORD USER_DB_PASSWORD
# MSSQL_SA_PASSWORD solo existe si el estudiante levantó sqlserver-up.sh
# alguna vez. Lo exportamos como cadena vacía si no, para que credentials.sh
# pueda hacer ${MSSQL_SA_PASSWORD:-} sin romper bajo set -u.
export MSSQL_SA_PASSWORD="${MSSQL_SA_PASSWORD:-}"

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
    local mod="$1" current="$2" total="$3"
    local file="$LIB_DIR/${mod}.sh"
    [[ -f "$file" ]] || err "Módulo no encontrado: $file"
    # shellcheck source=/dev/null
    source "$file"
    # Convertir guiones a underscores para el nombre de la función pública.
    local func="setup_${mod//-/_}"
    declare -f "$func" >/dev/null || err "Módulo '$mod' no define $func()"
    echo ""
    echo -e "${CYAN}┌─ Módulo ${current}/${total}: ${mod} ─────────────────────────────────────────${NC}"
    "$func"
    echo -e "${CYAN}└─ Módulo ${current}/${total}: ${mod} completado${NC}"
}

# --- Lista de módulos a ejecutar (se construye primero para saber el total) ---

ALL_MODULES=(system apache-php mariadb phpmyadmin nodejs vscode tools-cli chrome)
[[ "$FLAG_SKIP_WORDPRESS" == false ]] && ALL_MODULES+=(wordpress)
ALL_MODULES+=(tuning welcome-page credentials)

# Filtrar por --only si aplica
MODULES_TO_RUN=()
for mod in "${ALL_MODULES[@]}"; do
    should_run "$mod" && MODULES_TO_RUN+=("$mod")
done

TOTAL=${#MODULES_TO_RUN[@]}

# Si --only=X, borrar markers de esos módulos para forzar re-ejecución.
if [[ -n "$ONLY_MODULES" ]]; then
    info "Modo --only: forzando re-ejecución de módulos seleccionados."
    while IFS= read -r mod; do
        find "$STATE_DIR" -maxdepth 1 -name "${mod}*.done" -delete 2>/dev/null || true
    done < <(echo "$ONLY_MODULES" | tr ',' '\n')
fi

# Ejecutar módulos con contador de progreso
CURRENT=0
for mod in "${MODULES_TO_RUN[@]}"; do
    CURRENT=$((CURRENT + 1))
    run_module "$mod" "$CURRENT" "$TOTAL"
done

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

# Mostrar credenciales directo al TTY para que NO vayan al log.
# El exec/tee redirige todo stdout/stderr; /dev/tty esquiva ese redirect
# y escribe directamente al terminal del operador.
if [[ -f "$REAL_HOME/credenciales-instalacion.txt" ]]; then
    {
        echo ""
        echo "━━━ CREDENCIALES (no quedan en el log) ━━━━━━━━━"
        cat "$REAL_HOME/credenciales-instalacion.txt"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    } > /dev/tty 2>/dev/null || warn "Sin TTY: credenciales guardadas en $REAL_HOME/credenciales-instalacion.txt"
fi
