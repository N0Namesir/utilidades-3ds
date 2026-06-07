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

# Ejecuta una función-paso sólo si todavía no está marcada como completada.
# Uso: run_step <nombre_marcador> <nombre_funcion> [args...]
run_step() {
    local marker="$1"; shift
    local func="$1";   shift

    if step_done "$marker"; then
        warn "Paso '$marker' ya completado — saltando."
        return 0
    fi

    "$func" "$@"
    mark_done "$marker"
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
gen_password() {
    openssl rand -base64 18 | tr -d '/+=' | cut -c1-16
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
    local backup_file="/var/backups/setup-estudiante-$(date +%F_%H%M%S).tar.gz"
    info "Creando backup de /var/www/html → $backup_file"
    tar -czf "$backup_file" -C /var/www html 2>/dev/null || \
        warn "Backup parcial (puede haber archivos bloqueados)."
    ok "Backup guardado en $backup_file"
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
