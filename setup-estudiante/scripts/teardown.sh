#!/usr/bin/env bash
# =============================================================================
# teardown.sh -- Elimina TODO lo instalado por setup.sh para permitir
# pruebas repetibles sin restaurar snapshot.
#
# USO: sudo bash setup-estudiante/scripts/teardown.sh
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
echo "  Afectado: Apache, PHP, MariaDB, Node, VS Code, Chrome,"
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
# Funcion helper: purgar un paquete ignorando si no esta instalado
# ---------------------------------------------------------------------------
purge_pkg() {
    if dpkg -l "$1" &>/dev/null; then
        apt-get purge -y "$@"
        ok "$1 purgado"
    else
        info "$1 no instalado -- saltando"
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
    purge_pkg podman
else
    info "Podman no instalado -- saltando"
fi

# ---------------------------------------------------------------------------
# 2. Servicios: detener antes de purgar
# ---------------------------------------------------------------------------
step "Detener servicios"
for svc in apache2 mariadb earlyoom zramswap; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        systemctl stop    "$svc" || true
        ok "$svc detenido"
    fi
    systemctl disable "$svc" 2>/dev/null || true
done

# ---------------------------------------------------------------------------
# 3. Paquetes apt -- purge en grupos logicos
# ---------------------------------------------------------------------------
step "Purge de paquetes apt"

info "Apache + PHP..."
apt-get purge -y \
    apache2 apache2-bin apache2-data apache2-utils \
    php php-cli php-common \
    libapache2-mod-php \
    php-mysql php-curl php-gd php-mbstring php-xml php-zip php-intl \
    php-imagick imagemagick 2>/dev/null || true
ok "Apache + PHP purgados"

info "MariaDB..."
apt-get purge -y mariadb-server mariadb-client mariadb-common \
    libmariadb3 2>/dev/null || true
ok "MariaDB purgado"

info "phpMyAdmin..."
apt-get purge -y phpmyadmin 2>/dev/null || true
ok "phpMyAdmin purgado"

info "Node.js..."
apt-get purge -y nodejs npm 2>/dev/null || true
ok "Node.js purgado"

info "VS Code..."
apt-get purge -y code 2>/dev/null || true
ok "VS Code purgado"

info "Google Chrome Dev..."
apt-get purge -y google-chrome-unstable 2>/dev/null || true
ok "Chrome Dev purgado"

info "Herramientas CLI..."
apt-get purge -y \
    tilix \
    jq tree zip p7zip-full ncdu \
    ripgrep fd-find bat fzf tldr mkcert httpie \
    gh \
    fonts-firacode fonts-jetbrains-mono \
    build-essential 2>/dev/null || true
ok "Herramientas CLI purgadas"

info "zram + earlyoom..."
apt-get purge -y zram-tools earlyoom 2>/dev/null || true
ok "zram + earlyoom purgados"

info "Paquetes base adicionales..."
apt-get purge -y software-properties-common apt-transport-https 2>/dev/null || true
ok "Paquetes base adicionales purgados"

info "autoremove + clean..."
apt-get autoremove -y
apt-get clean
ok "Dependencias huerfanas eliminadas"

# ---------------------------------------------------------------------------
# 4. Repositorios y keyrings de terceros
# ---------------------------------------------------------------------------
step "Repositorios y keyrings de terceros"
for f in \
    /etc/apt/sources.list.d/vscode.list \
    /etc/apt/sources.list.d/nodesource.list \
    /etc/apt/sources.list.d/github-cli.list \
    /etc/apt/keyrings/microsoft.gpg \
    /etc/apt/keyrings/githubcli-archive-keyring.gpg; do
    if [[ -f "$f" ]]; then
        rm -f "$f"
        ok "Eliminado: $f"
    fi
done
apt-get update -qq
ok "apt update tras eliminar repos de terceros"

# ---------------------------------------------------------------------------
# 5. Datos y configuracion de MariaDB
# ---------------------------------------------------------------------------
step "Datos de MariaDB"
rm -rf /var/lib/mysql /etc/mysql
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

rm -f /etc/apache2/conf-available/wordpress-overrides.conf \
      /etc/apache2/conf-enabled/wordpress-overrides.conf 2>/dev/null || true
ok "Config Apache WordPress eliminada"

# ---------------------------------------------------------------------------
# 7. Binarios instalados manualmente
# ---------------------------------------------------------------------------
step "Binarios en /usr/local/bin"
for bin in composer fd bat micro; do
    if [[ -e "/usr/local/bin/$bin" ]]; then
        rm -f "/usr/local/bin/$bin"
        ok "Eliminado: /usr/local/bin/$bin"
    fi
done

# ---------------------------------------------------------------------------
# 8. Configuracion de tuning
# ---------------------------------------------------------------------------
step "Configuracion de tuning"
rm -f /etc/default/zramswap \
      /etc/default/earlyoom \
      /etc/mysql/mariadb.conf.d/99-low-ram.cnf 2>/dev/null || true
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
echo "  de: sudo bash setup-estudiante/setup.sh"
echo ""
echo "  Nota: git config --global (user.name, user.email)"
echo "  de $REAL_USER no fue modificado."
echo "================================================"
