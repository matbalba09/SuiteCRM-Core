# =============================================
# SuiteCRM 8.9.3 — Docker Image for Production
# =============================================
FROM php:8.3-apache-bookworm

LABEL maintainer="crm.extendresourcing.com"
LABEL app="SuiteCRM"
LABEL version="8.9.3"

# --- 1. System dependencies ---
RUN apt-get update && apt-get install -y --no-install-recommends \
    git unzip curl ca-certificates libzip4 \
    libpng16-16 libjpeg62-turbo libfreetype6 \
    libonig5 libxml2 libxslt1.1 libicu72 \
    libmagickwand-6.q16-6 libldap-2.5-0 \
    libpq5 libavif15 libwebp7 libxpm4 \
    default-mysql-client socat pv \
    libpng-dev libjpeg-dev libfreetype6-dev \
    libzip-dev libonig-dev libxml2-dev libxslt1-dev \
    libicu-dev libmagickwand-dev libldap2-dev \
    libpq-dev libavif-dev libwebp-dev libxpm-dev \
    libssl-dev pkg-config \
    gnupg2 \
    && rm -rf /var/lib/apt/lists/*

# --- 2. Node.js 20.x + Yarn 4 ---
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && corepack enable \
    && corepack prepare yarn@stable --activate \
    && rm -rf /var/lib/apt/lists/*

# --- 3. PHP extensions ---
RUN docker-php-ext-configure gd \
    --with-freetype --with-jpeg --with-webp --with-xpm --with-avif \
    && docker-php-ext-install -j$(nproc) \
    gd mysqli pdo pdo_mysql opcache zip mbstring xml intl bcmath soap xsl ldap

# --- 4. Imagick ---
RUN pecl install imagick && docker-php-ext-enable imagick

# --- 5. Composer ---
COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer

# --- 6. Apache ---
RUN a2enmod rewrite ssl headers env status proxy proxy_http \
    && a2dissite 000-default
COPY apache/suitecrm.conf /etc/apache2/sites-available/suitecrm.conf
RUN a2ensite suitecrm

# --- 7. PHP tuning ---
RUN { \
    echo "upload_max_filesize = 16M"; \
    echo "post_max_size = 20M"; \
    echo "memory_limit = 512M"; \
    echo "max_execution_time = 300"; \
    echo "max_input_time = 300"; \
    echo "max_input_vars = 20000"; \
    echo "date.timezone = UTC"; \
    echo "error_log = /var/log/php_errors.log"; \
    echo "log_errors = On"; \
    echo "display_errors = Off"; \
    echo "error_reporting = E_ALL \& ~E_DEPRECATED \& ~E_STRICT"; \
    echo "session.gc_maxlifetime = 1440"; \
    echo "session.cookie_httponly = On"; \
    echo "expose_php = Off"; \
} > /usr/local/etc/php/conf.d/suitecrm.ini

# --- 8. OPcache ---
RUN { \
    echo "opcache.enable=1"; \
    echo "opcache.memory_consumption=256"; \
    echo "opcache.interned_strings_buffer=16"; \
    echo "opcache.max_accelerated_files=10000"; \
    echo "opcache.revalidate_freq=60"; \
    echo "opcache.fast_shutdown=1"; \
    echo "opcache.save_comments=1"; \
} > /usr/local/etc/php/conf.d/opcache.ini

# --- 9. Working dir ---
WORKDIR /var/www/html
EXPOSE 80

# --- 10. Entrypoint ---
COPY scripts/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["apache2-foreground"]
