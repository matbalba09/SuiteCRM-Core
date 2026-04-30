# SuiteCRM Docker Deployment — Required Fixes

> **Context:** After `docker system prune -a --volumes -f`, a fresh `docker compose up -d` in the `docker/` directory results in the `suitecrm-app` container being marked **unhealthy** and the site returning **502 Bad Gateway**.

---

## Root Causes

1. **Healthcheck timeout is too short.** On a cold start the entrypoint runs `composer install`, `yarn install`, `yarn build`, SCSS compilation, and the SuiteCRM CLI installer. This takes **10–15 minutes**, but Docker only gives it a `start_period` of **60 seconds** before marking it unhealthy.
2. **Runtime directories lack correct ownership.** Named volumes (`suitecrm_var`, `suitecrm_cache`, `suitecrm_logs`, `suitecrm_public_bundles`) are created empty and owned by `root`. Apache runs as `www-data`, so Symfony cache clear, log writes, and asset generation fail silently.
3. **Missing `assets:install`.** Symfony bundle assets in `public/bundles/` are never populated, causing 404s for bundle CSS/JS once the container finally starts.

---

## Files to Modify

### 1. `docker/docker-compose.yml`

**What to change:** Increase `start_period` under the `suitecrm` service healthcheck.

**Current (lines 96–101):**
```yaml
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost/"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 60s
```

**Replace with:**
```yaml
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost/"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 900s
```

**Rationale:** `start_period: 900s` gives the container a 15-minute grace period before Docker considers the healthcheck failures fatal. `timeout` and `retries` are also bumped to be less aggressive.

---

### 2. `docker/scripts/docker-entrypoint.sh`

**What to change:** Fix the permissions section and add `assets:install` plus `cache:clear` ownership fix.

**Current permissions block (lines 90–104):**
```bash
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
```

**Replace with:**
```bash
# -- 4. Permissions --
log "Setting ownership and permissions ..."
find "${APP_DIR}" -type d -exec chmod 2755 {} \;
find "${APP_DIR}" -type f -exec chmod 0644 {} \;
chmod +x "${APP_DIR}/bin/console"

for d in cache logs var public/bundles public/legacy/cache; do
    fullpath="${APP_DIR}/${d}"
    if [ -d "${fullpath}" ]; then
        chown -R www-data:www-data "${fullpath}" || true
        chmod -R 775 "${fullpath}"
    fi
done

chmod 1733 /var/lib/php/sessions || true
chown -R www-data:www-data /var/lib/php/sessions || true
```

**Rationale:** `chown -R www-data:www-data` ensures Apache (running as `www-data`) can actually write to `var/`, `cache/`, `logs/`, and `public/bundles/`.

---

**Current cache warmup block (lines 148–152):**
```bash
# -- 6. Cache warmup --
log "Clearing/warming Symfony cache ..."
cd "${APP_DIR}"
php "${CONSOLE}" cache:clear --no-debug 2>&1 || true
php "${CONSOLE}" cache:warmup --no-debug 2>&1 || true
```

**Replace with:**
```bash
# -- 6. Assets & Cache --
log "Installing Symfony bundle assets ..."
cd "${APP_DIR}"
php "${CONSOLE}" assets:install public --no-interaction --no-debug 2>&1 || true

log "Clearing/warming Symfony cache ..."
su -s /bin/bash www-data -c "php ${CONSOLE} cache:clear --no-debug" 2>&1 || true
su -s /bin/bash www-data -c "php ${CONSOLE} cache:warmup --no-debug" 2>&1 || true
```

**Rationale:**
- `assets:install` populates `public/bundles/` with CSS/JS from installed Symfony bundles. Without this the UI will have 404s for bundle assets.
- Running `cache:clear` and `cache:warmup` **as `www-data`** prevents permission mismatches where the cache is created as `root` and then Apache cannot read or write it.

---

## Full Corrected `docker-entrypoint.sh` (for reference)

If preferred, replace the entire file with the following content:

```bash
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
echo 'Noon theme compiled: ' . strlen(\$result->getCss()) . \" bytes\\n\";
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
        chown -R www-data:www-data "${fullpath}" || true
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

# -- 6. Assets & Cache --
log "Installing Symfony bundle assets ..."
cd "${APP_DIR}"
php "${CONSOLE}" assets:install public --no-interaction --no-debug 2>&1 || true

log "Clearing/warming Symfony cache ..."
su -s /bin/bash www-data -c "php ${CONSOLE} cache:clear --no-debug" 2>&1 || true
su -s /bin/bash www-data -c "php ${CONSOLE} cache:warmup --no-debug" 2>&1 || true

log "Entrypoint complete. Handing over to Apache ..."

# -- Start Apache --
exec "$@"
```

---

## Pre-Flight Check: `proxy-tier` Network

Before running `docker compose up`, ensure the external `proxy-tier` network exists. It is created by Nginx Proxy Manager. If it does not exist, the stack will fail immediately with a network-not-found error.

```bash
sudo docker network ls | grep proxy-tier
```

If nothing appears, create it:
```bash
sudo docker network create proxy-tier
```

---

## Verification Steps After Applying Fixes

1. Ensure you are on the `reiyb-feature/docker-setup` branch.
2. Make the changes above.
3. On the server, in `/opt/docker/SuiteCRM-Core/docker`:
   ```bash
   sudo docker compose down
   sudo docker compose up -d --build
   sudo docker logs suitecrm-app -f
   ```
4. **Wait.** First boot takes 10–15 minutes. Watch logs for:
   - `Composer install finished.`
   - `Frontend build finished.`
   - `SuiteCRM not installed yet. Running CLI installer ...`
   - `Installing Symfony bundle assets ...`
   - `Entrypoint complete. Handing over to Apache ...`
5. Once `Entrypoint complete` appears, check health:
   ```bash
   sudo docker ps
   ```
   `suitecrm-app` should show `(healthy)`.
6. Visit `https://crm.extendresourcing.com/`.

---

### 3. `public/legacy/themes/suite8/css/Dawn/style.scss`

**What to change:** Fix an SCSS `@import` typo that causes the Dawn theme to fail compilation on a fresh container.

**Current (line 111):**
```scss
@import '../suitep-base/tinemce.scss';   // TYPO
```

**Replace with:**
```scss
@import '../suitep-base/tinymce.scss';   // CORRECT
```

**Rationale:** The file `suitep-base/tinemce.scss` does not exist — it is named `tinymce.scss`. On a fresh clone where `style.css` is missing, `scssphp` compilation of the Dawn theme silently fails with a "file not found" error. This leaves Dawn without its `style.css`, and the entrypoint only logs `WARN: Dawn theme compilation failed.` instead of surfacing the real error.

> **Note:** The `.css` files for both Dawn and Noon are `.gitignore`'d, so they are not in the repo. The entrypoint is supposed to compile them on first boot. This typo breaks that automation for Dawn.

---

### 4. Strengthen SCSS Compilation in `docker-entrypoint.sh`

The entrypoint currently swallows SCSS compilation failures with `|| log "WARN: ..."`. On a fresh install, if both Dawn and Noon fail, the UI will have no theme CSS and you get a broken-looking CRM with 404s for theme files.

While `|| true` is fine for non-fatal steps, the entrypoint should **exit with an error** if critical assets cannot be built. Without Dawn CSS, the CRM login page and backend are unusable.

**Recommended enhancement** (insert after the existing Dawn/Noon blocks, around line 185):

```bash
# -- 1c. Verify theme compilation succeeded --
if [ ! -f "${THEME_DIR}/Dawn/style.css" ] || [ ! -f "${THEME_DIR}/Noon/style.css" ]; then
    log "FATAL: Theme CSS compilation failed. Dawn or Noon style.css is missing."
    exit 1
fi
```

And optionally, in the existing blocks, **remove the silent fallback** for Dawn and Noon so you see the actual `scssphp` stack trace in logs:

```bash
# Before:
" 2>&1 || log "WARN: Dawn theme compilation failed."

# After:
" 2>&1 || { log "FATAL: Dawn theme compilation failed."; exit 1; }
```

Same for Noon.

---

## Bonus Recommendation: `.dockerignore`

Ensure `docker/.dockerignore` exists and excludes:
```
vendor/
node_modules/
cache/
var/
logs/
public/dist/
public/bundles/
```
This prevents the Docker build context from being bloated. The current `.dockerignore` appears to be in place already, but verify it covers these directories.