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
echo 'Dawn theme compiled: ' . strlen(\$result->getCss()) . \" bytes\\n\";
" 2>&1 || { log "FATAL: Dawn theme compilation failed."; exit 1; }
else
    log "Dawn theme CSS already present."
fi

# -- 1b. Compile Noon theme CSS (if missing) --
if [ ! -f "${THEME_DIR}/Noon/style.css" ]; then
    log "Noon theme CSS missing. Compiling via scssphp ..."
    set +e
    php -r "
require_once '${APP_DIR}/vendor/autoload.php';
\$compiler = new ScssPhp\ScssPhp\Compiler();
\$compiler->setImportPaths([
    '${APP_DIR}/public/legacy/themes/suite8/css/Noon',
    '${APP_DIR}/public/legacy/themes/suite8/css'
]);
\$result = \$compiler->compileString(file_get_contents('${APP_DIR}/public/legacy/themes/suite8/css/Noon/style.scss'));
file_put_contents('${APP_DIR}/public/legacy/themes/suite8/css/Noon/style.css', \$result->getCss());
echo 'Noon theme compiled: ' . strlen(\$result->getCss()) . \" bytes\\n\";
" 2>&1
    NOON_RC=$?
    set -e
    if [ "$NOON_RC" -ne 0 ]; then
        log "WARN: Noon theme compilation failed. Falling back to Dawn CSS ..."
        cp "${THEME_DIR}/Dawn/style.css" "${THEME_DIR}/Noon/style.css"
    fi
else
    log "Noon theme CSS already present."
fi

# -- 1c. Verify theme compilation succeeded --
if [ ! -f "${THEME_DIR}/Dawn/style.css" ] || [ ! -f "${THEME_DIR}/Noon/style.css" ]; then
    log "FATAL: Theme CSS compilation failed. Dawn or Noon style.css is missing."
    exit 1
fi

# -- 1d. Ensure angular.json exists (required for ng build) --
if [ ! -f "${APP_DIR}/angular.json" ]; then
    log "angular.json missing. Regenerating via merge-angular-json ..."
    cd "${APP_DIR}"
    if [ ! -d "node_modules" ]; then
        log "Installing JavaScript dependencies ..."
        yarn install --immutable 2>&1 || true
    fi
    yarn merge-angular-json 2>&1 || log "WARN: merge-angular-json returned non-zero."
    if [ ! -f "${APP_DIR}/angular.json" ]; then
        log "FATAL: angular.json could not be generated. Aborting."
        exit 1
    fi
    log "angular.json regenerated successfully."
else
    log "angular.json already present."
fi

# -- 2. Front-end build (run once) --
if [ ! -f "${DIST_DIR}/index.html" ]; then
    if [ -f "${APP_DIR}/package.json" ]; then
        log "Frontend dist/ missing or incomplete. Running Angular production build ..."
        cd "${APP_DIR}"
        if [ ! -d "node_modules" ]; then
            log "Installing JavaScript dependencies ..."
            yarn install --immutable 2>&1 || true
        fi
        # Fix common nested-binary permission issues in bind-mounted node_modules
        export NODE_OPTIONS="--max-old-space-size=4096"
    find node_modules -path.*esbuild.*-exec chmod +x {} \; 2>/dev/null || true
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

# -- 4. First-time SuiteCRM installation --
DB_USER="${DB_USER:-suitecrm}"
DB_PASS="${DB_PASSWORD:-SuiteCRM@2026!}"
DB_NAME="${DB_NAME:-suitecrm}"
DB_HOST="${DB_HOST:-mariadb}"
DB_PORT="${DB_PORT:-3306}"
SITE_ADMIN="${SITE_USERNAME:-admin}"
SITE_PASS="${SITE_PASSWORD:-Admin@123!}"
SITE_HOSTNAME="${SITE_URL:-https://crm.extendresourcing.com}"

NEEDS_INSTALL=0
if [ ! -f "${CONFIG_PHP}" ]; then
    log "SuiteCRM config.php not found -- installation required."
    NEEDS_INSTALL=1
else
    # config.php exists, but verify the database actually has tables
    if php -r "
        \$dsn = 'mysql:host=${DB_HOST};port=${DB_PORT};dbname=${DB_NAME}';
        try {
            \$pdo = new PDO(\$dsn, '${DB_USER}', '${DB_PASS}');
            \$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
            \$stmt = \$pdo->query(\"SELECT 1 FROM config LIMIT 1\");
            exit(0);
        } catch (Exception \$e) {
            exit(1);
        }
    " 2>/dev/null; then
        log "SuiteCRM config.php found and database is populated -- skipping installation."
    else
        log "WARN: config.php exists but database '${DB_NAME}' is empty or unreachable. Re-installing ..."
        # back up stale config files
        if [ -f "${CONFIG_PHP}" ]; then
            mv "${CONFIG_PHP}" "${CONFIG_PHP}.bak.$(date +%s)"
        fi
        if [ -f "${APP_DIR}/.env.local" ]; then
            mv "${APP_DIR}/.env.local" "${APP_DIR}/.env.local.bak.$(date +%s)"
        fi
        NEEDS_INSTALL=1
    fi
fi

if [ "${NEEDS_INSTALL}" -eq 1 ]; then
    log "Running SuiteCRM CLI installer ..."

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
        --no-debug 2>&1 || log "WARN: CLI installer returned non-zero."

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

# -- 5. Permissions (must run AFTER installer so www-data owns runtime dirs) --
log "Setting ownership and permissions ..."
find "${APP_DIR}" -type d -exec chmod 2755 {} \;
find "${APP_DIR}" -type f -exec chmod 0644 {} \;
chmod +x "${APP_DIR}/bin/console"

for d in cache logs var public/bundles public/extensions public/legacy/cache public/legacy/upload public/legacy/custom public/legacy/themes/suite8/css; do
    fullpath="${APP_DIR}/${d}"
    mkdir -p "${fullpath}"
    chown -R www-data:www-data "${fullpath}" || true
    chmod -R 775 "${fullpath}"
done

chmod 1733 /var/lib/php/sessions || true
chown -R www-data:www-data /var/lib/php/sessions || true

# -- 6. Assets & Cache --
log "Installing Symfony bundle assets ..."
cd "${APP_DIR}"
php "${CONSOLE}" assets:install public --no-interaction --no-debug 2>&1 || true

log "Clearing/warming Symfony cache ..."
php "${CONSOLE}" cache:clear --no-debug 2>&1 || true
php "${CONSOLE}" cache:warmup --no-debug 2>&1 || true

log "Fixing ownership for runtime directories ..."
for d in cache var logs public/bundles public/extensions public/legacy/cache public/legacy/upload public/legacy/custom public/legacy/themes/suite8/css; do
    chown -R www-data:www-data "${APP_DIR}/${d}" 2>/dev/null || true
    chmod -R 775 "${APP_DIR}/${d}" 2>/dev/null || true
done

log "Entrypoint complete. Handing over to Apache ..."

# -- Start Apache --
exec "$@"
