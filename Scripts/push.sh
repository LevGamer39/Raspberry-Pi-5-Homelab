#!/bin/bash

CONFIG_DIR="/srv/containers/configs"
REPO_DIR="/srv/containers/backup/backup_repo"

error_exit() {
    echo "Ошибка: $1" >&2
    exit 1
}

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

for cmd in git rsync; do
    if ! command -v $cmd &> /dev/null; then
        error_exit "Необходима установка $cmd"
    fi
done

if [ -f "$REPO_DIR/backup_config" ]; then
    echo "Найдена сохраненная конфигурация бэкапа:"
    source "$REPO_DIR/backup_config"
    echo "Репозиторий: $REPO_OWNER/$REPO_NAME"
    echo "Ветка: $BRANCH"
    echo "Токен: ${GITHUB_TOKEN:0:4}******"
    
    if confirm_action "Использовать сохраненную конфигурацию?" "y"; then
        USE_SAVED=true
    else
        rm -f "$REPO_DIR/backup_config"
    fi
fi

if [ "$USE_SAVED" != "true" ]; then
    echo "Настройка репозитория для бэкапа:"
    
    read -p "Введите владельца репозитория: " REPO_OWNER
    read -p "Введите название репозитория: " REPO_NAME
    
    read -p "Введите ветку для бэкапов: " BRANCH_INPUT
    BRANCH=${BRANCH_INPUT}

    if [ -z "$BRANCH" ]; then
        error_exit "Ветка не может быть пустой"
    fi

    if confirm_action "Репозиторий приватный? (нужен токен)" "y"; then
        read -s -p "Введите GitHub токен: " GITHUB_TOKEN
        echo
    else
        GITHUB_TOKEN=""
    fi
    
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

mkdir -p "$REPO_DIR" || error_exit "Не удалось создать директорию $REPO_DIR"
cd "$REPO_DIR" || error_exit "Не удалось перейти в $REPO_DIR"

if [ ! -d ".git" ]; then
    echo "Инициализация нового репозитория..."
    git init -b "$BRANCH" || error_exit "Не удалось инициализировать репозиторий"
    git remote add origin "$REPO_URL" || error_exit "Не удалось добавить удаленный репозиторий"
else
    git checkout "$BRANCH" 2>/dev/null || git checkout -b "$BRANCH"
fi

echo "Копирование конфигов..."
rsync -av --exclude='.git' --exclude='backup_config' "$CONFIG_DIR/" ./ || error_exit "Ошибка при копировании файлов"

if [ ! -d ".git" ]; then
    error_exit "Папка .git была удалена!"
fi

echo "Создание коммита..."
git add . || error_exit "Не удалось добавить файлы в индекс"

if git diff --cached --quiet; then
    echo "⚠️  Нет изменений для коммита"
else
    git commit -m "Backup $(date +'%Y-%m-%d %H:%M:%S')" || error_exit "Не удалось создать коммит"

    echo "Синхронизация с GitHub..."
    git fetch origin "$BRANCH" 2>/dev/null || echo "ℹ️  Нет удалённой ветки, пушим как новую"
    
    if git ls-remote --heads "$REPO_URL" "$BRANCH" | grep -q "$BRANCH"; then
        echo "ℹ️  Обновление локальной копии..."
        git rebase "origin/$BRANCH" 2>/dev/null || echo "⚠️  Конфликт при обновлении, продолжаем..."
    fi

    echo "Отправка изменений на GitHub..."
    git push -u origin "$BRANCH" || error_exit "Не удалось отправить изменения"

    echo "✅ Конфиги успешно сохранены в ветку $BRANCH"
fi