#!/bin/bash
# Выпуск новой версии TimeCapsule.
set -euo pipefail

cd /var/www/timecapsule

echo "==> Забираем новый код из GitHub"
git pull --ff-only

echo "==> Устанавливаем библиотеки"
composer install --no-dev --optimize-autoloader --no-interaction

echo "==> Создаём недостающие таблицы"
php bin/init-db.php

echo "==> Перезапускаем PHP-FPM"
sudo systemctl reload php-fpm

echo "Готово. На сервере коммит: $(git log -1 --oneline)"
