# ==========================================
# Laravel Octane + RoadRunner (Boilerplate)
# ==========================================
.PHONY: \
	help check-files \
	up up-prod down down-prod restart build rebuild \
	logs logs-app logs-postgres logs-pgadmin logs-node logs-redis logs-queue logs-scheduler  \
	status \
	shell shell-node shell-postgres shell-redis \
	setup install-deps \
	composer-install composer-update composer-require \
	npm-install npm-dev npm-build \
	artisan composer migrate rollback fresh tinker test-php \
	rr-reload rr-workers \
	permissions info validate \
	clean clean-all dev-reset

# Цвета для вывода
YELLOW=\033[0;33m
GREEN=\033[0;32m
RED=\033[0;31m
NC=\033[0m

# Переменные Compose (используем merge для разработки)
COMPOSE = docker compose -f docker-compose.yml
COMPOSE_PROD = docker compose --env-file .env.production -f docker-compose.prod.local.yml

APP_PORT := $(shell grep '^APP_PORT=' .env 2>/dev/null | cut -d '=' -f 2- | tr -d '[:space:]')
ifeq ($(APP_PORT),)
APP_PORT := 8050
endif

# Сервисы (имена сервисов из compose-файлов)
APP_SERVICE=laravel-roadrunner
POSTGRES_SERVICE=laravel-postgres-rr
REDIS_SERVICE=laravel-redis-rr
PGADMIN_SERVICE=laravel-pgadmin-rr
NODE_SERVICE=laravel-node-rr
QUEUE_SERVICE=laravel-queue-rr
SCHEDULER_SERVICE=laravel-scheduler-rr

help: ## Показать справку
	@echo "$(YELLOW)Laravel Octane + RoadRunner Docker Boilerplate$(NC)"
	@echo "======================================"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "$(GREEN)%-20s$(NC) %s\n", $$1, $$2}'

check-files: ## Проверить наличие всех необходимых файлов
	@echo "$(YELLOW)Проверка файлов конфигурации...$(NC)"
	@test -f docker-compose.yml || (echo "$(RED)✗ docker-compose.yml не найден$(NC)" && exit 1)
	@test -f docker-compose.prod.yml || (echo "$(RED)✗ docker-compose.prod.yml не найден$(NC)" && exit 1)
	@test -f docker-compose.prod.local.yml || (echo "$(RED)✗ docker-compose.prod.local.yml не найден$(NC)" && exit 1)
	@test -f .env || (echo "$(RED)✗ .env не найден. Убедитесь, что вы настроили проект Laravel$(NC)" && exit 1)
	@test -f docker/php.Dockerfile || (echo "$(RED)✗ docker/php.Dockerfile не найден$(NC)" && exit 1)
	@test -f docker/php/php.ini || (echo "$(RED)✗ docker/php/php.ini не найден$(NC)" && exit 1)
	@test -f .rr.yaml || (echo "$(RED)✗ .rr.yaml не найден$(NC)" && exit 1)
	@echo "$(GREEN)✓ Все файлы на месте$(NC)"

up: check-files ## Запустить контейнеры (Dev)
	$(COMPOSE) up -d
	@echo "$(GREEN)✓ Проект запущен на http://localhost:$(APP_PORT)$(NC)"

up-prod: check-files ## Запустить контейнеры (Prod)
	$(COMPOSE_PROD) up -d
	@echo "$(GREEN)✓ Проект (Prod) запущен$(NC)"

down: ## Остановить контейнеры
	$(COMPOSE) down

down-prod: ## Остановить контейнеры (Prod)
	$(COMPOSE_PROD) down

restart: ## Перезапустить контейнеры
	$(COMPOSE) restart

build: ## Собрать образы (Dev)
	$(COMPOSE) build

rebuild: ## Пересобрать образы без кэша (Dev)
	$(COMPOSE) build --no-cache

logs: ## Показать логи всех сервисов
	$(COMPOSE) logs -f

logs-app: ## Просмотр логов RoadRunner
	$(COMPOSE) logs -f $(APP_SERVICE)

logs-postgres: ## Просмотр логов PostgreSQL
	$(COMPOSE) logs -f $(POSTGRES_SERVICE)

logs-pgadmin: ## Просмотр логов pgAdmin
	$(COMPOSE) logs -f $(PGADMIN_SERVICE)

logs-node: ## Просмотр логов Node (HMR)
	$(COMPOSE) logs -f $(NODE_SERVICE)

logs-redis: ## Просмотр логов Redis
	$(COMPOSE) logs -f $(REDIS_SERVICE)

logs-queue: ## Просмотр логов Queue Worker (Prod)
	$(COMPOSE_PROD) logs -f $(QUEUE_SERVICE)

logs-scheduler: ## Просмотр логов Scheduler (Prod)
	$(COMPOSE_PROD) logs -f $(SCHEDULER_SERVICE)

status: ## Статус контейнеров
	$(COMPOSE) ps

shell: ## Войти в контейнер приложения (RoadRunner)
	$(COMPOSE) exec $(APP_SERVICE) sh

shell-node: ## Подключиться к контейнеру Node
	$(COMPOSE) exec $(NODE_SERVICE) sh

shell-postgres: ## Подключиться к PostgreSQL CLI
	@echo "$(YELLOW)Подключение к базе...$(NC)"
	@DB_USER=$$(grep '^DB_USERNAME=' .env | cut -d '=' -f 2- | tr -d '[:space:]'); \
	DB_NAME=$$(grep '^DB_DATABASE=' .env | cut -d '=' -f 2- | tr -d '[:space:]'); \
	$(COMPOSE) exec $(POSTGRES_SERVICE) psql -U $$DB_USER -d $$DB_NAME

shell-redis: ## Подключиться к Redis CLI
	@echo "$(YELLOW)Подключение к Redis...$(NC)"
	$(COMPOSE) exec $(REDIS_SERVICE) redis-cli ping

# --- Команды Laravel ---

setup: ## Полная инициализация проекта с нуля
	@make build
	@make up
	@echo "$(YELLOW)Ожидание готовности PostgreSQL...$(NC)"
	@$(COMPOSE) exec $(POSTGRES_SERVICE) sh -c 'until pg_isready; do sleep 1; done'
	@echo "$(YELLOW)Ожидание готовности Redis...$(NC)"
	@$(COMPOSE) exec $(REDIS_SERVICE) sh -c 'until redis-cli ping | grep -q PONG; do sleep 1; done'
	@make install-deps
	@make artisan CMD="key:generate"
	@make migrate
	@make permissions
	@echo "$(GREEN)✓ Проект готов: http://localhost:8000$(NC)"

install-deps: ## Установка всех зависимостей (Composer + NPM)
	@echo "$(YELLOW)Установка зависимостей...$(NC)"
	@$(MAKE) composer-install
	@$(MAKE) npm-install

# --- Команды Composer ---

composer-install: ## Установить зависимости через Composer
	$(COMPOSE) exec $(APP_SERVICE) composer install

composer-update: ## Обновить зависимости через Composer
	$(COMPOSE) exec $(APP_SERVICE) composer update

composer-require: ## Установить пакет через Composer (make composer-require PACKAGE=vendor/package)
	$(COMPOSE) exec $(APP_SERVICE) composer require $(PACKAGE)

npm-install: ## Установить NPM зависимости
	$(COMPOSE) exec $(NODE_SERVICE) npm install

npm-dev: ## Запустить Vite в режиме разработки (hot reload)
	$(COMPOSE) exec $(NODE_SERVICE) npm run dev

npm-build: ## Собрать фронтенд
	$(COMPOSE) exec $(NODE_SERVICE) npm run build

# --- Команды Artisan ---

artisan: ## Запустить команду artisan (make artisan CMD="migrate")
	$(COMPOSE) exec $(APP_SERVICE) php artisan $(CMD)

composer: ## Запустить команду composer (make composer CMD="install")
	$(COMPOSE) exec $(APP_SERVICE) composer $(CMD)

migrate: ## Запустить миграции
	$(COMPOSE) exec $(APP_SERVICE) php artisan migrate

rollback: ## Откатить миграции
	$(COMPOSE) exec $(APP_SERVICE) php artisan migrate:rollback

fresh: ## Пересоздать базу и запустить сиды
	$(COMPOSE) exec $(APP_SERVICE) php artisan migrate:fresh --seed

tinker: ## Запустить Laravel Tinker
	$(COMPOSE) exec $(APP_SERVICE) php artisan tinker

test-php: ## Запустить тесты PHP (PHPUnit)
	$(COMPOSE) exec $(APP_SERVICE) php artisan test

# --- RoadRunner ---
rr-reload: ## Перезагрузить воркеры RoadRunner (без перезапуска контейнера)
	$(COMPOSE) exec $(APP_SERVICE) rr reset -c /var/www/laravel/.rr.yaml

rr-workers: ## Показать статус воркеров RoadRunner
	$(COMPOSE) exec $(APP_SERVICE) rr workers -c /var/www/laravel/.rr.yaml

# --- Утилиты ---

permissions: ## Исправить права доступа для Laravel (storage/cache)
	@echo "$(YELLOW)Исправление прав доступа...$(NC)"
	$(COMPOSE) exec $(APP_SERVICE) sh -c "if [ -d storage ]; then chown -R www-data:www-data storage bootstrap/cache && chmod -R ug+rwX storage bootstrap/cache; fi"
	@echo "$(GREEN)✓ Права доступа исправлены$(NC)"

info: ## Показать информацию о проекте
	@echo "$(YELLOW)Laravel Octane + RoadRunner Development Environment$(NC)"
	@echo "======================================"
	@echo "$(GREEN)Сервисы:$(NC)"
	@echo "  • PHP 8.5 CLI + RoadRunner (Alpine)"
	@echo "  • PostgreSQL 18.2"
	@echo "  • Redis"
	@echo "  • pgAdmin 4 (dev only)"
	@echo "  • Node.js (Vite HMR, dev only)"
	@echo ""
	@echo "$(GREEN)Структура:$(NC)"
	@echo "  • docker/           - Dockerfile и конфиги PHP"
	@echo "  • .rr.yaml          - конфигурация RoadRunner"
	@echo "  • .env              - единый файл настроек (Laravel + Docker)"
	@echo ""
	@echo "$(GREEN)Порты:$(NC)"
	@echo "  • 8000 - RoadRunner (HTTP Server)"
	@echo "  • 2114 - RoadRunner Health Check"
	@echo "  • 5173 - Vite HMR (dev only)"
	@echo "  • 5432 - PostgreSQL (dev forwarded)"
	@echo "  • 6379 - Redis (dev forwarded)"
	@echo "  • 8080 - pgAdmin (dev only)"

validate: ## Проверить доступность сервисов по HTTP
	@echo "$(YELLOW)Проверка работы сервисов...$(NC)"
	@echo -n "RoadRunner (http://localhost:8000): "
	@curl -s -o /dev/null -w "%{http_code}" http://localhost:8000 && echo " $(GREEN)✓$(NC)" || echo " $(RED)✗$(NC)"
	@echo -n "Health Check (http://localhost:2114): "
	@curl -s -o /dev/null -w "%{http_code}" http://localhost:2114/health?plugin=http && echo " $(GREEN)✓$(NC)" || echo " $(RED)✗$(NC)"
	@echo -n "pgAdmin (http://localhost:8080): "
	@curl -s -o /dev/null -w "%{http_code}" http://localhost:8080 && echo " $(GREEN)✓$(NC)" || echo " $(RED)✗$(NC)"
	@echo "$(YELLOW)Статус контейнеров:$(NC)"
	@$(COMPOSE) ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"

clean: ## Удалить контейнеры и тома
	$(COMPOSE) down -v
	@echo "$(RED)! Контейнеры и данные БД удалены$(NC)"

clean-all: ## Полная очистка (контейнеры, образы, тома)
	@echo "$(YELLOW)Полная очистка...$(NC)"
	$(COMPOSE) down -v --rmi all
	@echo "$(GREEN)✓ Выполнена полная очистка$(NC)"

dev-reset: clean-all build up ## Сброс среды разработки
	@echo "$(GREEN)✓ Среда разработки сброшена и перезапущена!$(NC)"

.DEFAULT_GOAL := help
