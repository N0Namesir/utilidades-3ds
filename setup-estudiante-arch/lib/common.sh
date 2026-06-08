#!/usr/bin/env bash
# lib/common.sh — Helpers compartidos por todos los módulos
# Requerido por setup.sh antes de cargar cualquier otro módulo.
# Variante Arch Linux / CachyOS — usa pacman + yay.

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[✓]${NC} $1"; }
info() { echo -e "${BLUE}[→]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1" >&2; exit 1; }
step() { echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }

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

verify_check() {
    local desc="$1" cmd="$2" fix="${3:-}"
    [[ "$VERIFY_VERBOSE" == true ]] && echo -e "${BLUE}    \$ $cmd${NC}"
    if eval "$cmd" &>/dev/null; then
        check_ok "$desc"
    else
        check_fail "$desc" "$fix"
    fi
}

verify_check_warn() {
    local desc="$1" cmd="$2" fix="${3:-}"
    [[ "$VERIFY_VERBOSE" == true ]] && echo -e "${BLUE}    \$ $cmd${NC}"
    if eval "$cmd" &>/dev/null; then
        check_ok "$desc"
    else
        check_warn "$desc" "$fix"
    fi
}

STATE_DIR="/var/lib/setup-estudiante"

step_done() { [[ -f "$STATE_DIR/$1.done" ]]; }
mark_done() { mkdir -p "$STATE_DIR"; touch "$STATE_DIR/$1.done"; }

run_step() {
    local marker="$1"; shift
    local func="$1";   shift
    if step_done "$marker"; then
        warn "Paso '$marker' ya completado — saltando."
        return 0
    fi
    local rc=0
    "$func" "$@" || rc=$?
    if [[ $rc -ne 0 ]]; then
        err "Paso '$marker' falló (exit $rc). Re-ejecutá el script para reintentar."
    fi
    mark_done "$marker"
}

clear_marker() { rm -f "$STATE_DIR/$1.done"; }

require_root() {
    [[ "$EUID" -eq 0 ]] || err "Ejecutar como root: sudo bash setup.sh"
}

# Verifica que el sistema sea Arch Linux o una derivada compatible.
# Acepta: ID=arch, ID=cachyos, ID=endeavouros, ID=manjaro,
#         o cualquier distro donde ID_LIKE contenga "arch".
require_arch() {
    local os_id os_id_like
    if [[ ! -f /etc/os-release ]]; then
        err "No se encontró /etc/os-release. ¿Es realmente un sistema Arch-based?"
    fi
    # shellcheck source=/dev/null
    source /etc/os-release
    os_id="${ID:-}"
    os_id_like="${ID_LIKE:-}"

    case "$os_id" in
        arch|cachyos|endeavouros|manjaro) return 0 ;;
    esac

    # Aceptar cualquier distro que declare ID_LIKE=arch (o "arch something")
    if echo "$os_id_like" | grep -qw "arch"; then
        return 0
    fi

    err "Sistema no soportado: ID=${os_id}. Este script requiere Arch Linux o una derivada (CachyOS, EndeavourOS, Manjaro, etc.)."
}

detect_real_user() {
    REAL_USER="${SUDO_USER:-$USER}"
    REAL_HOME=$(eval echo "~$REAL_USER")
    [[ "$REAL_USER" == "root" ]] && \
        warn "No se detectó SUDO_USER; usando root. Considerá ejecutar con sudo desde tu usuario."
    export REAL_USER REAL_HOME
}

gen_password() {
    openssl rand -base64 18 | tr -d '/+=' | cut -c1-16
}

gen_password_complex() {
    local base sym
    base=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-14)
    sym=$(printf '%s' '!#%@_-' | fold -w1 | shuf -n1)
    printf 'Aa1%s%s\n' "$sym" "$base"
}

# Instala paquetes desde los repositorios oficiales (requiere root).
pacman_install() {
    pacman -S --noconfirm --needed "$@"
}

# Instala paquetes desde el AUR. DEBE ejecutarse como usuario no-root.
# Depende de que REAL_USER esté exportado por detect_real_user().
yay_install() {
    [[ -z "${REAL_USER:-}" ]] && err "yay_install: REAL_USER no está definido. Llamá detect_real_user() primero."
    [[ "$REAL_USER" == "root" ]] && err "yay_install: yay no puede ejecutarse como root. Definí SUDO_USER."
    sudo -u "$REAL_USER" yay -S --noconfirm --needed "$@"
}

# Alias de compatibilidad: módulos que aún llamen apt_install usarán pacman.
apt_install() {
    pacman_install "$@"
}

run_sql() {
    mysql -u root -p"${MARIADB_ROOT_PASSWORD}" || \
        err "Falló la ejecución de SQL (exit $?)"
}

backup_webroot() {
    local backup_dir="/var/backups"
    local today; today=$(date +%F)
    mkdir -p "$backup_dir"
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

assert_service_active() {
    local svc="$1"
    systemctl is-active --quiet "$svc" || \
        err "El servicio '$svc' no está activo tras la instalación."
}

require_cmd() {
    command -v "$1" &>/dev/null || err "Comando requerido no encontrado: $1"
}
