#!/usr/bin/env bash
# lib/welcome-page.sh — Página de bienvenida local (/var/www/html/index.php).

_welcome_install() {
    step "Página de bienvenida"
    backup_webroot
    rm -f /var/www/html/index.html

    cat > /var/www/html/index.php << 'PHPEOF'
<?php
$phpVersion  = phpversion();
$nodeVersion = trim(shell_exec('node -v 2>/dev/null') ?: 'no disponible');
$gitVersion  = trim(shell_exec('git --version 2>/dev/null') ?: 'no disponible');
// Fix bug #1: no usar credenciales root hardcodeadas en una página servida
// públicamente. systemctl is-active no requiere password y refleja el
// estado real del daemon.
$mysqlStatus    = (trim(shell_exec('systemctl is-active mariadb 2>/dev/null')  ?: '') === 'active') ? 'activo' : 'inactivo';
$earlyoomStatus = (trim(shell_exec('systemctl is-active earlyoom 2>/dev/null') ?: '') === 'active') ? 'activo' : 'inactivo';
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
    <div class="card"><div class="card-label">earlyoom</div><div class="card-value <?= $earlyoomStatus === 'activo' ? 'green' : 'warn' ?>"><?= $earlyoomStatus ?></div></div>
  </div>

  <div class="section-title">Accesos rápidos</div>
  <div class="links">
    <a class="link-card" href="/phpmyadmin" target="_blank">
      <span class="link-icon">🗄️</span>
      <div class="link-text"><div class="link-title">phpMyAdmin</div><div class="link-url">localhost/phpmyadmin</div></div>
    </a>
    <a class="link-card" href="/adminer.php" target="_blank">
      <span class="link-icon">⚡</span>
      <div class="link-text"><div class="link-title">Adminer</div><div class="link-url">localhost/adminer.php</div></div>
    </a>
    <a class="link-card" href="/wordpress" target="_blank">
      <span class="link-icon">🌐</span>
      <div class="link-text"><div class="link-title">WordPress</div><div class="link-url">localhost/wordpress</div></div>
    </a>
    <div class="link-card" title="Levantar a demanda con: sudo bash setup-estudiante/scripts/sqlserver-up.sh" style="cursor:help">
      <span class="link-icon">🧊</span>
      <div class="link-text"><div class="link-title">SQL Server (opcional)</div><div class="link-url">scripts/sqlserver-up.sh</div></div>
    </div>
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
<footer><?= date('Y') ?> — Apache activo · MariaDB <?= $mysqlStatus ?> · PHP <?= $phpVersion ?> · <code>sudo bash setup.sh --verify</code> para diagnosticar</footer>
</body>
</html>
PHPEOF

    chown "$REAL_USER":www-data /var/www/html/index.php
    ok "Página de bienvenida instalada → http://localhost"
}

setup_welcome_page() {
    run_step "welcome-page-install" _welcome_install
}

verify_welcome_page() {
    verify_check "/var/www/html/index.php existe" \
        "[[ -f /var/www/html/index.php ]]" \
        "sudo bash setup.sh --only=welcome-page"
    verify_check "index.php usa systemctl is-active (no PDO con pass hardcodeada)" \
        "grep -q 'systemctl is-active mariadb' /var/www/html/index.php" \
        "sudo bash setup.sh --only=welcome-page"
    verify_check "welcome page sirve HTTP 200 en /" \
        "curl -fsS -o /dev/null http://localhost/" \
        "sudo systemctl status apache2"
}

