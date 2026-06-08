#!/usr/bin/env bash
# lib/common.sh — Helpers compartidos por todos los módulos
# Requerido por setup.sh antes de cargar cualquier otro módulo.

# ---------------------------------------------------------------------------
# Colores
# ---------------------------------------------------------------------------
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# ---------------------------------------------------------------------------
# Funciones de log
# ---------------------------------------------------------------------------
ok()   { echo -e "${GREEN}[✓]${NC} $1"; }
info() { echo -e "${BLUE}[→]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1" >&2; exit 1; }
step() { echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }

# ---------------------------------------------------------------------------
# Helpers para modo --verify (doctor). NO arreglan nada; solo diagnostican.
# Usados por las funciones verify_<modulo>() en cada lib/*.sh.
# ---------------------------------------------------------------------------
VERIFY_FAIL_COUNT=${VERIFY_FAIL_COUNT:-0}
VERIFY_WARN_COUNT=${VERIFY_WARN_COUNT:-0}
VERIFY_VERBOSE=${VERIFY_VERBOSE:-false}

check_ok()   { echo -e "${GREEN}[✓]${NC} $1"; }
check_warn() {
    echo -e "${YELLOW}[⚠]${NC} $1"
    [[ -n "${2:-}" ]] && echo -e "    ${YELLOW}fix:${NC} $2"
    VERIFY_WARN_COUNT=$((VERIFY_WARN_COUNT + 1))
}
check_fail() {
    echo -e "${RED}[✗]${NC} $1"
    [[ -n "${2:-}" ]] && echo -e "    ${RED}fix:${NC} $2"
    VERIFY_FAIL_COUNT=$((VERIFY_FAIL_COUNT + 1))
}

# verify_check <descripcion> <comando> [fix_hint]
# Ejecuta el comando; si retorna 0 → OK, si no → FAIL con fix.
verify_check() {
    local desc="$1" cmd="$2" fix="${3:-}"
    [[ "$VERIFY_VERBOSE" == true ]] && echo -e "${BLUE}    \$ $cmd${NC}"
    if eval "$cmd" &>/dev/null; then
        check_ok "$desc"
    else
        check_fail "$desc" "$fix"
    fi
}

# verify_check_warn — como verify_check pero usa WARN.
# Para checks de cosas opcionales o subóptimas (no críticas).
verify_check_warn() {
    local desc="$1" cmd="$2" fix="${3:-}"
    [[ "$VERIFY_VERBOSE" == true ]] && echo -e "${BLUE}    \$ $cmd${NC}"
    if eval "$cmd" &>/dev/null; then
        check_ok "$desc"
    else
        check_warn "$desc" "$fix"
    fi
}

# ---------------------------------------------------------------------------
# Directorio de marcadores de pasos completados
# ---------------------------------------------------------------------------
STATE_DIR="/var/lib/setup-estudiante"

# Devuelve 0 (verdadero) si el paso ya fue completado.
step_done() {
    [[ -f "$STATE_DIR/$1.done" ]]
}

# Marca un paso como completado.
mark_done() {
    mkdir -p "$STATE_DIR"
    touch "$STATE_DIR/$1.done"
}

# ---------------------------------------------------------------------------
# INVARIANTE DE DISEÑO — leer antes de escribir nuevas funciones _<modulo>_<paso>
#
# La granularidad de reintento es el STEP, no el módulo.
# Si un step falla a mitad, el re-run lo vuelve a ejecutar COMPLETO desde
# el principio (no desde donde cortó). Por eso toda función _<modulo>_<paso>
# debe ser IDEMPOTENTE: ejecutarla dos veces sobre el mismo sistema debe
# producir el mismo resultado que ejecutarla una.
#
# Patrones seguros:
#   apt install -y         → no-op si ya instalado
#   CREATE … IF NOT EXISTS → no-op si ya existe
#   ALTER USER … BY '…'   → no-op si la pass ya es esa (misma $VAR, persistida)
#   systemctl enable/start → no-op si ya activo
#   ln -sf                 → sobreescribe el symlink, siempre idempotente
#   a2enmod / a2enconf     → no-op si ya habilitado
#   mkdir -p               → no-op si ya existe
#
# Patrones a evitar sin guardia:
#   ALTER USER sin IF EXISTS (rompe si el usuario no existe todavía)
#   rm -rf sin chequeo (destruye estado previo en re-run)
#   wget sin verificar si el destino ya existe
#   adduser / useradd sin --if-not-exists o chequeo previo
#
# El marker .done solo se crea si la función retorna exit 0.
# Si retorna ≠ 0, err() aborta antes de mark_done → el re-run reintenta.
# ---------------------------------------------------------------------------

# Ejecuta una función-paso sólo si todavía no está marcada como completada.
# Uso: run_step <nombre_marcador> <nombre_funcion> [args...]
run_step() {
    local marker="$1"; shift
    local func="$1";   shift

    if step_done "$marker"; then
        warn "Paso '$marker' ya completado — saltando."
        return 0
    fi

    # Captura el exit code explícitamente para que el marker SOLO se cree
    # si la función terminó con éxito, sin depender de set -e del caller.
    local rc=0
    "$func" "$@" || rc=$?
    if [[ $rc -ne 0 ]]; then
        err "Paso '$marker' falló (exit $rc). Re-ejecutá el script para reintentar."
    fi
    mark_done "$marker"
}

# Borra el marker de un paso (forzar re-ejecución en próxima corrida).
clear_marker() {
    rm -f "$STATE_DIR/$1.done"
}

# ---------------------------------------------------------------------------
# Validaciones de entorno
# ---------------------------------------------------------------------------

# Debe ejecutarse como root.
require_root() {
    [[ "$EUID" -eq 0 ]] || err "Ejecutar como root: sudo bash setup.sh"
}

# Debe ser un sistema Ubuntu/Debian.
require_debian() {
    local distro
    distro=$(lsb_release -is 2>/dev/null) || \
        err "No se pudo detectar la distribución. Instalá lsb-release."
    case "$distro" in
        Ubuntu|Debian) ;;
        *) err "Sistema no soportado: $distro. Este script requiere Ubuntu o Debian." ;;
    esac
}

# Detecta el usuario real que invocó sudo y su home.
detect_real_user() {
    REAL_USER="${SUDO_USER:-$USER}"
    REAL_HOME=$(eval echo "~$REAL_USER")
    [[ "$REAL_USER" == "root" ]] && \
        warn "No se detectó SUDO_USER; usando root. Considerá ejecutar con sudo desde tu usuario."
    export REAL_USER REAL_HOME
}

# ---------------------------------------------------------------------------
# Generación de passwords
# ---------------------------------------------------------------------------

# Genera un password aleatorio de 16 caracteres alfanuméricos.
# Apto para MariaDB / phpMyAdmin / WordPress (no requieren clases de chars).
gen_password() {
    openssl rand -base64 18 | tr -d '/+=' | cut -c1-16
}

# Genera un password "complejo" que satisface la política de SQL Server:
# mayúscula + minúscula + dígito + símbolo, longitud >= 12.
# Microsoft rechaza el contenedor mssql si no cumple esto.
# Símbolos elegidos: seguros en shell y en cadenas de conexión (sin $`"'\).
gen_password_complex() {
    local base sym
    base=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-14)
    # Garantizamos las 4 clases prependiendo Aa1 y agregando un símbolo seguro.
    sym=$(printf '%s' '!#%@_-' | fold -w1 | shuf -n1)
    printf 'Aa1%s%s\n' "$sym" "$base"
}

# ---------------------------------------------------------------------------
# Helpers de apt
# ---------------------------------------------------------------------------

# apt install silencioso pero que muestra errores.
apt_install() {
    DEBIAN_FRONTEND=noninteractive apt install -y "$@"
}

# ---------------------------------------------------------------------------
# Helper para bloques SQL con validación de exit code
# ---------------------------------------------------------------------------

# Ejecuta un heredoc SQL contra MariaDB con la contraseña root.
# Uso: run_sql <<'SQL'
#        CREATE DATABASE …;
#      SQL
run_sql() {
    mysql -u root -p"${MARIADB_ROOT_PASSWORD}" || \
        err "Falló la ejecución de SQL (exit $?)"
}

# ---------------------------------------------------------------------------
# Backup defensivo de /var/www/html
# ---------------------------------------------------------------------------
backup_webroot() {
    local backup_dir="/var/backups"
    local today; today=$(date +%F)
    mkdir -p "$backup_dir"

    # Si ya hay UN backup de hoy, no rehacer: ese captura el estado original
    # del día. Backups múltiples sobreescribirían el "antes de tocar nada".
    if compgen -G "$backup_dir/setup-estudiante-${today}*.tar.gz" >/dev/null; then
        info "Backup de hoy ya existe en $backup_dir — preservando original."
        return 0
    fi

    local backup_file ts
    ts=$(date +%H%M%S)
    backup_file="$backup_dir/setup-estudiante-${today}_${ts}.tar.gz"
    info "Creando backup de /var/www/html → $backup_file"
    if [[ -d /var/www/html ]]; then
        tar -czf "$backup_file" -C /var/www html 2>/dev/null || \
            warn "Backup parcial (puede haber archivos bloqueados)."
        ok "Backup guardado en $backup_file"
    else
        warn "/var/www/html no existe todavía — sin backup."
    fi
}

# ---------------------------------------------------------------------------
# Verificar que un servicio systemd está activo
# ---------------------------------------------------------------------------
assert_service_active() {
    local svc="$1"
    systemctl is-active --quiet "$svc" || \
        err "El servicio '$svc' no está activo tras la instalación."
}

# ---------------------------------------------------------------------------
# Verificación de comando disponible en PATH
# ---------------------------------------------------------------------------
require_cmd() {
    command -v "$1" &>/dev/null || err "Comando requerido no encontrado: $1"
}
