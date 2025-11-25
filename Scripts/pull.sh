#!/bin/bash

CONFIG_DIR="/srv/containers/configs"
REPO_DIR="/srv/containers/backup/backup_repo"

# Функция для вывода ошибки
error_exit() {
    echo "Ошибка: $1" >&2
    exit 1
}

# Функция подтверждения действия
confirm_action() {
    local message=$1
    local default=${2:-"n"}
    
    if [ "$default" = "y" ]; then
        read -p "$message [Y/n]: " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            return 1
        else
            return 0
        fi
    else
        read -p "$message [y/N]: " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            return 0
        else
            return 1
        fi
    fi
}

# Проверка зависимостей
for cmd in git rsync; do
    if ! command -v $cmd &> /dev/null; then
        error_exit "Необходима установка $cmd"
    fi
done

# Проверка существования конфигурации
if [ -f "$REPO_DIR/backup_config" ]; then
    echo "Найдена сохраненная конфигурация бэкапа:"
    source "$REPO_DIR/backup_config"
    echo "Репозиторий: $REPO_OWNER/$REPO_NAME"
    echo "Ветка: $BRANCH"
    echo "Токен: ${GITHUB_TOKEN:0:4}******"  # Показываем только первые 4 символа токена
    
    if confirm_action "Использовать сохраненную конфигурацию?" "y"; then
        USE_SAVED=true
    else
        # Удаляем сохраненную конфигурацию если не хотим использовать
        rm -f "$REPO_DIR/backup_config"
    fi
fi

if [ "$USE_SAVED" != "true" ]; then
    echo "Настройка репозитория для восстановления:"
    
    # Запрос данных репозитория
    read -p "Введите владельца репозитория (например: LevGamer39): " REPO_OWNER
    read -p "Введите название репозитория (например: raspberry-pi-5): " REPO_NAME
    read -p "Введите ветку для бэкапов (по умолчанию backups): " BRANCH_INPUT
    BRANCH=${BRANCH_INPUT:-"backups"}
    
    if confirm_action "Репозиторий приватный? (нужен токен)" "n"; then
        read -s -p "Введите GitHub токен: " GITHUB_TOKEN
        echo
    else
        GITHUB_TOKEN=""
    fi
    
    # Сохраняем конфигурацию
    if confirm_action "Сохранить конфигурацию для будущего использования?" "y"; then
        mkdir -p "$REPO_DIR"
        cat > "$REPO_DIR/backup_config" << CONFIG
REPO_OWNER="$REPO_OWNER"
REPO_NAME="$REPO_NAME"
BRANCH="$BRANCH"
GITHUB_TOKEN="$GITHUB_TOKEN"
CONFIG
        echo "✅ Конфигурация сохранена"
    fi
fi

if [ -z "$REPO_OWNER" ] || [ -z "$REPO_NAME" ] || [ -z "$BRANCH" ]; then
    error_exit "Все поля должны быть заполнены"
fi

if [ -n "$GITHUB_TOKEN" ]; then
    REPO_URL="https://${GITHUB_TOKEN}@github.com/${REPO_OWNER}/${REPO_NAME}.git"
else
    REPO_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}.git"
fi

echo "Используемый репозиторий: $REPO_OWNER/$REPO_NAME, ветка: $BRANCH"

# Создаем директорию репозитория
mkdir -p "$REPO_DIR" || error_exit "Не удалось создать директорию $REPO_DIR"
cd "$REPO_DIR" || error_exit "Не удалось перейти в $REPO_DIR"

# Клонирование или обновление репозитория
if [ ! -d ".git" ]; then
    echo "Клонирование репозитория..."
    git clone -b "$BRANCH" "$REPO_URL" . || error_exit "Не удалось клонировать репозиторий"
else
    echo "Обновление репозитория..."
    git checkout "$BRANCH" || error_exit "Не удалось переключиться на ветку $BRANCH"
    git pull origin "$BRANCH" || error_exit "Не удалось обновить репозиторий"
fi

# Создаем целевую директорию
mkdir -p "$CONFIG_DIR" || error_exit "Не удалось создать директорию $CONFIG_DIR"

# Создаем бэкап текущих конфигов
BACKUP_DIR="/srv/containers/backup/config_backup_$(date +%Y%m%d_%H%M%S)"
if confirm_action "Создать бэкап текущих конфигов перед восстановлением?" "y"; then
    echo "Создание бэкапа текущих конфигов..."
    mkdir -p "$BACKUP_DIR"
    rsync -av "$CONFIG_DIR/" "$BACKUP_DIR/" || echo "⚠️  Не удалось создать бэкап"
    echo "✅ Бэкап создан: $BACKUP_DIR"
fi

# Копирование конфигов
echo "Копирование конфигов..."
rsync -av --exclude='.git' --exclude='backup_config' ./ "$CONFIG_DIR/" || error_exit "Ошибка при копировании файлов"

echo "✅ Конфиги успешно восстановлены из ветки $BRANCH"

if [ -d "$BACKUP_DIR" ]; then
    echo "📦 Старые конфиги сохранены в: $BACKUP_DIR"
fi