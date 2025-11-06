#!/bin/bash

CONFIG_DIR="/srv/containers/configs"
REPO_DIR="/srv/containers/backup/backup_repo"

error_exit() {
    echo "Ошибка: $1" >&2
    exit 1
}

# Запрос данных репозитория
read -p "Введите владельца репозитория (например: LevGamer39): " REPO_OWNER
read -p "Введите название репозитория (например: raspberry-pi-5): " REPO_NAME
read -p "Введите ветку для бэкапов (например: backups): " BRANCH
read -s -p "Введите GitHub токен: " GITHUB_TOKEN
echo

if [ -z "$REPO_OWNER" ] || [ -z "$REPO_NAME" ] || [ -z "$BRANCH" ] || [ -z "$GITHUB_TOKEN" ]; then
    error_exit "Все поля должны быть заполнены"
fi

REPO_URL="https://${GITHUB_TOKEN}@github.com/${REPO_OWNER}/${REPO_NAME}.git"

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
rsync -av --exclude='.git' "$CONFIG_DIR/" ./ || error_exit "Ошибка при копировании файлов"

if [ ! -d ".git" ]; then
    error_exit "Папка .git была удалена!"
fi

echo "Создание коммита..."
git add . || error_exit "Не удалось добавить файлы в индекс"
git commit -m "Backup $(date +'%Y-%m-%d %H:%M:%S')" || error_exit "Не удалось создать коммит"

echo "Синхронизация с GitHub..."
git fetch origin "$BRANCH" || echo "Нет удалённой ветки, пушим как новую"
git rebase origin/"$BRANCH" 2>/dev/null || echo "Ребейз не нужен"

echo "Отправка изменений на GitHub..."
git push -u origin "$BRANCH" || error_exit "Не удалось отправить изменения"

echo "Конфиги успешно сохранены в ветку $BRANCH"
