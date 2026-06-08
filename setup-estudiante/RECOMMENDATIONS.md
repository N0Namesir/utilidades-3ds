# Recomendaciones a futuro

Mejoras opcionales que no justifican un módulo propio pero que pueden
marcar la diferencia en hardware limitado o en función de los contenidos
que se dicten.

---

## Navegador más ligero

Google Chrome Dev consume entre 500 MB y 1.5 GB de RAM con pocas pestañas
abiertas. En máquinas con 4 GB compartidos con Apache, MariaDB y VS Code,
esto puede saturar el sistema.

**Alternativas a considerar:**

**Firefox ESR** — buen soporte de estándares web, menos RAM que Chrome Dev,
ciclo de actualizaciones más estable. Ideal si se trabaja con compatibilidad
entre navegadores.

```bash
sudo apt install firefox-esr
```

**Chromium** — base open source de Chrome, sin telemetría, menor consumo.
Disponible directo en los repos de Ubuntu.

```bash
sudo apt install chromium-browser
```

**Midori** — navegador ultraligero basado en WebKit. Recomendado solo si la
máquina tiene menos de 3 GB de RAM disponibles y el uso web es básico.

```bash
sudo apt install midori
```

---

## Docker / Docker Compose

Para proyectos que requieran entornos reproducibles o trabajar con
microservicios. No se incluyó en el instalador base porque en 4 GB de RAM
Docker compite directamente con el stack LAMP.

Repo oficial de Docker para Ubuntu 24.04:

```bash
# Agregar el repo oficial
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) \
    signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu noble stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt update
sudo apt install docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo usermod -aG docker $USER
```

> Nota: si se usa SQL Server vía Podman, considerar que Docker y Podman
> pueden coexistir pero compiten por los mismos puertos.

---

## DBeaver (cliente de base de datos universal)

Alternativa a phpMyAdmin y Adminer con soporte para MariaDB, PostgreSQL,
SQLite, SQL Server y más desde una interfaz de escritorio.

```bash
# Descargar el .deb desde el repo oficial
wget -O /tmp/dbeaver.deb https://dbeaver.io/files/dbeaver-ce_latest_amd64.deb
sudo apt install /tmp/dbeaver.deb
```

---

## PostgreSQL

Si el plan de estudios incluye PostgreSQL además de MariaDB. No se instaló
por defecto para no consumir RAM innecesariamente.

```bash
sudo apt install postgresql postgresql-contrib
# Habilitar y arrancar
sudo systemctl enable --now postgresql
```

Para gestión web, **pgAdmin 4** tiene un repo oficial:

```bash
curl -fsS https://www.pgadmin.org/static/packages_pgadmin_org.pub \
    | sudo gpg --dearmor -o /etc/apt/keyrings/packages-pgadmin-org.gpg
sudo sh -c 'echo "deb [signed-by=/etc/apt/keyrings/packages-pgadmin-org.gpg] \
    https://ftp.postgresql.org/pub/pgadmin/pgadmin4/apt/noble pgadmin4 main" \
    > /etc/apt/sources.list.d/pgadmin4.list'
sudo apt update
sudo apt install pgadmin4-web
```

---

## Aumentar zram al 75%

El instalador usa `PERCENT=50` (2 GB de swap comprimido) como valor
conservador. Si el sistema muestra thrashing frecuente con Chrome Dev +
VS Code + Apache abiertos simultáneamente, subir al 75%:

```bash
sudo sed -i 's/PERCENT=50/PERCENT=75/' /etc/default/zramswap
sudo systemctl restart zramswap
```

---

## Ampliar el disco virtual

Si la VM se queda sin espacio (el stack completo ocupa ~6–8 GB):

1. Apagar la VM
2. En VirtualBox: Archivo → Herramientas → Administrador de medios virtuales → Propiedades → aumentar tamaño
3. Arrancar la VM y extender la partición:

```bash
sudo apt install cloud-guest-utils
sudo growpart /dev/sda 1
sudo resize2fs /dev/sda1
```

---

## PHP en versión específica

Ubuntu 24.04 instala PHP 8.3 por defecto. Si algún proyecto requiere una
versión anterior (8.1, 8.2), el repo de Ondřej Surý es el estándar:

```bash
sudo add-apt-repository ppa:ondrej/php
sudo apt update
sudo apt install php8.1 libapache2-mod-php8.1 php8.1-mysql php8.1-curl \
    php8.1-gd php8.1-mbstring php8.1-xml php8.1-zip
# Cambiar la versión activa de Apache
sudo a2dismod php8.3
sudo a2enmod php8.1
sudo systemctl restart apache2
```

---

## Alias útiles para el usuario

Agregar a `~/.bash_aliases` o `~/.bashrc`:

```bash
# Atajos de Apache y MariaDB
alias apache-restart='sudo systemctl restart apache2'
alias apache-log='sudo tail -f /var/log/apache2/error.log'
alias mysql-root='mysql -u root -p'

# Navegar rápido al webroot
alias www='cd /var/www/html'

# Ver qué está escuchando en qué puerto
alias ports='ss -tlnp'
```
