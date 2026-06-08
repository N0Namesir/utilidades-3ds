# utilidades-3ds

Herramientas de configuración para máquinas de estudiantes del tercer año de desarrollo de software.  
Todo corre en **Lubuntu 24.04 LTS** sobre hardware modesto (Intel Celeron, 4 GB RAM, 40–128 GB disco).

---

## ¿Qué instala?

Un solo script deja la máquina lista para trabajar:

| Herramienta | Versión |
|---|---|
| Apache 2 | última del repo oficial |
| PHP | última del repo oficial |
| MariaDB | última del repo oficial |
| phpMyAdmin + Adminer | última estable |
| WordPress | última estable |
| Node.js | 22 LTS (NodeSource) |
| pnpm | última |
| npm globals | serve, nodemon, prettier, eslint, json-server |
| VS Code | estable (repo Microsoft) |
| Google Chrome Dev | canal unstable |
| Tilix | terminal con paneles |
| Micro | editor de texto de terminal |
| Git | última del repo oficial |
| Composer | última estable (verificado con sha384) |
| jq, tree, ncdu, ripgrep, fd, bat, fzf, tldr | herramientas de terminal |
| HTTPie (`http`) | cliente HTTP de terminal |
| mkcert | certificados locales confiables |
| GitHub CLI (`gh`) | última estable |
| zram (zstd 50%) | swap comprimido en RAM |
| earlyoom | previene freezes por falta de RAM |

**Opcional** (se levanta a demanda, no arranca solo):

- SQL Server 2022 Express via Podman

---

## Requisitos previos

- Lubuntu 24.04 LTS recién instalado
- Conexión a internet
- Al menos 10 GB de disco libre
- Correr el script como tu usuario con `sudo`, no como root directo

---

## Uso

```bash
# Clonar el repositorio
git clone https://github.com/N0Namesir/utilidades-3ds.git
cd utilidades-3ds

# Instalación completa
sudo bash setup-estudiante/setup.sh

# Sin WordPress (si no se necesita)
sudo bash setup-estudiante/setup.sh --skip-wordpress

# Solo reinstalar un módulo específico
sudo bash setup-estudiante/setup.sh --only=mariadb

# Diagnóstico del entorno (no modifica nada)
sudo bash setup-estudiante/setup.sh --verify

# Ver todas las opciones
sudo bash setup-estudiante/setup.sh --help
```

Al terminar, el script muestra las contraseñas generadas directamente en
el terminal. **No quedan en el log.** Se guardan también en
`~/credenciales-instalacion.txt` (solo visible por tu usuario).

---

## Accesos rápidos después de la instalación

| Servicio | URL |
|---|---|
| Página de inicio | http://localhost |
| phpMyAdmin | http://localhost/phpmyadmin |
| Adminer | http://localhost/adminer.php |
| WordPress | http://localhost/wordpress |

La página de inicio en `http://localhost` muestra el estado del entorno
(versiones de PHP, Node, Git, MariaDB, earlyoom) y enlaces a todas las herramientas.

---

## SQL Server (opcional)

SQL Server usa bastante RAM. El script lo instala a demanda y detiene
Apache + MariaDB mientras corre.

```bash
# Levantar SQL Server (primera vez: descarga la imagen ~1.5 GB)
sudo bash setup-estudiante/scripts/sqlserver-up.sh

# Detener y volver a Apache + MariaDB
sudo bash setup-estudiante/scripts/sqlserver-down.sh

# Borrar todo (contenedor, volumen, imagen, contraseña)
sudo bash setup-estudiante/scripts/sqlserver-down.sh --purge
```

La contraseña del usuario `sa` se genera la primera vez que se levanta
el servidor y se guarda en `~/credenciales-instalacion.txt`.

---

## Diagnóstico y reparación

```bash
# Ver el estado de todo el entorno
sudo bash setup-estudiante/setup.sh --verify

# Ver el estado de módulos específicos
sudo bash setup-estudiante/setup.sh --verify=mariadb,apache-php

# Ver qué comando se ejecuta en cada check
sudo bash setup-estudiante/setup.sh --verify --verbose

# Reparar un módulo específico
sudo bash setup-estudiante/setup.sh --only=wordpress

# Borrar todo el estado guardado y empezar de cero
# (genera nuevas contraseñas en el próximo run)
sudo bash setup-estudiante/setup.sh --purge-state
```

El modo `--verify` tiene tres niveles de resultado:

- `[✓]` todo bien
- `[⚠]` advertencia (funcional pero subóptimo)
- `[✗]` falla — usa el comando de reparación indicado

---

## Log de instalación

```
/var/log/setup-estudiante.log   ← solo legible por root (chmod 600)
```

Si algo falla durante la instalación, el log tiene el detalle completo:

```bash
sudo tail -50 /var/log/setup-estudiante.log
```

---

## Estructura del proyecto

```
utilidades-3ds/
├── README.md
├── setup-estudiante/
│   ├── setup.sh              ← punto de entrada
│   ├── ARCHITECTURE.md       ← documentación técnica interna
│   ├── lib/                  ← módulos (uno por herramienta)
│   └── scripts/
│       ├── sqlserver-up.sh
│       └── sqlserver-down.sh
└── archivo-historico/
    └── setup-estudiante-v1.sh   ← versión monolítica original (referencia)
```

---

## Versiones

| Versión | Descripción |
|---|---|
| v1 (monolítico) | Script único, sin idempotencia. En `archivo-historico/`. |
| v2 (actual) | Modular, idempotente, con modo verify/doctor. |
