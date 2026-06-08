#!/bin/bash

# =============================================================================
# Script de configuración automática — Entorno de desarrollo estudiantil
# Versión: 1.1 — Junio 2026
# Uso: sudo bash setup-estudiante.sh
# =============================================================================

set -e

# =============================================================================
# VARIABLES — Ajustar antes de ejecutar
# =============================================================================

MARIADB_ROOT_PASSWORD="rootpass"
PHPMYADMIN_PASSWORD="accesoadmin"

# =============================================================================
# COLORES
# =============================================================================

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[✓]${NC} $1"; }
info() { echo -e "${BLUE}[→]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# =============================================================================
# CABECERA
# =============================================================================

echo ""
echo "=============================================="
echo "  Configuración Entorno Estudiantil"
echo "  Desarrollo Web — Versión 1.1"
echo "=============================================="
echo ""

# =============================================================================
# VALIDACIONES
# =============================================================================

if [ "$EUID" -ne 0 ]; then
  err "Ejecutar como root: sudo bash setup-estudiante.sh"
fi

if [ -z "$MARIADB_ROOT_PASSWORD" ]; then
  err "Falta MARIADB_ROOT_PASSWORD. Editá el script y agregá una contraseña."
fi

# Detectar el usuario real (quien ejecutó sudo)
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(eval echo "~$REAL_USER")

info "Usuario detectado: $REAL_USER (home: $REAL_HOME)"

# =============================================================================
# PASO 1 — Actualizar sistema
# =============================================================================

info "Actualizando sistema..."
apt update && apt upgrade -y
ok "Sistema actualizado"

# =============================================================================
# PASO 2 — Paquetes base y utilidades
# =============================================================================

info "Instalando paquetes base..."
apt install -y \
  curl \
  wget \
  git \
  unzip \
  software-properties-common \
  apt-transport-https \
  ca-certificates \
  gnupg \
  lsb-release
ok "Paquetes base instalados"

# =============================================================================
# PASO 3 — Apache y PHP
# =============================================================================

info "Instalando Apache y PHP..."
apt install -y apache2 php libapache2-mod-php php-mysql php-mbstring php-zip php-gd php-curl php-xml
systemctl enable apache2
systemctl start apache2
ok "Apache y PHP instalados"

info "Habilitando mod_rewrite para Apache..."
a2enmod rewrite
systemctl restart apache2
ok "mod_rewrite habilitado"

# =============================================================================
# PASO 4 — MariaDB
# =============================================================================

info "Instalando MariaDB..."
apt install -y mariadb-server
systemctl enable mariadb
systemctl start mariadb
ok "MariaDB instalado"

info "Asegurando MariaDB..."
sudo mysql << EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MARIADB_ROOT_PASSWORD}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
ok "MariaDB asegurado"

# =============================================================================
# PASO 5 — phpMyAdmin
# =============================================================================

info "Instalando phpMyAdmin..."
export DEBIAN_FRONTEND=noninteractive
echo "phpmyadmin phpmyadmin/dbconfig-install boolean true"                        | debconf-set-selections
echo "phpmyadmin phpmyadmin/app-password-confirm password ${PHPMYADMIN_PASSWORD}" | debconf-set-selections
echo "phpmyadmin phpmyadmin/mysql/admin-pass password ${MARIADB_ROOT_PASSWORD}"   | debconf-set-selections
echo "phpmyadmin phpmyadmin/mysql/app-pass password ${PHPMYADMIN_PASSWORD}"       | debconf-set-selections
echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2"            | debconf-set-selections
apt install -y phpmyadmin
ln -sf /usr/share/phpmyadmin /var/www/html/phpmyadmin
ok "phpMyAdmin instalado → http://localhost/phpmyadmin"

# =============================================================================
# PASO 6 — Node.js 22 LTS + pnpm
# =============================================================================

info "Instalando Node.js 22 LTS..."
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt install -y nodejs
ok "Node.js $(node -v) instalado"

info "Instalando pnpm..."
npm install -g pnpm
ok "pnpm $(pnpm -v) instalado"

# =============================================================================
# PASO 7 — VS Code (repositorio oficial .deb)
# =============================================================================

info "Agregando repositorio oficial de VS Code..."
wget -qO- https://packages.microsoft.com/keys/microsoft.asc \
  | gpg --dearmor > /etc/apt/keyrings/microsoft.gpg
chmod a+r /etc/apt/keyrings/microsoft.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/microsoft.gpg] \
  https://packages.microsoft.com/repos/code stable main" \
  | tee /etc/apt/sources.list.d/vscode.list > /dev/null
apt update
apt install -y code
ok "VS Code instalado"

# =============================================================================
# PASO 8 — Tilix (emulador de terminal)
# =============================================================================

info "Instalando Tilix..."
apt install -y tilix
ok "Tilix instalado"

# =============================================================================
# PASO 9 — Micro (editor de terminal, binario oficial)
# =============================================================================

info "Instalando Micro desde binario oficial..."
MICRO_VERSION="2.0.15"
MICRO_URL="https://github.com/micro-editor/micro/releases/download/v${MICRO_VERSION}/micro-${MICRO_VERSION}-linux64.tar.gz"
MICRO_TMP=$(mktemp -d)

wget -qO "$MICRO_TMP/micro.tar.gz" "$MICRO_URL"
tar -xzf "$MICRO_TMP/micro.tar.gz" -C "$MICRO_TMP"
install -m 755 "$MICRO_TMP/micro-${MICRO_VERSION}/micro" /usr/local/bin/micro
rm -rf "$MICRO_TMP"
ok "Micro $(micro --version) instalado en /usr/local/bin/micro"

# =============================================================================
# PASO 10 — Google Chrome Dev
# =============================================================================

info "Instalando Google Chrome Dev..."
CHROME_TMP=$(mktemp -d)
wget -qO "$CHROME_TMP/chrome-dev.deb" \
  "https://dl.google.com/linux/direct/google-chrome-unstable_current_amd64.deb"
apt install -y "$CHROME_TMP/chrome-dev.deb"
rm -rf "$CHROME_TMP"
ok "Google Chrome Dev instalado"

# =============================================================================
# PASO 11 — WordPress (descarga lista para instalar)
# =============================================================================

info "Descargando WordPress..."
WORDPRESS_DIR="/var/www/html/wordpress"

if [ -d "$WORDPRESS_DIR" ]; then
  warn "WordPress ya existe en $WORDPRESS_DIR, omitiendo descarga"
else
  wget -qO /tmp/wordpress.tar.gz https://wordpress.org/latest.tar.gz
  tar -xzf /tmp/wordpress.tar.gz -C /var/www/html/
  rm -f /tmp/wordpress.tar.gz
  chown -R "$REAL_USER":www-data "$WORDPRESS_DIR"
  chmod -R 775 "$WORDPRESS_DIR"
  ok "WordPress descargado → http://localhost/wordpress"
fi

info "Creando base de datos para WordPress..."
mysql -u root -p"${MARIADB_ROOT_PASSWORD}" << EOF
CREATE DATABASE IF NOT EXISTS wordpress CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${REAL_USER}'@'localhost' IDENTIFIED BY '${REAL_USER}';
GRANT ALL PRIVILEGES ON wordpress.* TO '${REAL_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF
ok "Base de datos 'wordpress' lista (user: $REAL_USER)"

# =============================================================================
# PASO 12 — Permisos sobre /var/www/html para el usuario
# =============================================================================

info "Configurando permisos en /var/www/html para $REAL_USER..."
usermod -aG www-data "$REAL_USER"
chown -R "$REAL_USER":www-data /var/www/html
chmod -R 775 /var/www/html
ok "Permisos configurados (grupo www-data)"

# =============================================================================
# PASO 13 — Crear base de datos personal del estudiante
# =============================================================================

info "Creando base de datos local 'desarrollo'..."
mysql -u root -p"${MARIADB_ROOT_PASSWORD}" << EOF
CREATE DATABASE IF NOT EXISTS desarrollo CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${REAL_USER}'@'localhost' IDENTIFIED BY '${REAL_USER}';
GRANT ALL PRIVILEGES ON desarrollo.* TO '${REAL_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF
ok "Base de datos 'desarrollo' creada — usuario: $REAL_USER / pass: $REAL_USER"

# =============================================================================
# PASO 14 — Página de bienvenida local
# =============================================================================

info "Instalando página de bienvenida..."
rm -f /var/www/html/index.html

cat > /var/www/html/index.php << 'PHPEOF'
<?php
$phpVersion  = phpversion();
$nodeVersion = trim(shell_exec('node -v 2>/dev/null') ?: 'no disponible');
$gitVersion  = trim(shell_exec('git --version 2>/dev/null') ?: 'no disponible');
$mysqlStatus = 'inactivo';
try {
  new PDO('mysql:host=localhost', 'root', 'rootpass');
  $mysqlStatus = 'activo';
} catch (Exception $e) {}
?>
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Entorno de Desarrollo Local</title>
<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500&family=IBM+Plex+Sans:wght@300;400;500;600&display=swap" rel="stylesheet">
<style>
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
:root{--bg:#0f1117;--surface:#181c25;--border:#252a36;--accent:#4f8ef7;--accent2:#38c96b;--warn:#f0a854;--text:#e2e8f0;--muted:#64748b}
body{background:var(--bg);color:var(--text);font-family:'IBM Plex Sans',sans-serif;min-height:100vh;display:flex;flex-direction:column}
header{background:var(--surface);border-bottom:1px solid var(--border);padding:0 32px;height:56px;display:flex;align-items:center;gap:12px}
.dot{width:8px;height:8px;border-radius:50%;background:var(--accent2);box-shadow:0 0 8px var(--accent2);animation:pulse 2s infinite}
@keyframes pulse{0%,100%{opacity:1}50%{opacity:.4}}
.logo{font-family:'IBM Plex Mono',monospace;font-size:13px;letter-spacing:.05em}
.logo span{color:var(--accent)}
main{max-width:900px;margin:48px auto;padding:0 24px;flex:1;width:100%}
h1{font-size:22px;font-weight:600;margin-bottom:8px}
.subtitle{color:var(--muted);font-size:14px;margin-bottom:40px}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(200px,1fr));gap:16px;margin-bottom:40px}
.card{background:var(--surface);border:1px solid var(--border);border-radius:8px;padding:20px}
.card-label{font-family:'IBM Plex Mono',monospace;font-size:10px;color:var(--muted);text-transform:uppercase;letter-spacing:.1em;margin-bottom:8px}
.card-value{font-size:16px;font-weight:600;word-break:break-all}
.card-value.blue{color:var(--accent)}.card-value.green{color:var(--accent2)}.card-value.warn{color:var(--warn)}
.links{display:grid;grid-template-columns:repeat(auto-fill,minmax(200px,1fr));gap:12px;margin-bottom:40px}
.link-card{background:var(--surface);border:1px solid var(--border);border-radius:8px;padding:16px 20px;text-decoration:none;transition:border-color .2s;display:flex;align-items:center;gap:12px}
.link-card:hover{border-color:var(--accent)}
.link-icon{font-size:20px}
.link-text{flex:1}
.link-title{font-size:13px;font-weight:500;color:var(--text)}
.link-url{font-family:'IBM Plex Mono',monospace;font-size:11px;color:var(--muted)}
.section-title{font-family:'IBM Plex Mono',monospace;font-size:11px;color:var(--muted);text-transform:uppercase;letter-spacing:.1em;margin-bottom:12px;padding-bottom:8px;border-bottom:1px solid var(--border)}
footer{border-top:1px solid var(--border);padding:16px 32px;font-family:'IBM Plex Mono',monospace;font-size:11px;color:var(--muted)}
</style>
</head>
<body>
<header>
  <div class="dot"></div>
  <span class="logo">localhost / <span>entorno estudiantil</span></span>
</header>
<main>
  <h1>Entorno de Desarrollo Local</h1>
  <p class="subtitle">Todo listo para trabajar. Accedé a tus herramientas desde aquí.</p>

  <div class="section-title">Estado del entorno</div>
  <div class="grid" style="margin-bottom:32px">
    <div class="card"><div class="card-label">PHP</div><div class="card-value blue"><?= $phpVersion ?></div></div>
    <div class="card"><div class="card-label">Node.js</div><div class="card-value green"><?= $nodeVersion ?></div></div>
    <div class="card"><div class="card-label">Git</div><div class="card-value warn"><?= htmlspecialchars($gitVersion) ?></div></div>
    <div class="card"><div class="card-label">MariaDB</div><div class="card-value <?= $mysqlStatus === 'activo' ? 'green' : 'warn' ?>"><?= $mysqlStatus ?></div></div>
  </div>

  <div class="section-title">Accesos rápidos</div>
  <div class="links">
    <a class="link-card" href="/phpmyadmin" target="_blank">
      <span class="link-icon">🗄️</span>
      <div class="link-text"><div class="link-title">phpMyAdmin</div><div class="link-url">localhost/phpmyadmin</div></div>
    </a>
    <a class="link-card" href="/wordpress" target="_blank">
      <span class="link-icon">🌐</span>
      <div class="link-text"><div class="link-title">WordPress</div><div class="link-url">localhost/wordpress</div></div>
    </a>
    <a class="link-card" href="https://github.com" target="_blank">
      <span class="link-icon">🐙</span>
      <div class="link-text"><div class="link-title">GitHub</div><div class="link-url">github.com</div></div>
    </a>
    <a class="link-card" href="https://developer.mozilla.org/es/" target="_blank">
      <span class="link-icon">📖</span>
      <div class="link-text"><div class="link-title">MDN Docs</div><div class="link-url">developer.mozilla.org</div></div>
    </a>
  </div>
</main>
<footer><?= date('Y') ?> — Apache activo · MariaDB <?= $mysqlStatus ?> · PHP <?= $phpVersion ?></footer>
</body>
</html>
PHPEOF

chown "$REAL_USER":www-data /var/www/html/index.php
ok "Página de bienvenida instalada → http://localhost"

# =============================================================================
# RESUMEN FINAL
# =============================================================================

echo ""
echo "=============================================="
echo -e "${GREEN}  Configuración completada exitosamente${NC}"
echo "=============================================="
echo ""
echo "  Usuario:         $REAL_USER"
echo "  Apache:          http://localhost"
echo "  phpMyAdmin:      http://localhost/phpmyadmin"
echo "  WordPress:       http://localhost/wordpress"
echo "  MariaDB root:    $MARIADB_ROOT_PASSWORD"
echo "  DB desarrollo:   desarrollo  (user: $REAL_USER / pass: $REAL_USER)"
echo "  DB wordpress:    wordpress   (user: $REAL_USER / pass: $REAL_USER)"
echo "  Node.js:         $(node -v)"
echo "  pnpm:            $(pnpm -v)"
echo "  VS Code:         code ."
echo "  Terminal:        tilix"
echo "  Editor micro:    micro <archivo>"
echo "  Chrome Dev:      google-chrome-unstable"
echo ""
echo -e "${YELLOW}  Pendiente (manual):${NC}"
echo "  - Configurar nombre y email en Git:"
echo "    git config --global user.name  'Tu Nombre'"
echo "    git config --global user.email 'tu@email.com'"
echo "  - Cerrar sesión y volver a entrar para que apliquen"
echo "    los permisos del grupo www-data"
echo "  - Completar instalación de WordPress en:"
echo "    http://localhost/wordpress"
echo ""
