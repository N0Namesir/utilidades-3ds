#!/usr/bin/env bash
# =============================================================================
# teardown.sh -- Elimina TODO lo instalado por setup.sh para permitir
# pruebas repetibles sin restaurar snapshot.
#
# USO: sudo bash setup-estudiante-arch/scripts/teardown.sh
#
# ADVERTENCIA: destructivo e irreversible. Purga paquetes, borra datos de
# MariaDB, elimina /var/www/html, ~/.npm-global, credenciales, etc.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Helpers minimos (sin depender de common.sh)
# ---------------------------------------------------------------------------
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[v]${NC} $1"; }
info() { echo    "    $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
step() { echo -e "\n${CYAN}=== $1 ===${NC}"; }

[[ "$EUID" -ne 0 ]] && { echo -e "${RED}[x]${NC} Ejecutar como root: sudo bash teardown.sh"; exit 1; }

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(eval echo "~$REAL_USER")

# ---------------------------------------------------------------------------
# Confirmacion explicita
# ---------------------------------------------------------------------------
echo ""
echo "================================================================"
echo "  TEARDOWN -- elimina TODO lo instalado por setup.sh"
echo "  Afectado: Apache (httpd), PHP, MariaDB, Node, VS Code, Chrome,"
echo "  WordPress, credenciales, state, zram, earlyoom, SQL Server"
echo "================================================================"
echo ""
echo -n "Escribi 'si' para confirmar el teardown completo: "
read -r confirm < /dev/tty
if [[ "$confirm" != "si" ]]; then
    echo "Cancelado."
    exit 0
fi

# ---------------------------------------------------------------------------
# Funcion helper: remover un paquete con pacman ignorando si no está instalado
# ---------------------------------------------------------------------------
remove_pkg() {
    local pkg="$1"
    if pacman -Qi "$pkg" &>/dev/null; then
        pacman -Rns --noconfirm "$pkg"
        ok "$pkg removido"
    else
        info "$pkg no instalado -- saltando"
    fi
}

# ---------------------------------------------------------------------------
# 1. SQL Server (Podman) -- primero para liberar RAM y puertos
# ---------------------------------------------------------------------------
step "SQL Server / Podman"
if command -v podman &>/dev/null; then
    if podman ps -a --filter "name=^sqlserver$" --format '{{.Names}}' 2>/dev/null | grep -q sqlserver; then
        podman stop sqlserver 2>/dev/null || true
        podman rm   sqlserver 2>/dev/null || true
        ok "Contenedor sqlserver eliminado"
    fi
    if podman volume ls --format '{{.Name}}' 2>/dev/null | grep -q sqlserver-data; then
        podman volume rm sqlserver-data 2>/dev/null || true
        ok "Volumen sqlserver-data eliminado"
    fi
    if podman image ls --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -q 'mssql/server'; then
        podman rmi mcr.microsoft.com/mssql/server:2022-latest 2>/dev/null || true
        ok "Imagen SQL Server eliminada"
    fi
    remove_pkg podman
else
    info "Podman no instalado -- saltando"
fi

# ---------------------------------------------------------------------------
# 2. Servicios: detener antes de purgar
# ---------------------------------------------------------------------------
step "Detener servicios"
for svc in httpd mariadb earlyoom systemd-zram-setup@zram0.service; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        systemctl stop    "$svc" || true
        ok "$svc detenido"
    fi
    systemctl disable "$svc" 2>/dev/null || true
done

# ---------------------------------------------------------------------------
# 3. Paquetes pacman -- remover en grupos logicos
# ---------------------------------------------------------------------------
step "Remoción de paquetes"

info "Apache + PHP..."
pacman -Rns --noconfirm \
    apache \
    php php-apache php-cli \
    php-gd php-intl php-imagick imagemagick 2>/dev/null || true
ok "Apache + PHP removidos"

info "MariaDB..."
pacman -Rns --noconfirm mariadb mariadb-clients 2>/dev/null || true
ok "MariaDB removido"

info "phpMyAdmin..."
# phpMyAdmin puede estar instalado vía yay (AUR) o manualmente
if pacman -Qi phpmyadmin &>/dev/null; then
    pacman -Rns --noconfirm phpmyadmin 2>/dev/null || true
    ok "phpMyAdmin removido"
else
    info "phpMyAdmin no instalado via pacman -- saltando"
fi

info "Node.js..."
pacman -Rns --noconfirm nodejs npm 2>/dev/null || true
ok "Node.js removido"

info "VS Code..."
# VS Code puede estar como 'code' (AUR) o 'code-oss' (repos)
pacman -Rns --noconfirm code 2>/dev/null || \
pacman -Rns --noconfirm code-oss 2>/dev/null || true
ok "VS Code removido (si estaba instalado)"

info "Google Chrome..."
# Chrome estable (AUR: google-chrome)
if pacman -Qi google-chrome &>/dev/null; then
    pacman -Rns --noconfirm google-chrome 2>/dev/null || true
    ok "Google Chrome removido"
else
    info "google-chrome no instalado via pacman -- saltando"
fi

info "Herramientas CLI..."
pacman -Rns --noconfirm \
    jq tree zip p7zip ncdu \
    ripgrep fd bat fzf \
    github-cli \
    ttf-fira-code ttf-jetbrains-mono \
    base-devel 2>/dev/null || true
ok "Herramientas CLI removidas"

info "earlyoom..."
pacman -Rns --noconfirm earlyoom 2>/dev/null || true
ok "earlyoom removido"

info "Limpieza de caché de pacman..."
pacman -Sc --noconfirm
ok "Caché de pacman limpiada"

# ---------------------------------------------------------------------------
# 4. Caché de yay (AUR helper)
# ---------------------------------------------------------------------------
step "Caché de yay"
YAY_CACHE="$REAL_HOME/.cache/yay"
if [[ -d "$YAY_CACHE" ]]; then
    rm -rf "$YAY_CACHE"
    ok "Caché de yay eliminada ($YAY_CACHE)"
else
    info "Caché de yay no encontrada -- saltando"
fi

# ---------------------------------------------------------------------------
# 5. Datos y configuracion de MariaDB
# ---------------------------------------------------------------------------
step "Datos de MariaDB"
rm -rf /var/lib/mysql /etc/my.cnf.d
ok "Datos y config de MariaDB eliminados"

# ---------------------------------------------------------------------------
# 6. Webroot y WordPress
# ---------------------------------------------------------------------------
step "Webroot /var/www/html"
rm -rf /var/www/html
mkdir -p /var/www/html
chown root:root /var/www/html
chmod 755 /var/www/html
ok "/var/www/html limpiado (directorio vacio recreado)"

rm -f /etc/httpd/conf/extra/wordpress.conf 2>/dev/null || true
# Eliminar la línea Include de wordpress.conf en httpd.conf si existe
if [[ -f /etc/httpd/conf/httpd.conf ]]; then
    sed -i '/^Include conf\/extra\/wordpress\.conf$/d' /etc/httpd/conf/httpd.conf || true
fi
ok "Config Apache/httpd WordPress eliminada"

# ---------------------------------------------------------------------------
# 7. Binarios instalados manualmente
# ---------------------------------------------------------------------------
step "Binarios en /usr/local/bin"
for bin in composer micro; do
    if [[ -e "/usr/local/bin/$bin" ]]; then
        rm -f "/usr/local/bin/$bin"
        ok "Eliminado: /usr/local/bin/$bin"
    fi
done

# ---------------------------------------------------------------------------
# 8. Configuracion de tuning
# ---------------------------------------------------------------------------
step "Configuracion de tuning"
rm -f /etc/systemd/zram-generator.conf \
      /etc/default/earlyoom \
      /etc/my.cnf.d/99-low-ram.cnf 2>/dev/null || true
ok "Archivos de tuning eliminados"

# ---------------------------------------------------------------------------
# 9. State, passwords y log del instalador
# ---------------------------------------------------------------------------
step "Estado del instalador"
rm -rf /var/lib/setup-estudiante
ok "/var/lib/setup-estudiante eliminado"

rm -f /var/log/setup-estudiante.log
ok "Log de instalacion eliminado"

# ---------------------------------------------------------------------------
# 10. Archivos del usuario
# ---------------------------------------------------------------------------
step "Archivos de usuario: $REAL_USER"

rm -f "$REAL_HOME/credenciales-instalacion.txt"
ok "credenciales-instalacion.txt eliminado"

rm -rf "$REAL_HOME/.npm-global"
ok ".npm-global eliminado"

if [[ -f "$REAL_HOME/.npmrc" ]]; then
    sudo -u "$REAL_USER" npm config delete prefix 2>/dev/null || true
    ok ".npmrc: prefix eliminado"
fi

# Eliminar bloque de 3 lineas que agrego nodejs.sh en .profile
local_profile="$REAL_HOME/.profile"
if [[ -f "$local_profile" ]] && grep -qF '.npm-global/bin' "$local_profile"; then
    sed -i '/# npm globals sin sudo (setup-estudiante)/d
            /npm-global\/bin/d' "$local_profile"
    # Eliminar lineas vacias dobles que pudieran quedar
    sed -i '/^$/{ N; /^\n$/d }' "$local_profile" || true
    ok ".profile: linea npm-global eliminada"
fi

# gitignore global -- eliminar entradas del instalador
local_gitignore="$REAL_HOME/.gitignore_global"
if [[ -f "$local_gitignore" ]]; then
    sed -i '/^credenciales-instalacion\.txt$/d
            /^\*\.env$/d
            /^\.env\.local$/d
            /^\.env\.\*\.local$/d' "$local_gitignore"
    ok ".gitignore_global: entradas del instalador eliminadas"
fi

# mkcert: desregistrar CA del trust store
if command -v mkcert &>/dev/null; then
    if sudo -u "$REAL_USER" mkcert -uninstall 2>/dev/null; then
        ok "CA de mkcert desregistrada"
    else
        warn "mkcert -uninstall fallo (no critico)"
    fi
fi

# Backups de /var/www/html creados por backup_webroot()
if compgen -G "/var/backups/setup-estudiante-*.tar.gz" >/dev/null 2>&1; then
    rm -f /var/backups/setup-estudiante-*.tar.gz
    ok "Backups de webroot eliminados"
fi

# ---------------------------------------------------------------------------
# Resumen final
# ---------------------------------------------------------------------------
echo ""
echo "================================================"
echo -e "${GREEN}  Teardown completado.${NC}"
echo ""
echo "  El sistema esta listo para una nueva ejecucion"
echo "  de: sudo bash setup-estudiante-arch/setup.sh"
echo ""
echo "  Nota: git config --global (user.name, user.email)"
echo "  de $REAL_USER no fue modificado."
echo "================================================"
