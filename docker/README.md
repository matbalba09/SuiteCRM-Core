# SuiteCRM 8.9.3 — Docker Compose Deployment

> Quick-setup Docker stack for a **fresh git clone** of SuiteCRM-Core.
> Proxied through existing **nginx-proxy-manager** on the external `proxy-tier` network.

---

## Architecture

| Service | Image | Role |
|---------|-------|------|
| **suitecrm** | Custom `php:8.3-apache-bookworm` | Apache + PHP 8.3 + all required extensions |
| **mariadb** | `mariadb:10.11` | Database server |

**Networks**
- `suitecrm-internal` — private bridge between app & DB
- `proxy-tier` — **external** bridge managed by nginx-proxy-manager

---

## Quick Start

### 1. Copy environment file

```bash
cd docker
cp .env.example .env
# Edit .env with your real secrets
cd ..
```

### 2. Start the stack

```bash
# From repo root
cd docker
./suitecrm-docker.sh up

# OR manually (if wrapper is not executable yet)
chmod +x suitecrm-docker.sh
docker compose up -d --build
```

**First boot** behaviour (happens automatically in the `suitecrm` container):
1. Installs Composer dependencies (`vendor/`)
2. Builds Angular front-end (`public/dist/`)
3. Fixes legacy `.htaccess` RewriteBase issue
4. Sets correct file/directory permissions
5. Runs the SuiteCRM CLI installer if `public/legacy/config.php` is absent
6. Clears & warms Symfony cache

### 3. Reverse-proxy configuration (Nginx Proxy Manager)

| Setting | Value |
|---------|-------|
| Domain Names | `crm.extendresourcing.com` |
| Scheme | `http` |
| Forward Hostname/IP | `suitecrm-app` *(or the Docker host IP)* |
| Forward Port | `8080` *(or whatever `SUITECRM_HOST_PORT` is set to)* |
| Block Common Exploits | ✔ |

> **Note:** If NPM is running in a container on the same `proxy-tier` network, you can forward directly to the service name `suitecrm-app` on port `80` (the container’s port). If NPM is on the Docker host, forward to the host IP + `SUITECRM_HOST_PORT`.

### 4. DNS (AdGuard)

Add a **DNS rewrite** in AdGuard:
```
crm.extendresourcing.com → <Docker-Host-IP>
```

---

## File Layout

```
docker/
├── docker-compose.yml           # Main orchestration
├── Dockerfile                   # PHP 8.3 + Apache image
├── .env.example                 # Template for secrets
├── .dockerignore                # Slim build context
├── suitecrm-docker.sh           # Convenience wrapper
├── apache/
│   └── suitecrm.conf            # VirtualHost (DocumentRoot = public/)
├── mariadb/
│   └── init.sql                 # Bootstrap DB + user
├── scripts/
│   └── docker-entrypoint.sh     # First-run setup + installer
├── logs/                        # Persisted Apache / app logs
└── data/
    └── mariadb-backups/         # Dump directory for backups
```

---

## Useful Commands

| Command | Description |
|---------|-------------|
| `./suitecrm-docker.sh up` | Build & start containers |
| `./suitecrm-docker.sh down` | Stop and remove containers |
| `./suitecrm-docker.sh logs` | Tail logs |
| `./suitecrm-docker.sh shell` | Bash into the app container |
| `./suitecrm-docker.sh db` | MariaDB REPL as root |
| `./suitecrm-docker.sh install` | Re-run CLI installer manually |
| `./suitecrm-docker.sh cache-clear` | Clear & warm cache |
| `./suitecrm-docker.sh permissions` | Fix ownership/permissions |
| `./suitecrm-docker.sh backup` | Dump DB to `./data/mariadb-backups/` |
| `./suitecrm-docker.sh destroy` | **Delete all data** (volumes + DB) |

---

## Environment Variables (`.env`)

| Variable | Default | Purpose |
|----------|---------|---------|
| `APP_ENV` | `prod` | Symfony environment |
| `APP_SECRET` | *(generate a new one)* | Symfony secret |
| `DB_ROOT_PASSWORD` | `SuiteRoot2026!` | MariaDB root password |
| `DB_NAME` / `DB_USER` / `DB_PASSWORD` | `suitecrm` … | Application DB credentials |
| `SITE_URL` | `https://crm.extendresourcing.com` | Public URL |
| `SAML_SP_ENTITY_ID` | `https://crm.extendresourcing.com` | SAML entity ID |
| `VIRTUAL_HOST` | `crm.extendresourcing.com` | Host label for reverse proxy |
| `SUITECRM_HOST_PORT` | `8080` | Host port mapped to container port 80 |
| `SITE_USERNAME` | `admin` | Initial admin username |
| `SITE_PASSWORD` | `Admin@123!` | Initial admin password |

---

## Post-Install Checklist

1. **Change admin password** immediately after first login.
2. **Generate a strong `APP_SECRET`** in `.env` and rebuild.
3. **Enable HTTPS** in Nginx Proxy Manager (SSL certificate).
4. **Secure the DB** — change default DB passwords.
5. **Configure cron** for SuiteCRM schedulers (see below).

### Optional: Cron Schedulers

Add a cron job **on the Docker host** (or a cron sidecar container):

```bash
# Every minute
* * * * * docker exec suitecrm-app php /var/www/html/bin/console suitecrm:scheduler run >> /var/log/suitecrm_cron.log 2>&1
```

Or uncomment the cron service in a `docker-compose.override.yml`.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| **502 Bad Gateway** from NPM | Make sure `suitecrm-app` container is healthy: `./suitecrm-docker.sh logs` |
| **500 error after login** | Check legacy `.htaccess` — `./suitecrm-docker.sh shell` then `grep RewriteBase public/legacy/.htaccess` |
| **Permission denied** | Run `./suitecrm-docker.sh permissions` |
| **Missing `vendor/`** | Container auto-runs `composer install` on first boot |
| **Missing `public/dist/`** | Container auto-runs `yarn build` on first boot |
| **Database connection failed** | Verify `DATABASE_URL` matches `.env` values; check `./suitecrm-docker.sh logs` |
| **Cache issues** | `./suitecrm-docker.sh cache-clear` |

---

## Credits

Derived from the [SuiteCRM 8.9.3 Complete Deployment Guide](./SUITECRM-8.9.3-COMPLETE-DEPLOYMENT-GUIDE.md).
