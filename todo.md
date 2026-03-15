Да, я это вижу: у тебя `php-base` сейчас выполняет **две роли сразу**:

* база для production
* runnable image для local development

И именно поэтому перенос `USER/CMD` только в `production` без изменений действительно сломает dev-сценарий.

## Что лучше сделать

Самый чистый вариант — **сделать отдельный stage для development**.

То есть структура такая:

* `php-base` — только общая база: PHP, ext, composer, rr, рабочая директория, пользователь
* `development` — dev php.ini, `USER www-data`, `CMD rr serve`
* `production` — prod php.ini, copy app, composer install, `USER www-data`, `CMD rr serve`

Так ты не смешиваешь:

* runtime-базу
* dev-runner
* production image

Это заметно проще поддерживать.

---

## Почему это лучше, чем оставлять `CMD` в `php-base`

Если `php-base` содержит финальный `CMD`, он уже не совсем base, а “полуготовый runnable image”.

Проблемы такого подхода:

* хуже переиспользуемость
* труднее добавлять отдельные stages
* непонятно, где кончается база и начинается конкретное окружение

---

## Как бы я разложил твой Dockerfile

### `php-base`

Оставить здесь:

* `pie`
* apk deps
* php extensions
* `phpredis`
* optional xdebug
* composer
* rr
* `WORKDIR`
* создание `www-data`
* `STOPSIGNAL`
* `EXPOSE`

Но убрать отсюда:

* `COPY docker/php/php.ini ...`
* `USER www-data`
* `CMD [...]`

---

### `development`

Добавить stage:

```dockerfile
FROM php-base AS development

COPY docker/php/php.ini /usr/local/etc/php/conf.d/local.ini

USER www-data

CMD ["rr", "serve", "-c", "/var/www/laravel/.rr.yaml"]
```

---

### `production`

Оставить production как отдельный stage и туда уже:

```dockerfile
COPY docker/php/php.prod.ini /usr/local/etc/php/conf.d/local.ini
.../
USER www-data
CMD ["rr", "serve", "-c", "/var/www/laravel/.rr.yaml"]
```

---

## Что тогда менять в `docker-compose.yml`

Для локалки сейчас у тебя:

```yaml
target: php-base
```

Тогда нужно будет заменить на:

```yaml
target: development
```

Это и будет dev image.

---

# Теперь про второй вопрос — зачем у тебя второй `composer install`

Вот этот блок:

```dockerfile
RUN rm -rf bootstrap/cache/*.php \
    && composer install --no-dev --optimize-autoloader --no-interaction --no-progress
```

обычно делают по такой причине:

## Что происходило

1. Сначала ты копировал только `composer.json` и `composer.lock`
2. Делал:

```bash
composer install --no-dev --no-scripts
```

чтобы закэшировать слой `vendor`

3. Потом копировал весь проект
4. Но после копирования:

    * появлялись файлы приложения
    * появлялись artisan, config, providers и т.д.
    * нужно было выполнить `post-autoload-dump` / `package:discover`

Поэтому и делали **второй `composer install` уже без `--no-scripts`**

---

## Почему удаляли `bootstrap/cache/*.php`

Потому что при `COPY . ./` из хоста могли приехать:

* `bootstrap/cache/config.php`
* `bootstrap/cache/packages.php`
* `bootstrap/cache/services.php`

И они могли быть:

* собраны в dev-среде
* собраны с другими env
* собраны под другим набором пакетов
* просто протухшие

Это частая причина странных багов в production.

Так что сама идея правильная:

> перед финальной composer/script-фазой вычистить Laravel cache files, приехавшие с хоста.

---

## Что тут можно улучшить

Сейчас у тебя второй `composer install` делает слишком много.
Для production я бы сделал так:

### Первый install оставить

```dockerfile
COPY composer.json composer.lock ./
RUN composer install --no-dev --optimize-autoloader --no-interaction --no-scripts --no-progress
```

### После `COPY . ./` уже не делать второй полный install

А сделать более точечно:

```dockerfile
RUN rm -rf bootstrap/cache/*.php \
    && composer dump-autoload --optimize --no-dev --classmap-authoritative \
    && php artisan package:discover --ansi
```

---

## Почему это лучше

Потому что второй `composer install`:

* заново проходит dependency resolution/install flow
* тяжелее
* медленнее
* хотя тебе уже не нужно переустанавливать пакеты

А тебе после копирования проекта реально нужно в основном:

* обновить autoload
* прогнать package discovery
* убрать dev-кеши

То есть более точная и быстрая версия:

```dockerfile
RUN rm -rf bootstrap/cache/*.php \
    && composer dump-autoload --optimize --no-dev --classmap-authoritative \
    && php artisan package:discover --ansi
```

---

## Когда всё же нужен второй `composer install`

Он нужен, если у тебя есть composer scripts, которые:

* реально обязаны выполняться через `composer install`
* завязаны на special install flow
* или ты хочешь максимально простой и привычный pipeline без ручного вызова artisan-команд

Но для Laravel чаще достаточно:

* `composer install --no-scripts` на слое vendor
* потом `composer dump-autoload`
* потом `php artisan package:discover`

---

## Что я бы рекомендовал тебе

### По stage-структуре

Сделать так:

* `php-base`
* `development`
* `production`

Это лучший вариант для твоего Dockerfile.

### По финальному composer-шагу в production

Заменить:

```dockerfile
RUN rm -rf bootstrap/cache/*.php \
    && composer install --no-dev --optimize-autoloader --no-interaction --no-progress
```

на:

```dockerfile
RUN rm -rf bootstrap/cache/*.php \
    && composer dump-autoload --optimize --no-dev --classmap-authoritative \
    && php artisan package:discover --ansi
```

---

## Почему это особенно полезно у тебя

Потому что у тебя локальная разработка с volume mount:

```yaml
volumes:
  - .:/var/www/laravel
```

Значит dev-кеши с хоста действительно могут попасть в образ/контейнер и мешать.
И чистка `bootstrap/cache/*.php` у тебя не случайная — она вполне оправдана.

---

## Итог

Да, ты прав: `php-base` у тебя не просто база, а ещё и dev image.
Поэтому лучший путь — **не оставлять всё в `php-base`, а выделить отдельный `development` stage**.

И второй важный момент: твой второй `composer install` можно сделать легче и чище, заменив его на:

```dockerfile
RUN rm -rf bootstrap/cache/*.php \
    && composer dump-autoload --optimize --no-dev --classmap-authoritative \
    && php artisan package:discover --ansi
```

Если хочешь, я могу следующим сообщением дать тебе уже **готовый переписанный кусок Dockerfile с `development` stage и оптимизированным production stage**.
