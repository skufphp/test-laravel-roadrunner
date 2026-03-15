# ==============================================================================
# Многоэтапный образ PHP + RoadRunner — PHP 8.5 Alpine (Laravel Octane)
# ==============================================================================
# Назначение:
# - Сборка фронтенда (Node.js)
# - Базовая среда PHP с RoadRunner
# - Поддержка Xdebug для разработки
# - Оптимизированный Production образ
#
# Context: корень проекта (.)
# Stages:
#   frontend-build — сборка фронтенд-ассетов
#   php-base       — общая база: PHP, ext, RR, composer (без php.ini, USER, CMD)
#   development    — dev-среда: php.ini, USER, CMD
#   production     — prod-образ: php.prod.ini, код, vendor, USER, CMD
# ==============================================================================

FROM node:24-alpine AS frontend-build

WORKDIR /app

# Ставим зависимости фронта отдельно для лучшего кеширования
COPY package*.json ./
RUN if [ -f package-lock.json ]; then npm ci; else npm install; fi

# Копируем проект и собираем ассеты
COPY . ./
RUN npm run build

# ==============================================================================
# Базовая среда PHP с RoadRunner — только общая база для всех окружений
# ==============================================================================
FROM php:8.5-cli-alpine AS php-base

# PIE (PHP Installer for Extensions)
COPY --from=ghcr.io/php/pie:bin /pie /usr/bin/pie

# Зависимости времени выполнения (Runtime) + Зависимости для сборки (build dependencies) (удалим после компиляции)
RUN set -eux; \
    apk add --no-cache \
      curl git zip unzip \
      icu-libs libzip libpng libjpeg-turbo freetype postgresql-libs libxml2 oniguruma \
    && apk add --no-cache --virtual .build-deps \
      $PHPIZE_DEPS linux-headers \
      icu-dev libzip-dev libpng-dev libjpeg-turbo-dev freetype-dev \
      postgresql-dev libxml2-dev oniguruma-dev

# PHP расширения + phpredis
RUN set -eux; \
    docker-php-ext-configure gd --with-freetype --with-jpeg; \
    docker-php-ext-install -j"$(nproc)" \
      pdo \
      pdo_pgsql \
      pgsql \
      mbstring \
      xml \
      gd \
      bcmath \
      zip \
      intl \
      sockets \
      pcntl; \
    pie install phpredis/phpredis; \
    docker-php-ext-enable redis

# Xdebug (только для разработки)
ARG INSTALL_XDEBUG=false
RUN set -eux; \
    if [ "${INSTALL_XDEBUG}" = "true" ]; then \
      pie install xdebug/xdebug; \
      docker-php-ext-enable xdebug; \
    fi

# Очистка временных файлов
RUN set -eux; \
    apk del .build-deps; \
    rm -rf /tmp/pear ~/.pearrc /var/cache/apk/*

# Установка Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Установка RoadRunner
COPY --from=ghcr.io/roadrunner-server/roadrunner:2024 /usr/bin/rr /usr/bin/rr

WORKDIR /var/www/laravel

# Создаём пользователя www-data (если не существует) и назначаем права
RUN addgroup -g 82 -S www-data 2>/dev/null || true; \
    adduser -u 82 -D -S -G www-data www-data 2>/dev/null || true; \
    chown -R www-data:www-data /var/www/laravel

# Graceful shutdown: RoadRunner корректно завершает воркеры по SIGTERM
STOPSIGNAL SIGTERM

EXPOSE 8000

# ==============================================================================
# Development образ: dev php.ini, монтируется volume с кодом хоста
# ==============================================================================
FROM php-base AS development

# Конфигурация php.ini для разработки
COPY docker/php/php.ini /usr/local/etc/php/conf.d/local.ini

USER www-data

CMD ["rr", "serve", "-c", "/var/www/laravel/.rr.yaml"]

# ==============================================================================
# Production образ: код + vendor + собранные ассеты (идеально для деплоя)
# ==============================================================================
FROM php-base AS production

# Переключаемся на root для установки зависимостей
USER root

WORKDIR /var/www/laravel

# Копируем php.ini для продакшена
COPY docker/php/php.prod.ini /usr/local/etc/php/conf.d/local.ini

# Явно копируем конфиг RoadRunner: если файла нет в git-контексте, build должен упасть сразу
COPY .rr.yaml /var/www/laravel/.rr.yaml

# Копируем composer-файлы отдельно для кеширования слоя vendor
COPY composer.json composer.lock ./
RUN composer install --no-dev --optimize-autoloader --no-interaction --no-scripts --no-progress

# Копируем весь проект
COPY . ./

# Удаляем public/hot, чтобы отключить Vite dev-server режим в production
RUN rm -f public/hot

# Копируем собранные ассеты из frontend-build
COPY --from=frontend-build /app/public/build /var/www/laravel/public/build

# Удаляем dev-кеши, скопированные с хоста
# Перегенерируем autoload и запускаем package:discover без второго полного composer install
RUN rm -rf bootstrap/cache/*.php \
    && composer dump-autoload --optimize --no-dev --classmap-authoritative \
    && php artisan package:discover --ansi

# Назначаем права и переключаемся на www-data
RUN chown -R www-data:www-data /var/www/laravel
USER www-data

CMD ["rr", "serve", "-c", "/var/www/laravel/.rr.yaml"]
