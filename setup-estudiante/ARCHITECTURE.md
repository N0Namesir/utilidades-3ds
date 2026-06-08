# Arquitectura de setup-estudiante v2.0

Documento técnico para reproducir, extender o portar este instalador a otro contexto.  
Stack objetivo: **Lubuntu 24.04 LTS** · Intel Celeron · 4 GB RAM · 40–128 GB disco.

---

## 1. Propósito y contexto

`setup-estudiante` instala y configura un entorno de desarrollo web local para alumnos
de primer año. El objetivo del diseño es que el script sea:

- **Re-ejecutable sin daño**: si algo falla a mitad, se vuelve a correr y continúa donde quedó.
- **Auditado**: todo queda en `/var/log/setup-estudiante.log` (600 root:root).
- **Reparable**: `--verify` diagnostica y `--only=X` repara un módulo específico.
- **Seguro**: ninguna contraseña queda en el log ni en el historial de shell.

---

## 2. Estructura de archivos

```
setup-estudiante/
├── setup.sh              ← Orquestador principal (único punto de entrada)
├── lib/
│   ├── common.sh         ← Helpers compartidos; debe ser el primer source
│   ├── verify.sh         ← Modo doctor (--verify); fuente de verdad de checks
│   ├── system.sh
│   ├── apache-php.sh
│   ├── mariadb.sh
│   ├── phpmyadmin.sh
│   ├── nodejs.sh
│   ├── vscode.sh
│   ├── tools-cli.sh
│   ├── chrome.sh
│   ├── wordpress.sh
│   ├── tuning.sh
│   ├── welcome-page.sh
│   └── credentials.sh
└── scripts/
    ├── sqlserver-up.sh   ← Levanta SQL Server 2022 en Podman (opcional)
    └── sqlserver-down.sh ← Detiene / purga SQL Server
```

---

## 3. Invariante fundamental: sourcing ≠ ejecución

**Todo módulo `lib/*.sh` solo define funciones. No ejecuta nada al ser sourceado.**

```bash
# CORRECTO — un módulo termina así:
setup_mariadb() { run_step "mariadb-install" _mariadb_install; ... }
verify_mariadb() { verify_check ...; ... }
# No hay ninguna llamada fuera de una función.

# INCORRECTO — rompe el invariante:
setup_mariadb   # ← llamada directa al final del archivo
```

Esto permite que `verify.sh` sourcée todos los módulos para obtener sus
funciones `verify_<modulo>()` sin disparar ninguna instalación.  
`run_module()` en `setup.sh` sourcéa y luego llama explícitamente a `setup_<modulo>()`.

---

## 4. Idempotencia por step

La unidad de idempotencia es el **step**, no el módulo.

```
/var/lib/setup-estudiante/   ← STATE_DIR (700 root:root)
    passwords.env            ← 600, contiene las 3 variables de contraseña
    system-update.done
    mariadb-install.done
    mariadb-secure.done
    ...
```

`run_step <marker> <funcion>` funciona así:

1. Si `$STATE_DIR/$marker.done` existe → skip (ya hecho).
2. Ejecuta la función y captura el exit code.
3. Si exit code ≠ 0 → `err()` aborta el script (sin crear el marker).
4. Si exit code = 0 → crea el marker → idempotente en próximo run.

El marker solo existe si el step terminó exitosamente. Un step a mitad
no deja marker, por lo que el re-run lo reintenta completo.

### Patrones seguros para funciones de step

| Patrón | Por qué es idempotente |
|---|---|
| `apt install -y PKG` | No-op si ya instalado |
| `CREATE DATABASE IF NOT EXISTS` | No-op si ya existe |
| `systemctl enable --now SVC` | No-op si ya activo |
| `ln -sf SRC DST` | Sobrescribe el symlink, resultado igual |
| `a2enmod / a2enconf` | No-op si ya habilitado |
| `mkdir -p` | No-op si ya existe |
| `grep -qF LINE FILE \|\| echo LINE >> FILE` | Agrega solo si no está |
| `cat > FILE` | Sobreescribe siempre → OK si el contenido es determinístico |

### Patrones a evitar sin guardia

| Patrón | Problema |
|---|---|
| `rm -rf` sin chequeo | Destruye estado previo en re-run |
| `wget -O DEST URL` sin `[[ -f DEST ]]` | Descarga redundante; puede fallar |
| `adduser USER` sin `id USER 2>/dev/null` | Error si el usuario ya existe |
| `ALTER USER` sin `IF EXISTS` | Falla si el usuario no fue creado todavía |

---

## 5. Flujo del orquestador (setup.sh)

```
[inicio]
    │
    ├─ Log 600 root:root ANTES del exec/tee  ← seguridad crítica
    ├─ exec > >(tee -a LOG) 2>&1             ← todo stdout+stderr capturado
    │
    ├─ Parseo de flags
    ├─ require_root / require_debian / detect_real_user
    │
    ├── ¿--purge-state?  → rm -rf STATE_DIR, exit 0
    ├── ¿--verify?       → source verify.sh; run_verify; exit $?
    │
    ├─ Generar / leer passwords.env
    │       Si existe → warn + source
    │       Si no → gen_password() × 3 → escribir 600
    │
    ├─ ¿--only=X? → borrar markers de esos módulos
    │
    ├─ run_module(system)
    ├─ run_module(apache-php)
    ├─ ...
    ├─ [skip wordpress si --skip-wordpress]
    ├─ run_module(tuning)
    ├─ run_module(welcome-page)
    └─ run_module(credentials)
         │
         └─ cat credenciales → /dev/tty  ← NO va al log
```

### Por qué /dev/tty y no stdout

`exec > >(tee -a LOG)` captura todo stdout. Si se hace `cat credenciales`
a stdout, las contraseñas quedan en el log. `/dev/tty` escribe directamente
al terminal del operador, esquivando el tee. El log queda limpio de secretos.

---

## 6. Contraseñas y secretos

### Generación

```bash
# Alfanumérica (MariaDB, phpMyAdmin, WordPress DB)
gen_password() {
    openssl rand -base64 18 | tr -d '/+=' | cut -c1-16
}

# Compleja (SQL Server SA: requiere mayúsc + minúsc + dígito + símbolo)
gen_password_complex() {
    local base sym
    base=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-14)
    sym=$(printf '%s' '!#%@_-' | fold -w1 | shuf -n1)
    printf 'Aa1%s%s\n' "$sym" "$base"
}
```

`gen_password_complex` garantiza las 4 clases de caracteres que exige SQL Server
prepending `Aa1` + un símbolo del set `!#%@_-` (seguros en shell y en connection strings).

### Almacenamiento

```
/var/lib/setup-estudiante/passwords.env   (600 root:root)
    MARIADB_ROOT_PASSWORD=...
    PHPMYADMIN_PASSWORD=...
    USER_DB_PASSWORD=...
```

`MSSQL_SA_PASSWORD` se agrega a `passwords.env` la primera vez que se corre
`scripts/sqlserver-up.sh` con `grep -qF` para no duplicar.

En re-runs, `setup.sh` sourcéa `passwords.env` y exporta las variables.
`--purge-state` borra el directorio entero → próximo run genera nuevas contraseñas.

---

## 7. Modo doctor (--verify)

Cada módulo expone `verify_<modulo>()` con checks usando dos helpers:

```bash
verify_check      "descripcion" "comando" ["hint de reparación"]
verify_check_warn "descripcion" "comando" ["hint"]   # warn, no falla
```

Niveles de resultado:

| Símbolo | Función | Efecto en exit code |
|---|---|---|
| `[✓]` | `check_ok` | ninguno |
| `[⚠]` | `check_warn` | ninguno (informativo) |
| `[✗]` | `check_fail` | incrementa VERIFY_FAIL_COUNT |

`run_verify` retorna exit 1 si `VERIFY_FAIL_COUNT > 0`.

Los checks de `verify_<modulo>` usan los mismos comandos que el propio
instalador: si el instalador usó `systemctl is-active mariadb`, el check
usa `systemctl is-active --quiet mariadb`. Coherencia garantizada.

**Regla de oro de verify**: no repara nada. Solo diagnostica y señala el
comando exacto para reparar.

---

## 8. Convenciones de nombres

| Concepto | Convención | Ejemplo |
|---|---|---|
| Función pública de módulo | `setup_<modulo>()` con guiones→underscore | `setup_apache_php()` |
| Función de verificación | `verify_<modulo>()` | `verify_apache_php()` |
| Función interna de paso | `_<modulo>_<paso>()` | `_mariadb_secure()` |
| Marker de estado | `<modulo>-<paso>` | `mariadb-secure` |
| Archivo de módulo | `lib/<modulo>.sh` con guiones | `lib/apache-php.sh` |
| Función pública en run_module | `${mod//-/_}` conversión inline | `apache-php` → `apache_php` |

La conversión guión→underscore se hace en `run_module()` y `run_verify()` con
`${mod//-/_}`. Los nombres de archivo y markers pueden tener guiones; los
nombres de función bash no pueden.

---

## 9. Variables de entorno de contexto

Exportadas por `detect_real_user()` y disponibles en todos los módulos:

| Variable | Contenido |
|---|---|
| `REAL_USER` | Usuario que invocó sudo (de `$SUDO_USER`) |
| `REAL_HOME` | Home de `REAL_USER` (vía `eval echo "~$REAL_USER"`) |
| `STATE_DIR` | `/var/lib/setup-estudiante` |
| `MARIADB_ROOT_PASSWORD` | Generada o leída de passwords.env |
| `PHPMYADMIN_PASSWORD` | Idem |
| `USER_DB_PASSWORD` | Idem |
| `MSSQL_SA_PASSWORD` | Vacía si SQL Server nunca se levantó |

`MSSQL_SA_PASSWORD` se exporta como cadena vacía si no existe para que
`${MSSQL_SA_PASSWORD:-}` no rompa bajo `set -u`.

---

## 10. Particularidades del stack en Ubuntu 24.04

Estas diferencias respecto a nombres "esperados" quemaron tiempo de debugging:

| Comando esperado | Nombre real en Ubuntu 24.04 | Solución |
|---|---|---|
| `fd` | `fdfind` | symlink `/usr/local/bin/fd → fdfind` |
| `bat` | `batcat` | symlink `/usr/local/bin/bat → batcat` |
| `mysql -u root` sin pass | Socket auth (unix_socket plugin) | usar `sudo mysql` sin `-p` en _secure |
| `mkcert -install` | Requiere correr como el usuario real, no root | `sudo -u "$REAL_USER" mkcert -install` |
| npm globals sin sudo | Requiere prefix en `~/.npm-global` | `npm config set prefix` + PATH en `.profile` |

### MariaDB y socket auth

En Ubuntu/Debian, `root@localhost` en MariaDB usa el plugin `unix_socket` por
defecto. `sudo mysql` autentica por UID sin contraseña. `_mariadb_secure()` usa
`sudo mysql` para configurar los usuarios; los módulos posteriores usan
`mysql -u root -p"$MARIADB_ROOT_PASSWORD"` (password auth) porque ya se
configuró `mysql_native_password` para root en ese paso. Si se re-ejecuta
`_mariadb_secure()`, el `ALTER USER … BY '...'` es idempotente porque
`$MARIADB_ROOT_PASSWORD` persiste en `passwords.env`.

### Node.js y el PATH del usuario

El instalador escribe en `~/.profile` una línea que agrega `~/.npm-global/bin`
al PATH. Eso requiere nuevo login para activarse. Para correr `npm install -g`
dentro del mismo script, se pasa el PATH inline:

```bash
sudo -u "$REAL_USER" env "PATH=$REAL_HOME/.npm-global/bin:$PATH" npm install -g ...
```

La línea en `.profile` usa variables literales (no expandidas en tiempo de
escritura) porque el shell del usuario las expandirá en su propio contexto:

```bash
# shellcheck disable=SC2016  ← intencional: $HOME/$PATH literales
local path_line='export PATH="$HOME/.npm-global/bin:$PATH"'
```

---

## 11. SQL Server (opcional, Podman)

`scripts/sqlserver-up.sh` gestiona un contenedor `mssql/server:2022-latest`.

Estados posibles del contenedor (detección con `podman ps -a --filter`):

1. **No existe** → crear con `podman run`
2. **Existe, detenido** → `podman start`
3. **Existe, corriendo** → no-op

Loop de readiness (90 s máx):

```bash
until sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -C -Q "SELECT 1" &>/dev/null; do
    sleep 3
done
```

`-C` (trust server certificate) es necesario con `tools-18` de sqlcmd contra
la imagen `2022-latest` que usa certificado autofirmado.

**Antes de levantar SQL Server se detienen Apache + MariaDB** (4 GB RAM no
alcanza para todo simultáneo). `sqlserver-down.sh` los restaura al terminar.

`--purge` en `sqlserver-down.sh` también borra la línea de `passwords.env`
con `sed -i '/^MSSQL_SA_PASSWORD=/d'` para que el próximo `sqlserver-up.sh`
genere una nueva contraseña.

---

## 12. Tuning de RAM (4 GB)

```
zram: ALGO=zstd, PERCENT=50
      → 2 GB de swap comprimido en RAM; ~3× más rápido que swap a disco
      → Si hay thrashing con Chrome Dev + VS Code, subir a PERCENT=75

MariaDB:
  innodb_buffer_pool_size = 128M   (default: ~70% RAM = 2.8 GB)
  key_buffer_size = 16M
  max_connections = 30
  performance_schema = OFF

Apache: a2dismod autoindex cgi status
        → reduce surface de ataque + consumo de memoria

earlyoom: -m 15,10 -s 15,10
          → warn a 15% RAM libre, kill a 10%
          → más agresivo que el default (10/10) porque con zram el
             "swap disponible" se llena tarde y el freeze ya ocurrió
```

---

## 13. Flags de setup.sh

| Flag | Efecto |
|---|---|
| `--verify` | Doctor mode: chequea todos los módulos, exit 1 si hay fallas |
| `--verify=mod1,mod2` | Doctor filtrado |
| `--verbose` | En verify: imprime cada comando antes de ejecutarlo |
| `--only=mod1,mod2` | Borra markers de esos módulos y ejecuta solo ellos |
| `--skip-wordpress` | Saltea el módulo wordpress |
| `--purge-state` | Borra STATE_DIR completo (passwords + markers), exit 0 |
| `--help` | Imprime ayuda y exit 0 |

`--only` y `--skip-wordpress` son mutuamente excluyentes (validado al inicio).

---

## 14. Seguridad en capas

| Capa | Medida |
|---|---|
| Log | 600 root:root; se crea y protege **antes** del `exec > >(tee)` |
| Contraseñas en log | Ninguna: las credenciales se muestran via `/dev/tty`, nunca stdout |
| passwords.env | 600 root:root en STATE_DIR (700) |
| credenciales-instalacion.txt | 600 owner=REAL_USER |
| gitignore global | `credenciales-instalacion.txt`, `*.env`, `.env.local` agregados por el instalador |
| Página web | Sin contraseñas hardcodeadas; estado de servicios via `systemctl is-active` |

---

## 15. Cómo agregar un módulo nuevo

1. Crear `lib/mi-modulo.sh`:

```bash
#!/usr/bin/env bash
# lib/mi-modulo.sh — descripción breve

_mi_modulo_install() {
    step "Mi Módulo"
    apt_install paquete-ejemplo
    ok "Paquete instalado"
}

setup_mi_modulo() {
    run_step "mi-modulo-install" _mi_modulo_install
}

verify_mi_modulo() {
    verify_check "paquete-ejemplo en PATH" \
        "command -v paquete-ejemplo" \
        "sudo bash setup.sh --only=mi-modulo"
}
```

2. En `setup.sh`, agregar en el lugar correcto del orden:

```bash
should_run mi-modulo && run_module mi-modulo
```

3. En `lib/verify.sh`, agregar `mi-modulo` al array `modules`:

```bash
local modules=(... mi-modulo ...)
```

Reglas:
- El archivo se llama con guiones (`mi-modulo.sh`).
- La función pública se llama con underscores (`setup_mi_modulo`).
- Los markers de step siguen el patrón `mi-modulo-<paso>`.
- Toda función interna empieza con `_` para indicar que es privada.
- `setup_mi_modulo()` no llama a nada fuera de `run_step`; los detalles van en `_mi_modulo_*()`.
