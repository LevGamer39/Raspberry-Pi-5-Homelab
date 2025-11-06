#!/bin/bash

CONFIG_DIR="/data/data/com.termux/files/home/test2/config"
REPO_DIR="/data/data/com.termux/files/home/test2/backup/backup_repo"

# Функция для вывода ошибки
error_exit() {
    echo "Ошибка: $1" >&2
    exit 1
}

# Проверка зависимостей
for cmd in git rsync; do
    if ! command -v $cmd &> /dev/null; then
        error_exit "Необходима установка $cmd: pkg install $cmd"
    fi
done

# Запрос данных репозитория
read -p "Введите владельца репозитория (например: LevGamer39): " REPO_OWNER
read -p "Введите название репозитория (например: raspberry-pi-5): " REPO_NAME
read -p "Введите ветку для бэкапов (например: backups): " BRANCH
read -s -p "Введите GitHub токен: " GITHUB_TOKEN
echo

if [ -z "$REPO_OWNER" ] || [ -z "$REPO_NAME" ] || [ -z "$BRANCH" ] || [ -z "$GITHUB_TOKEN" ]; then
    error_exit "Все поля должны быть заполнены"
fi

# Формируем URL с токеном
REPO_URL="https://${GITHUB_TOKEN}@github.com/${REPO_OWNER}/${REPO_NAME}.git"

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

# Копирование конфигов
echo "Копирование конфигов..."
rsync -av --exclude='.git' ./ "$CONFIG_DIR/" || error_exit "Ошибка при копировании файлов"

echo "Конфиги успешно восстановлены из ветки $BRANCH"
