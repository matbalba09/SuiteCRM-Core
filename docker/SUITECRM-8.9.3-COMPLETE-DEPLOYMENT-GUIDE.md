# SuiteCRM 8.9.3 Complete Deployment Guide

**Document Version:** 1.0  
**Date Created:** April 29, 2026  
**Target Platform:** Ubuntu 24.04 LTS  
**SuiteCRM Version:** 8.9.3  
**Installation Type:** Production (Pre-built Package)  

---

## ⚠️ IMPORTANT: How to Use This Document

This document is designed to be read by **AgentSmith** (or similar AI agent) to replicate this exact SuiteCRM installation on a fresh server.

**To use:** Provide this entire file to AgentSmith with the prompt:
> "Please set up SuiteCRM 8.9.3 on this fresh server following the deployment guide in this document."

The agent should execute all steps in order.

---

## 📋 Table of Contents

1. [Environment Overview](#environment-overview)
2. [Prerequisites](#prerequisites)
3. [Phase 1: Install System Packages](#phase-1-install-system-packages)
4. [Phase 2: Install PHP Extensions](#phase-2-install-php-extensions)
5. [Phase 3: Configure Apache](#phase-3-configure-apache)
6. [Phase 4: Configure MariaDB](#phase-4-configure-mariadb)
7. [Phase 5: Download SuiteCRM](#phase-5-download-suitecrm)
8. [Phase 6: Set Permissions](#phase-6-set-permissions)
9. [Phase 7: Install Composer Dependencies](#phase-7-install-composer-dependencies)
10. [Phase 8: Run SuiteCRM Installer](#phase-8-run-suitecrm-installer)
11. [Phase 9: Configure Environment](#phase-9-configure-environment)
12. [Phase 10: Fix Known Issues](#phase-10-fix-known-issues)
13. [Phase 11: Final Configuration](#phase-11-final-configuration)
14. [Verification](#verification)
15. [Troubleshooting](#troubleshooting)
16. [Appendix: File Contents](#appendix-file-contents)

---

## Environment Overview

### Server Specifications
- **OS:** Ubuntu 24.04 LTS (Noble Numbat)
- **Web Server:** Apache 2.4.58
- **Database:** MariaDB 10.11.14
- **PHP:** 8.3.6
- **SuiteCRM:** 8.9.3

### Network Configuration
- **VM IP Address:** 192.168.254.108 (example - will vary per deployment)
- **Domain:** crm.extendresourcing.com (configurable)
- **Alternative Access:** suitecrm.local (via DNS rewrite)

### Directory Structure
```
/var/www/html/
├── SuiteCRM-Core/          # Original git repository (preserved)
└── suitecrm/               # Production installation
    ├── public/             # Web root (DocumentRoot)
    │   ├── index.php       # Main entry point
    │   ├── legacy/         # SuiteCRM 7.x legacy code
    │   └── .htaccess       # Apache rewrite rules
    ├── config/             # Symfony configuration
    ├── core/               # SuiteCRM 8.x core
    ├── var/                # Symfony cache/logs
    ├── logs/               # Application logs
    ├── cache/              # Application cache
    └── .env.local          # Environment configuration
```

---

## Prerequisites

### Required Credentials (Customize Before Deployment)

| Component | Username | Password | Notes |
|-----------|----------|----------|-------|
| **Database** | `suitecrm` | `SuiteCRM@2026!` | Change for production |
| **Database Name** | `suitecrm` | - | - |
| **SuiteCRM Admin** | `admin` | `Admin@123!` | **CHANGE IMMEDIATELY** |
| **Sudo Password** | - | `1221` | System-specific |

### DNS/Host Configuration

**Option A: AdGuard DNS Rewrite (Recommended)**
```
Domain: crm.extendresourcing.com
IP: <server-ip-address>
```

**Option B: Hosts File**
```
<server-ip-address>    crm.extendresourcing.com
<server-ip-address>    suitecrm.local
```

---

## Phase 1: Install System Packages

### 1.1 Update Package Lists
```bash
echo "1221" | sudo -S apt-get update
```

### 1.2 Install Core Packages
```bash
echo "1221" | sudo -S apt-get install -y apache2 mariadb-server mariadb-client php php-cli libapache2-mod-php unzip curl git pv socat ssl-cert
```

**Packages Installed:**
- `apache2` - Web server
- `mariadb-server` - Database server
- `mariadb-client` - Database client
- `php` - PHP interpreter (8.3)
- `php-cli` - PHP command-line interface
- `libapache2-mod-php` - Apache PHP module
- `unzip` - Archive extraction
- `curl` - HTTP client
- `git` - Version control (for future development)
- `pv` - Progress viewer
- `socat` - Socket utility (for MariaDB)
- `ssl-cert` - SSL certificates

### 1.3 Enable Apache Modules
```bash
echo "1221" | sudo -S a2enmod rewrite
```

### 1.4 Start Services
```bash
echo "1221" | sudo -S systemctl start apache2
echo "1221" | sudo -S systemctl start mariadb
echo "1221" | sudo -S systemctl enable apache2
echo "1221" | sudo -S systemctl enable mariadb
```

---

## Phase 2: Install PHP Extensions

### 2.1 Install Required Extensions
```bash
echo "1221" | sudo -S apt-get install -y php-mysql php-curl php-gd php-mbstring php-xml php-zip php-intl php-imagick php-bcmath php-json php-ldap
```

**Extensions Installed:**
- `php-mysql` - MySQL/MariaDB database connectivity
- `php-curl` - HTTP requests
- `php-gd` - Image processing
- `php-mbstring` - Multibyte string handling
- `php-xml` - XML parsing
- `php-zip` - ZIP archive handling
- `php-intl` - Internationalization
- `php-imagick` - ImageMagick image processing
- `php-bcmath` - Arbitrary precision mathematics
- `php-json` - JSON handling
- `php-ldap` - LDAP authentication (required for SAML)

### 2.2 Configure PHP Upload Limits
```bash
echo "1221" | sudo -S sed -i 's/upload_max_filesize = 2M/upload_max_filesize = 16M/' /etc/php/8.3/apache2/php.ini
echo "1221" | sudo -S sed -i 's/post_max_size = 8M/post_max_size = 20M/' /etc/php/8.3/apache2/php.ini
```

### 2.3 Enable PHP Error Logging (for debugging)
```bash
echo "1221" | sudo -S bash -c "cat >> /etc/php/8.3/apache2/php.ini << 'EOF'

; Error logging for debugging
error_log = /var/log/php_errors.log
log_errors = On
display_errors = On
display_startup_errors = On
error_reporting = E_ALL
EOF"
```

```bash
echo "1221" | sudo -S touch /var/log/php_errors.log
echo "1221" | sudo -S chmod 666 /var/log/php_errors.log
```

---

## Phase 3: Configure Apache

### 3.1 Create Virtual Host Configuration
```bash
echo "1221" | sudo -S bash -c "cat > /etc/apache2/sites-available/suitecrm.conf << 'EOF'
<VirtualHost *:80>
    ServerName crm.extendresourcing.com
    ServerAlias suitecrm.local localhost
    
    DocumentRoot /var/www/html/suitecrm/public
    
    <Directory /var/www/html/suitecrm/public>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
        DirectoryIndex index.php
    </Directory>
    
    ErrorLog \${APACHE_LOG_DIR}/suitecrm_error.log
    CustomLog \${APACHE_LOG_DIR}/suitecrm_access.log combined
</VirtualHost>
EOF"
```

### 3.2 Enable Site and Disable Default
```bash
echo "1221" | sudo -S a2ensite suitecrm.conf
echo "1221" | sudo -S a2dissite 000-default.conf
```

### 3.3 Restart Apache
```bash
echo "1221" | sudo -S systemctl restart apache2
```

---

## Phase 4: Configure MariaDB

### 4.1 Create Database
```bash
echo "1221" | sudo -S mysql -u root -e "CREATE DATABASE IF NOT EXISTS suitecrm CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
```

### 4.2 Create Database User
```bash
echo "1221" | sudo -S mysql -u root -e "CREATE USER IF NOT EXISTS 'suitecrm'@'localhost' IDENTIFIED BY 'SuiteCRM@2026!';"
```

### 4.3 Grant Privileges
```bash
echo "1221" | sudo -S mysql -u root -e "GRANT ALL PRIVILEGES ON suitecrm.* TO 'suitecrm'@'localhost'; FLUSH PRIVILEGES;"
```

### 4.4 Verify Database
```bash
echo "1221" | sudo -S mysql -u root -e "SHOW DATABASES LIKE 'suitecrm';"
```

---

## Phase 5: Download SuiteCRM

### 5.1 Create Installation Directory
```bash
echo "1221" | sudo -S mkdir -p /var/www/html/suitecrm
echo "1221" | sudo -S chown www-data:www-data /var/www/html/suitecrm
```

### 5.2 Download SuiteCRM 8.9.3
```bash
curl -L -o /tmp/suitecrm-8.9.3.zip "https://suitecrm.com/download/166/suite89/567686/suitecrm-8-9-3.zip"
```

### 5.3 Extract Package
```bash
echo "1221" | sudo -S unzip -q /tmp/suitecrm-8.9.3.zip -d /var/www/html/suitecrm
```

---

## Phase 6: Set Permissions

### 6.1 Set Ownership
```bash
echo "1221" | sudo -S chown -R www-data:www-data /var/www/html/suitecrm
```

### 6.2 Set Directory Permissions
```bash
echo "1221" | sudo -S find /var/www/html/suitecrm -type d -exec chmod 2755 {} \;
```

### 6.3 Set File Permissions
```bash
echo "1221" | sudo -S find /var/www/html/suitecrm -type f -exec chmod 0644 {} \;
```

### 6.4 Make Console Executable
```bash
echo "1221" | sudo -S chmod +x /var/www/html/suitecrm/bin/console
```

### 6.5 Fix Special Directory Permissions
```bash
echo "1221" | sudo -S find /var/www/html/suitecrm -type d \( -name "cache" -o -name "logs" -o -name "storage" -o -name "var" \) -exec chmod 775 {} \;
echo "1221" | sudo -S find /var/www/html/suitecrm -type d \( -name "cache" -o -name "logs" -o -name "storage" -o -name "var" \) -exec chown -R www-data:www-data {} \;
```

### 6.6 Create Var Directories
```bash
echo "1221" | sudo -S mkdir -p /var/www/html/suitecrm/var/cache/prod /var/www/html/suitecrm/var/log
echo "1221" | sudo -S chown -R www-data:www-data /var/www/html/suitecrm/var
echo "1221" | sudo -S chmod -R 775 /var/www/html/suitecrm/var
```

---

## Phase 7: Install Composer Dependencies

### 7.1 Install Composer
```bash
echo "1221" | sudo -S apt-get install -y composer
```

### 7.2 Install Dependencies
```bash
cd /var/www/html/suitecrm
echo "1221" | sudo -S -u www-data composer install --no-interaction
```

**Note:** This installs 94+ packages including:
- `doctrine/doctrine-fixtures-bundle` (critical - was missing)
- `api-platform/core`
- `symfony/*` components
- Testing frameworks (PHPUnit, Codeception)
- Development tools

---

## Phase 8: Run SuiteCRM Installer

### 8.1 Execute CLI Installer
```bash
cd /var/www/html/suitecrm
echo "1221" | sudo -S -u www-data php bin/console suitecrm:app:install \
    --db_username=suitecrm \
    --db_password='SuiteCRM@2026!' \
    --db_host=localhost \
    --db_port=3306 \
    --db_name=suitecrm \
    --site_username=admin \
    --site_password='Admin@123!' \
    --site_host=localhost \
    --demoData \
    --no-interaction \
    -W 1 \
    --no-debug
```

**Installer Parameters:**
- `--db_username` - Database username
- `--db_password` - Database password
- `--db_host` - Database host
- `--db_port` - Database port
- `--db_name` - Database name
- `--site_username` - Admin username
- `--site_password` - Admin password
- `--site_host` - Site hostname
- `--demoData` - Install demo data for testing
- `--no-interaction` - Non-interactive mode
- `-W 1` - Ignore system check warnings
- `--no-debug` - Production mode

---

## Phase 9: Configure Environment

### 9.1 Create .env.local File
```bash
echo "1221" | sudo -S bash -c "cat > /var/www/html/suitecrm/.env.local << 'EOF'
DATABASE_URL="mysql://suitecrm:SuiteCRM%402026%21@localhost:3306/suitecrm"
APP_SECRET=84e6ea0c2fc518726ef09daa4ce63ff6
APP_DEBUG=0
APP_ENV=prod
SITE_URL=http://localhost
SAML_SP_ENTITY_ID=http://localhost
EOF"
```

**Critical Settings:**
- `DATABASE_URL` - Database connection string (password URL-encoded)
- `APP_SECRET` - Symfony application secret (auto-generated during install)
- `APP_DEBUG=0` - Disable debug mode for production
- `APP_ENV=prod` - Production environment
- `SITE_URL` - Base URL for the application
- `SAML_SP_ENTITY_ID` - SAML Service Provider entity ID (prevents validation errors)

### 9.2 Clear Cache
```bash
cd /var/www/html/suitecrm
echo "1221" | sudo -S -u www-data php bin/console cache:clear
```

---

## Phase 10: Fix Known Issues

### ⚠️ ISSUE 1: Legacy .htaccess RewriteBase Error

**Problem:** After login, Apache returns 500 error with log message:
```
RewriteBase: argument is not a valid URL
```

**Root Cause:** The `public/legacy/.htaccess` file has `RewriteBase localhost/public/legacy` which is invalid syntax.

**Fix:**
```bash
echo "1221" | sudo -S sed -i 's|RewriteBase localhost/public/legacy|RewriteBase /legacy|' /var/www/html/suitecrm/public/legacy/.htaccess
```

**Verification:**
```bash
grep "RewriteBase" /var/www/html/suitecrm/public/legacy/.htaccess
# Should output: RewriteBase /legacy
```

### ⚠️ ISSUE 2: SAML Configuration Errors

**Problem:** 500 Internal Server Error with message:
```
Invalid array settings: sp_acs_url_invalid, sp_sls_url_invalid
```

**Root Cause:** SAML Service Provider entity ID is empty, causing URL validation to fail.

**Fix:** Set `SAML_SP_ENTITY_ID` in `.env.local` (done in Phase 9.1)

### ⚠️ ISSUE 3: Missing Composer Dependencies

**Problem:** Error during cache clear:
```
Class "Doctrine\Bundle\FixturesBundle\DoctrineFixturesBundle" not found
```

**Root Cause:** Composer dependencies not installed.

**Fix:** Run `composer install` (Phase 7.2)

### ⚠️ ISSUE 4: Missing PHP LDAP Extension

**Problem:** Composer fails with:
```
symfony/ldap requires ext-ldap *
```

**Root Cause:** PHP LDAP extension not installed.

**Fix:**
```bash
echo "1221" | sudo -S apt-get install -y php-ldap
```

### ⚠️ ISSUE 5: Wrong DocumentRoot

**Problem:** Apache shows directory listing instead of SuiteCRM.

**Root Cause:** SuiteCRM 8.x uses Symfony structure with `public/` as web root.

**Fix:** Set `DocumentRoot /var/www/html/suitecrm/public` in Apache config (Phase 3.1)

### ⚠️ ISSUE 6: Upload Size Limits

**Problem:** Installer fails system checks with:
```
Upload File Size | error | Your PHP configuration should be changed to allow files of at least 6MB
```

**Root Cause:** Default PHP upload limits too low.

**Fix:** Increase `upload_max_filesize` and `post_max_size` (Phase 2.2)

---

## Phase 11: Final Configuration

### 11.1 Restart Apache
```bash
echo "1221" | sudo -S systemctl restart apache2
```

### 11.2 Enable Services on Boot
```bash
echo "1221" | sudo -S systemctl enable apache2
echo "1221" | sudo -S systemctl enable mariadb
```

### 11.3 Create Public .htaccess (if missing)
```bash
echo "1221" | sudo -S bash -c "cat > /var/www/html/suitecrm/public/.htaccess << 'EOF'
RewriteEngine On
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule ^(.*)$ index.php [QSA,L]
EOF"
```

---

## Verification

### 12.1 Check Service Status
```bash
echo "1221" | sudo -S systemctl status apache2 --no-pager
echo "1221" | sudo -S systemctl status mariadb --no-pager
```

### 12.2 Verify PHP
```bash
php -v
# Should show: PHP 8.3.x
```

### 12.3 Verify Database
```bash
echo "1221" | sudo -S mysql -u root -e "SHOW DATABASES LIKE 'suitecrm';"
# Should output: suitecrm
```

### 12.4 Test HTTP Access
```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost/
# Should return: 200
```

### 12.5 Test Login
1. Open browser to `http://<server-ip>/` or `http://crm.extendresourcing.com/`
2. Login with:
   - **Username:** `admin`
   - **Password:** `Admin@123!`
3. Verify dashboard loads without errors

---

## Troubleshooting

### Common Issues and Solutions

#### 1. 500 Internal Server Error
**Check logs:**
```bash
echo "1221" | sudo -S tail -100 /var/log/apache2/suitecrm_error.log
echo "1221" | sudo -S tail -100 /var/log/php_errors.log
```

#### 2. Database Connection Error
**Verify credentials:**
```bash
echo "1221" | sudo -S mysql -u suitecrm -p'SuiteCRM@2026!' -e "USE suitecrm; SELECT 1;"
```

#### 3. Permission Denied Errors
**Fix ownership:**
```bash
echo "1221" | sudo -S chown -R www-data:www-data /var/www/html/suitecrm
```

**Fix permissions:**
```bash
echo "1221" | sudo -S find /var/www/html/suitecrm -type d -exec chmod 2755 {} \;
echo "1221" | sudo -S find /var/www/html/suitecrm -type f -exec chmod 0644 {} \;
```

#### 4. Cache Issues
**Clear cache:**
```bash
cd /var/www/html/suitecrm
echo "1221" | sudo -S -u www-data php bin/console cache:clear
```

#### 5. Session Errors
**Check session directory:**
```bash
echo "1221" | sudo -S ls -la /var/lib/php/sessions
echo "1221" | sudo -S chmod 1733 /var/lib/php/sessions
```

---

## Appendix: File Contents

### A.1 Apache Virtual Host (/etc/apache2/sites-available/suitecrm.conf)
```apache
<VirtualHost *:80>
    ServerName crm.extendresourcing.com
    ServerAlias suitecrm.local localhost
    
    DocumentRoot /var/www/html/suitecrm/public
    
    <Directory /var/www/html/suitecrm/public>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
        DirectoryIndex index.php
    </Directory>
    
    ErrorLog ${APACHE_LOG_DIR}/suitecrm_error.log
    CustomLog ${APACHE_LOG_DIR}/suitecrm_access.log combined
</VirtualHost>
```

### A.2 Environment File (/var/www/html/suitecrm/.env.local)
```env
DATABASE_URL="mysql://suitecrm:SuiteCRM%402026%21@localhost:3306/suitecrm"
APP_SECRET=84e6ea0c2fc518726ef09daa4ce63ff6
APP_DEBUG=0
APP_ENV=prod
SITE_URL=http://localhost
SAML_SP_ENTITY_ID=http://localhost
```

### A.3 Public .htaccess (/var/www/html/suitecrm/public/.htaccess)
```apache
RewriteEngine On
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule ^(.*)$ index.php [QSA,L]
```

### A.4 Legacy .htaccess Fix (/var/www/html/suitecrm/public/legacy/.htaccess)
**Line 22 should read:**
```apache
RewriteBase /legacy
```

---

## Security Notes

### Immediate Actions After Installation

1. **Change Admin Password**
   - Login as admin
   - Navigate to User Profile
   - Change default password `Admin@123!`

2. **Secure Database Credentials**
   - Change `SuiteCRM@2026!` to a strong unique password
   - Update `.env.local` with new credentials

3. **Disable Debug Mode**
   - Ensure `APP_DEBUG=0` in `.env.local`
   - Ensure `APP_ENV=prod` in `.env.local`

4. **Enable HTTPS (Recommended)**
   ```bash
   echo "1221" | sudo -S apt-get install -y certbot python3-certbot-apache
   echo "1221" | sudo -S certbot --apache -d crm.extendresourcing.com
   ```

5. **Configure Firewall**
   ```bash
   echo "1221" | sudo -S ufw allow 'Apache Full'
   echo "1221" | sudo -S ufw allow 'OpenSSH'
   echo "1221" | sudo -S ufw enable
   ```

6. **Set Up Cron Jobs**
   ```bash
   crontab -e -u www-data
   # Add:
   * * * * * cd /var/www/html/suitecrm && php bin/console suitecrm:scheduler run >> /var/log/suitecrm_cron.log 2>&1
   ```

---

## Performance Tuning (Optional)

### PHP OPcache Configuration
```bash
echo "1221" | sudo -S bash -c "cat >> /etc/php/8.3/apache2/php.ini << 'EOF'

; OPcache Configuration
opcache.enable=1
opcache.memory_consumption=256
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=10000
opcache.revalidate_freq=60
opcache.fast_shutdown=1
EOF"
```

### MariaDB Configuration
```bash
echo "1221" | sudo -S bash -c "cat >> /etc/mysql/mariadb.conf.d/99-suitecrm.cnf << 'EOF'
[mysqld]
innodb_buffer_pool_size = 512M
innodb_log_file_size = 128M
innodb_flush_log_at_trx_commit = 2
query_cache_size = 64M
query_cache_type = 1
max_connections = 200
EOF"
```

Then restart services:
```bash
echo "1221" | sudo -S systemctl restart mariadb
echo "1221" | sudo -S systemctl restart apache2
```

---

## Backup Strategy

### Database Backup
```bash
echo "1221" | sudo -S mysqldump -u root suitecrm > /backup/suitecrm_$(date +%Y%m%d_%H%M%S).sql
```

### File Backup
```bash
echo "1221" | sudo -S tar -czf /backup/suitecrm_files_$(date +%Y%m%d_%H%M%S).tar.gz /var/www/html/suitecrm
```

### Automated Backup Script
Create `/usr/local/bin/suitecrm-backup.sh`:
```bash
#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
mysqldump -u root suitecrm > /backup/suitecrm_db_${DATE}.sql
tar -czf /backup/suitecrm_files_${DATE}.tar.gz /var/www/html/suitecrm
find /backup -name "suitecrm_*" -mtime +30 -delete
```

Make executable:
```bash
echo "1221" | sudo -S chmod +x /usr/local/bin/suitecrm-backup.sh
```

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-04-29 | AgentSmith | Initial comprehensive documentation |

---

## Contact & Support

- **SuiteCRM Documentation:** https://docs.suitecrm.com/
- **SuiteCRM Community:** https://community.suitecrm.com/
- **SuiteCRM GitHub:** https://github.com/SuiteCRM/SuiteCRM

---

**END OF DEPLOYMENT GUIDE**
