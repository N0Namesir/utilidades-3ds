#!/usr/bin/env bash
# scripts/sqlserver-up.sh — Levanta SQL Server Express en Podman.
# Antes detiene httpd + MariaDB para liberar RAM (en 4 GB importa).
# Idempotente: si el container ya está corriendo, no hace nada.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"

CONTAINER="sqlserver"
VOLUME="sqlserver-data"
IMAGE="mcr.microsoft.com/mssql/server:2022-latest"
PORT=1433
EULA_MARKER="$STATE_DIR/sqlserver-eula-accepted"
PASSWORDS_FILE="$STATE_DIR/passwords.env"

require_root

# --- 1. Podman presente ---
if ! command -v podman &>/dev/null; then
    err "Podman no está instalado.
   Editá setup-estudiante-arch/setup.sh y descomentá la sección de Podman,
   después corré: sudo bash setup.sh --only=tools-cli"
fi

# --- 2. EULA (una sola vez) ---
if [[ ! -f "$EULA_MARKER" ]]; then
    [[ -t 0 ]] || err "EULA pendiente y no hay TTY. Corré desde una terminal interactiva."
    echo ""
    echo "Vas a aceptar la EULA de SQL Server 2022 Express y descargar ~1.5 GB."
    echo "Más info: https://go.microsoft.com/fwlink/?linkid=857698"
    read -r -p "¿Continuar? [s/N]: " resp < /dev/tty
    [[ "$resp" =~ ^[sSyY]$ ]] || err "Cancelado por el usuario."
    mkdir -p "$STATE_DIR"
    touch "$EULA_MARKER"
    ok "EULA aceptada (no se vuelve a preguntar)"
fi

# --- 3. Estado del container ---
state=$(podman ps -a --filter "name=^${CONTAINER}\$" --format '{{.Status}}' 2>/dev/null || true)
if [[ "$state" =~ ^Up ]]; then
    ok "SQL Server ya está corriendo."
    podman ps --filter "name=^${CONTAINER}\$" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
    exit 0
fi

# --- 4. Liberar RAM ---
info "Deteniendo httpd y MariaDB para liberar RAM..."
systemctl stop httpd   || warn "httpd no estaba corriendo"
systemctl stop mariadb || warn "mariadb no estaba corriendo"

# --- 5. Password sa: reusar o generar + append a passwords.env ---
SA_PASSWORD=""
if [[ -f "$PASSWORDS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$PASSWORDS_FILE"
    SA_PASSWORD="${MSSQL_SA_PASSWORD:-}"
fi
if [[ -z "$SA_PASSWORD" ]]; then
    SA_PASSWORD=$(gen_password_complex)
    mkdir -p "$STATE_DIR"
    # grep -qF evita duplicar si ya existe la clave
    if ! grep -qF "MSSQL_SA_PASSWORD=" "$PASSWORDS_FILE" 2>/dev/null; then
        echo "MSSQL_SA_PASSWORD=${SA_PASSWORD}" >> "$PASSWORDS_FILE"
    fi
    chmod 600 "$PASSWORDS_FILE"
    ok "Password sa generado y persistido en $PASSWORDS_FILE"
fi

# --- 6. Volumen ---
podman volume inspect "$VOLUME" &>/dev/null || podman volume create "$VOLUME"

# --- 7. Start o Run ---
if [[ -n "$state" ]]; then
    info "Container existe detenido — arrancando..."
    podman start "$CONTAINER"
else
    info "Descargando imagen y arrancando container (puede tardar)..."
    podman run -d \
        --name "$CONTAINER" \
        -e "ACCEPT_EULA=Y" \
        -e "MSSQL_SA_PASSWORD=${SA_PASSWORD}" \
        -e "MSSQL_PID=Express" \
        -p "${PORT}:1433" \
        -v "${VOLUME}:/var/opt/mssql" \
        "$IMAGE"
fi

# --- 8. Espera por readiness ---
info "Esperando que SQL Server acepte conexiones (timeout 90s)..."
deadline=$((SECONDS + 90))
while (( SECONDS < deadline )); do
    if podman exec "$CONTAINER" \
        /opt/mssql-tools18/bin/sqlcmd -C -S localhost -U sa \
        -P "$SA_PASSWORD" -Q 'SELECT 1' &>/dev/null; then
        ok "SQL Server listo."
        echo ""
        echo "  Host     : localhost"
        echo "  Puerto   : $PORT"
        echo "  Usuario  : sa"
        echo "  Password : (ver $PASSWORDS_FILE o ~/credenciales-instalacion.txt)"
        echo ""
        echo "  Detener  : sudo bash $SCRIPT_DIR/sqlserver-down.sh"
        echo "  Purgar   : sudo bash $SCRIPT_DIR/sqlserver-down.sh --purge"
        exit 0
    fi
    sleep 3
done

err "SQL Server no respondió en 90s. Revisá: podman logs $CONTAINER"
