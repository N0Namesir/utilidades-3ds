#!/usr/bin/env bash
# scripts/sqlserver-down.sh — Detiene SQL Server y reinicia httpd + MariaDB.
# Uso:
#   sudo bash sqlserver-down.sh           detiene container, conserva volumen
#   sudo bash sqlserver-down.sh --purge   detiene + borra container/volumen/imagen
#                                         y remueve MSSQL_SA_PASSWORD de passwords.env

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"

CONTAINER="sqlserver"
VOLUME="sqlserver-data"
IMAGE="mcr.microsoft.com/mssql/server:2022-latest"
PASSWORDS_FILE="$STATE_DIR/passwords.env"

PURGE=false
[[ "${1:-}" == "--purge" ]] && PURGE=true

require_root

if ! command -v podman &>/dev/null; then
    err "Podman no está instalado, nada que detener."
fi

# --- 1. Detener container si existe ---
if podman ps -a --filter "name=^${CONTAINER}\$" --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    info "Deteniendo container $CONTAINER..."
    podman stop "$CONTAINER" >/dev/null || warn "Container no estaba corriendo"
    podman rm   "$CONTAINER" >/dev/null
    ok "Container eliminado"
else
    info "No hay container $CONTAINER."
fi

# --- 2. Purga opcional ---
if [[ "$PURGE" == true ]]; then
    if podman volume inspect "$VOLUME" &>/dev/null; then
        podman volume rm "$VOLUME" >/dev/null
        ok "Volumen $VOLUME eliminado"
    fi
    if podman image inspect "$IMAGE" &>/dev/null; then
        podman rmi "$IMAGE" >/dev/null
        ok "Imagen $IMAGE eliminada"
    fi
    # Remover MSSQL_SA_PASSWORD de passwords.env (sed -i in-place).
    if [[ -f "$PASSWORDS_FILE" ]] && grep -qF "MSSQL_SA_PASSWORD=" "$PASSWORDS_FILE"; then
        sed -i '/^MSSQL_SA_PASSWORD=/d' "$PASSWORDS_FILE"
        ok "MSSQL_SA_PASSWORD removida de $PASSWORDS_FILE"
    fi
    rm -f "$STATE_DIR/sqlserver-eula-accepted"
    ok "Purga completa"
fi

# --- 3. Reiniciar httpd + MariaDB ---
info "Reiniciando httpd y MariaDB..."
systemctl start mariadb || warn "No se pudo arrancar mariadb"
systemctl start httpd   || warn "No se pudo arrancar httpd"
ok "Stack LAMP nativo de vuelta en marcha"
