-- SuiteCRM 8.9.3 — Database Bootstrap
-- This script runs once when the MariaDB container initialises.

CREATE DATABASE IF NOT EXISTS suitecrm
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS 'suitecrm'@'%'
    IDENTIFIED BY 'SuiteCRM@2026!';

GRANT ALL PRIVILEGES ON suitecrm.* TO 'suitecrm'@'%';
FLUSH PRIVILEGES;
