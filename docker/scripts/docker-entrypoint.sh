#!/bin/bash
set -eo pipefail

# =============================================
# SuiteCRM 8.9.3 -- Docker Entrypoint
# =============================================
APP_DIR="/var/www/html"
VENDOR_DIR="${APP_DIR}/vendor"
DIST_DIR="${APP_DIR}/public/dist"
LEGACY_HTACCESS="${APP_DIR}/public/legacy/.htaccess"
CONFIG_PHP="${APP_DIR}/public/legacy/config.php"
CONSOLE="${APP_DIR}/bin/console"

log() { echo "[SuiteCRM entrypoint] $*"; }

# -- 1. Composer dependencies --
THEME_DIR="${APP_DIR}/public/legacy/themes/suite8/css"

if [ ! -f "${VENDOR_DIR}/autoload.php" ]; then
    log "Vendor directory missing. Running composer install ..."
    cd "${APP_DIR}"
    composer install --no-interaction --optimize-autoloader --no-dev 2>&1
    log "Composer install finished."
else
    log "Vendor directory already present."
fi

# -- 1a. Compile Dawn theme CSS (if missing) --
if [ ! -f "${THEME_DIR}/Dawn/style.css" ]; then
    log "Dawn theme CSS missing. Compiling via scssphp ..."
    php -r "
require_once '${APP_DIR}/vendor/autoload.php';
\$compiler = new ScssPhp\ScssPhp\Compiler();
\$compiler->setImportPaths([
    '${APP_DIR}/public/legacy/themes/suite8/css/Dawn',
    '${APP_DIR}/public/legacy/themes/suite8/css'
]);
\$result = \$compiler->compileString(file_get_contents('${APP_DIR}/public/legacy/themes/suite8/css/Dawn/style.scss'));
file_put_contents('${APP_DIR}/public/legacy/themes/suite8/css/Dawn/style.css', \$result->getCss());
echo 'Dawn theme compiled: ' . strlen(\$result->getCss()) . \" bytes\n\";
" 2>&1 || log "WARN: Dawn theme compilation failed."
else
    log "Dawn theme CSS already present."
fi

# -- 1b. Compile Noon theme CSS (if missing) --
if [ ! -f "${THEME_DIR}/Noon/style.css" ]; then
    log "Noon theme CSS missing. Compiling via scssphp ..."
    php -r "
require_once '${APP_DIR}/vendor/autoload.php';
\$compiler = new ScssPhp\ScssPhp\Compiler();
\$compiler->setImportPaths([
    '${APP_DIR}/public/legacy/themes/suite8/css/Noon',
    '${APP_DIR}/public/legacy/themes/suite8/css'
]);
\$result = \$compiler->compileString(file_get_contents('${APP_DIR}/public/legacy/themes/suite8/css/Noon/style.scss'));
file_put_contents('${APP_DIR}/public/legacy/themes/suite8/css/Noon/style.css', \$result->getCss());
echo 'Noon theme compiled: ' . strlen(\$result->getCss()) . \" bytes\n\";
" 2>&1 || log "WARN: Noon theme compilation failed."
else
    log "Noon theme CSS already present."
fi

# -- 2. Front-end build (run once) --
if [ ! -d "${DIST_DIR}" ]; then
    if [ -f "${APP_DIR}/package.json" ]; then
        log "Frontend dist/ missing. Running Angular production build ..."
        cd "${APP_DIR}"
        if [ ! -d "node_modules" ]; then
            log "Installing JavaScript dependencies ..."
            yarn install --immutable 2>&1 || true
        fi
        yarn build 2>&1 || log "WARN: yarn build returned non-zero."
        log "Frontend build finished."
    else
        log "WARN: package.json not found -- skipping frontend build."
    fi
else
    log "Frontend dist/ already present."
fi

# -- 3. Fix legacy .htaccess RewriteBase --
if [ -f "${LEGACY_HTACCESS}" ]; then
    if grep -q 'RewriteBase localhost/public/legacy' "${LEGACY_HTACCESS}"; then
        log "Fixing legacy .htaccess RewriteBase ..."
        sed -i 's|RewriteBase localhost/public/legacy|RewriteBase /legacy|' "${LEGACY_HTACCESS}"
    fi
fi

# -- 4. Permissions --
log "Setting ownership and permissions ..."
find "${APP_DIR}" -type d -exec chmod 2755 {} \;
find "${APP_DIR}" -type f -exec chmod 0644 {} \;
chmod +x "${APP_DIR}/bin/console"

for d in cache logs var public/bundles public/legacy/cache; do
    fullpath="${APP_DIR}/${d}"
    if [ -d "${fullpath}" ]; then
        chmod -R 775 "${fullpath}"
    fi
done

chmod 1733 /var/lib/php/sessions || true
chown -R www-data:www-data /var/lib/php/sessions || true

# -- 5. First-time SuiteCRM installation --
if [ ! -f "${CONFIG_PHP}" ]; then
    log "SuiteCRM not installed yet. Running CLI installer ..."

    DB_USER="${DB_USER:-suitecrm}"
    DB_PASS="${DB_PASSWORD:-SuiteCRM@2026!}"
    DB_NAME="${DB_NAME:-suitecrm}"
    DB_HOST="${DB_HOST:-mariadb}"
    DB_PORT="${DB_PORT:-3306}"
    SITE_ADMIN="${SITE_USERNAME:-admin}"
    SITE_PASS="${SITE_PASSWORD:-Admin@123!}"
    SITE_HOSTNAME="${SITE_URL:-https://crm.extendresourcing.com}"

    php "${CONSOLE}" suitecrm:app:install \
        --db_username="${DB_USER}" \
        --db_password="${DB_PASS}" \
        --db_host="${DB_HOST}" \
        --db_port="${DB_PORT}" \
        --db_name="${DB_NAME}" \
        --site_username="${SITE_ADMIN}" \
        --site_password="${SITE_PASS}" \
        --site_host="${SITE_HOSTNAME}" \
        --no-interaction \
        -W 1 \
        --no-debug 2>&1 || log "WARN: CLI installer returned non-zero (may already be installed)."

    if [ ! -f "${APP_DIR}/.env.local" ]; then
        log "Creating .env.local ..."
        ESCAPED_DB_PASS=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${DB_PASS}', safe=''))" 2>/dev/null || echo "${DB_PASS}")
        cat > "${APP_DIR}/.env.local" <<EOF
DATABASE_URL="mysql://${DB_USER}:${ESCAPED_DB_PASS}@${DB_HOST}:${DB_PORT}/${DB_NAME}?serverVersion=10.11.2-MariaDB&charset=utf8mb4"
APP_SECRET=${APP_SECRET:-$(openssl rand -hex 16)}
APP_DEBUG=0
APP_ENV=prod
SITE_URL=${SITE_HOSTNAME}
SAML_SP_ENTITY_ID=${SITE_HOSTNAME}
EOF
    fi
else
    log "SuiteCRM config.php found -- skipping installation."
fi

# -- 6. Cache warmup --
log "Clearing/warming Symfony cache ..."
cd "${APP_DIR}"
php "${CONSOLE}" cache:clear --no-debug 2>&1 || true
php "${CONSOLE}" cache:warmup --no-debug 2>&1 || true

log "Entrypoint complete. Handing over to Apache ..."

# -- Start Apache --
exec "$@"
