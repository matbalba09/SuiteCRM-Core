#!/usr/bin/env bash
# =============================================
# suitecrm-docker.sh  —  Convenience wrapper
# =============================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

CMD="${1:-help}"
shift || true

case "${CMD}" in
    up)
        echo "==> Starting SuiteCRM stack ..."
        docker compose up -d --build "$@"
        ;;
    down)
        echo "==> Stopping SuiteCRM stack ..."
        docker compose down "$@"
        ;;
    stop)
        docker compose stop "$@"
        ;;
    restart)
        docker compose restart "$@"
        ;;
    logs)
        docker compose logs -f "$@"
        ;;
    shell)
        echo "==> Opening shell in suitecrm-app ..."
        docker compose exec suitecrm bash
        ;;
    db)
        echo "==> Opening MariaDB shell ..."
        docker compose exec mariadb mariadb -u root -p"${DB_ROOT_PASSWORD:-SuiteRoot2026!}" suitecrm
        ;;
    install)
        echo "==> Running SuiteCRM CLI installer ..."
        docker compose exec suitecrm php bin/console suitecrm:app:install \
            --db_username="${DB_USER:-suitecrm}" \
            --db_password="${DB_PASSWORD:-SuiteCRM@2026!}" \
            --db_host=mariadb \
            --db_port=3306 \
            --db_name="${DB_NAME:-suitecrm}" \
            --site_username="${SITE_USERNAME:-admin}" \
            --site_password="${SITE_PASSWORD:-Admin@123!}" \
            --site_host="${SITE_URL:-https://crm.extendresourcing.com}" \
            --no-interaction -W 1 --no-debug
        ;;
    cache-clear)
        docker compose exec suitecrm php bin/console cache:clear --no-debug
        docker compose exec suitecrm php bin/console cache:warmup --no-debug
        ;;
    permissions)
        docker compose exec suitecrm bash -c '
            find /var/www/html -type d -exec chmod 2755 {} \;
            find /var/www/html -type f -exec chmod 0644 {} \;
            chmod +x /var/www/html/bin/console
            for d in cache logs var public/bundles public/legacy/cache; do
                [ -d "/var/www/html/$d" ] && chmod -R 775 "/var/www/html/$d"
            done
        '
        ;;
    backup)
        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        echo "==> Backing up database ..."
        docker compose exec mariadb mysqldump -u root -p"${DB_ROOT_PASSWORD:-SuiteRoot2026!}" suitecrm > "./data/mariadb-backups/suitecrm_db_${TIMESTAMP}.sql"
        echo "==> Backup saved to ./data/mariadb-backups/suitecrm_db_${TIMESTAMP}.sql"
        ;;
    status)
        docker compose ps
        ;;
    update)
        echo "==> Pulling newest images & rebuilding ..."
        docker compose pull
        docker compose up -d --build
        ;;
    destroy)
        read -r -p "⚠️  This will DELETE all volumes and data. Continue? [y/N] " CONFIRM
        if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
            docker compose down -v
            echo " destroyed. Run './suitecrm-docker.sh up' to start fresh."
        else
            echo "Aborted."
        fi
        ;;
    *)
        cat <<EOF
Usage: ./suitecrm-docker.sh <command>

Commands:
  up            Build (if needed) and start containers
  down          Stop and remove containers
  stop          Stop containers (keep them)
  restart       Restart containers
  logs          Follow container logs
  shell         Open bash in the suitecrm-app container
  db            Open MariaDB REPL as root
  install       Re-run the CLI installer manually
  cache-clear   Clear + warm Symfony cache
  permissions   Fix file/directory permissions
  backup        Dump database to ./data/mariadb-backups/
  status        Show running containers
  update        Pull new base images and rebuild
  destroy       ⚠️  Remove containers AND volumes (data loss!)
EOF
        ;;
esac
