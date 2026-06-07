#!/usr/bin/env bash
# lib/verify.sh — Modo doctor.
# Sourceá cada módulo (sin disparar setup_X gracias al invariante
# "sourcing != ejecutar") y corré verify_<modulo>() si está definida.
#
# Llamado desde setup.sh cuando se pasa --verify[=mod1,mod2] [--verbose].
# NO arregla nada; solo reporta. Exit code = 1 si hay FAILs, 0 si no.

_verify_system_paths() {
    step "Sistema — permisos y archivos de estado"

    verify_check "log /var/log/setup-estudiante.log existe" \
        "[[ -f /var/log/setup-estudiante.log ]]" \
        "sudo bash setup.sh  (regenera el log con el modo correcto)"

    verify_check "log es 600 root:root" \
        "[[ \$(stat -c '%a %U' /var/log/setup-estudiante.log 2>/dev/null) == '600 root' ]]" \
        "sudo chmod 600 /var/log/setup-estudiante.log && sudo chown root:root /var/log/setup-estudiante.log"

    verify_check "STATE_DIR ($STATE_DIR) existe" \
        "[[ -d '$STATE_DIR' ]]" \
        "sudo bash setup.sh"

    verify_check "STATE_DIR es 700" \
        "[[ \$(stat -c '%a' '$STATE_DIR' 2>/dev/null) == '700' ]]" \
        "sudo chmod 700 '$STATE_DIR'"

    verify_check "passwords.env es 600" \
        "[[ \$(stat -c '%a' '$STATE_DIR/passwords.env' 2>/dev/null) == '600' ]]" \
        "sudo chmod 600 '$STATE_DIR/passwords.env'"
}

_verify_sqlserver_optional() {
    step "SQL Server (opcional)"
    if ! command -v podman &>/dev/null; then
        info "Podman no instalado — sección opcional, no es falla."
        return 0
    fi
    local state
    state=$(podman ps -a --filter "name=^sqlserver\$" --format '{{.Status}}' 2>/dev/null || true)
    if [[ "$state" =~ ^Up ]]; then
        check_ok "SQL Server container corriendo ($state)"
    elif [[ -n "$state" ]]; then
        check_warn "SQL Server container detenido" \
            "sudo bash setup-estudiante/scripts/sqlserver-up.sh"
    else
        info "SQL Server no instanciado (correcto si no lo necesitás)."
    fi
}

# Uso: run_verify [only_modules_csv] [verbose_bool]
run_verify() {
    local only_csv="${1:-}"
    export VERIFY_VERBOSE="${2:-false}"
    VERIFY_FAIL_COUNT=0
    VERIFY_WARN_COUNT=0

    echo ""
    echo "=============================================="
    echo "  Verify / doctor — entorno estudiantil"
    [[ -n "$only_csv" ]] && echo "  Filtrado: $only_csv"
    [[ "$VERIFY_VERBOSE" == true ]] && echo "  Modo: --verbose (imprime comandos)"
    echo "=============================================="

    _verify_system_paths

    local modules=(system apache-php mariadb phpmyadmin nodejs vscode
                   tools-cli chrome wordpress tuning welcome-page credentials)

    for mod in "${modules[@]}"; do
        if [[ -n "$only_csv" ]] && ! echo "$only_csv" | tr ',' '\n' | grep -qx "$mod"; then
            continue
        fi
        local file="$LIB_DIR/${mod}.sh"
        [[ -f "$file" ]] || continue
        # shellcheck disable=SC1090
        source "$file"
        local func="verify_${mod//-/_}"
        if declare -f "$func" >/dev/null; then
            step "Verificando $mod"
            "$func"
        else
            warn "Módulo '$mod' no define $func() — saltando."
        fi
    done

    [[ -z "$only_csv" ]] && _verify_sqlserver_optional

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if (( VERIFY_FAIL_COUNT == 0 )); then
        echo -e "${GREEN}  Verificación: ${VERIFY_WARN_COUNT} warnings, 0 fallas.${NC}"
        return 0
    else
        echo -e "${RED}  Verificación: ${VERIFY_FAIL_COUNT} fallas, ${VERIFY_WARN_COUNT} warnings.${NC}"
        echo "  Para reparar un módulo:  sudo bash setup.sh --only=<modulo>"
        return 1
    fi
}
