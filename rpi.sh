#!/bin/bash

lcd_services=false
menager_name=""
USERNAME=""
PASSWORD=""
OS_TYPE=""
PACKAGE_MANAGER=""
CREATE_USER=true
BACKUP_REPO_OWNER=""
BACKUP_REPO_NAME=""
BACKUP_BRANCH="backups"
BACKUP_GITHUB_TOKEN=""

DOCKER_USER="mediauser"
STEAM_USER="steam"
ASF_USER="asf"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

INSTALL_PACKAGES=false
INSTALL_LCD=false
INSTALL_DOTNET=false
INSTALL_PORTAINER=false
INSTALL_CONTAINERS=false
INSTALL_NGINX=false
INSTALL_STEAMCMD=false
SETUP_CONFIG=false
SETUP_BACKUP=false

# Функция: Определение ОС
detect_os() {
    if [ -f "/etc/arch-release" ]; then
        OS_TYPE="arch"
        PACKAGE_MANAGER="pacman"
    elif [ -f "/etc/debian_version" ]; then
        OS_TYPE="debian"
        PACKAGE_MANAGER="apt"
    else
        echo -e "${RED}❌ Неподдерживаемая операционная система${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ Обнаружена ОС: $OS_TYPE${NC}"
}

# Функция: Логирование
log_message() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

# Функция: Подтверждение действия
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

# Функция: Настройка Git
setup_git_config() {
    if command -v git &>/dev/null; then
        log_message "Настройка Git"
        
        if confirm_action "Настроить глобальную конфигурацию Git?" "y"; then
            read -p "Введите имя для Git (по умолчанию: YourName): " git_name
            git_name=${git_name:-"YourName"}
            
            read -p "Введите email для Git (по умолчанию: your@email.com): " git_email
            git_email=${git_email:-"your@email.com"}
            
            sudo -u "$USERNAME" git config --global user.name "$git_name"
            sudo -u "$USERNAME" git config --global user.email "$git_email"
            
            echo -e "${GREEN}✅ Git настроен: $git_name <$git_email>${NC}"
        else
            echo -e "${YELLOW}⚠️ Git не настроен${NC}"
        fi
    fi
}

# Функция: Все вопросы в начале
ask_all_questions() {
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}         Настройка установки${NC}"
    echo -e "${BLUE}=========================================${NC}"
    
    log_message "Настройка пользователя"
    
    if confirm_action "Создать нового пользователя?" "y"; then
        CREATE_USER=true
        
        echo "Изменить имя пользователя"
        echo "1. Да"
        echo "2. Нет (по умолчанию: user)"
        read -p "Введите 1 или 2: " name_choice

        if [ "$name_choice" = "1" ]; then
            while true; do
                read -p "Введите имя пользователя: " USERNAME
                if [[ "$USERNAME" =~ ^[A-Za-z0-9._-]+$ ]]; then
                    break
                else
                    echo -e "${RED}❌ Ошибка: допустимы только A–Z, a–z, 0–9, . _ -${NC}"
                fi
            done
        else
            USERNAME="user"
            echo -e "${YELLOW}⚠️  Используется имя пользователя по умолчанию: user${NC}"
        fi
        
        echo "Изменить пароль пользователя"
        echo "1. Да"
        echo "2. Нет (будет запрошен позже)"
        read -p "Введите 1 или 2: " password_choice

        if [ "$password_choice" = "1" ]; then
            while true; do
                read -s -p "Введите пароль: " PASSWORD
                echo
                if [ ${#PASSWORD} -ge 5 ]; then
                    read -s -p "Подтвердите пароль: " PASSWORD_CONFIRM
                    echo
                    if [ "$PASSWORD" = "$PASSWORD_CONFIRM" ]; then
                        break
                    else
                        echo -e "${RED}❌ Пароли не совпадают${NC}"
                    fi
                else
                    echo -e "${RED}❌ Пароль должен быть не короче 5 символов${NC}"
                fi
            done
        else
            PASSWORD=""
            echo -e "${YELLOW}⚠️  Пароль будет установлен позже${NC}"
        fi
    else
        CREATE_USER=false
        echo -e "${YELLOW}⚠️  Создание пользователя пропущено${NC}"
        
        USERNAME=$(whoami)
        echo -e "${GREEN}✅ Будет использован текущий пользователь: $USERNAME${NC}"
    fi

    log_message "Настройка сервисов"
    
    if confirm_action "Включить LCD сервис?" "n"; then
        lcd_services=true
        INSTALL_LCD=true
        echo -e "${GREEN}✅ LCD сервис будет включен${NC}"
    else
        lcd_services=false
        echo -e "${YELLOW}⚠️  LCD сервис отключен${NC}"
    fi
    
    if [ "$OS_TYPE" = "arch" ]; then
        echo "Выберите AUR менеджер:"
        echo "1. Yay (рекомендуется)"
        echo "2. Paru"
        read -p "Введите 1 или 2: " menager_choice

        if [ "$menager_choice" = "1" ]; then
            menager_name="yay"
        elif [ "$menager_choice" = "2" ]; then
            menager_name="paru"
        else
            menager_name="yay"
            echo -e "${YELLOW}⚠️  По умолчанию будет установлен Yay${NC}"
        fi
        echo -e "${GREEN}✅ Выбран менеджер: $menager_name${NC}"
    fi

    log_message "Настройка бэкапа конфигов"
    
    if confirm_action "Настроить автоматический бэкап конфигов в GitHub?" "n"; then
        SETUP_BACKUP=true
        
        read -p "Введите владельца репозитория: " BACKUP_REPO_OWNER
        read -p "Введите название репозитория: " BACKUP_REPO_NAME
        read -p "Введите ветку для бэкапов: " BACKUP_BRANCH
        
        if confirm_action "Репозиторий приватный? (нужен токен)" "y"; then
            read -s -p "Введите GitHub токен: " BACKUP_GITHUB_TOKEN
            echo
        else
            BACKUP_GITHUB_TOKEN=""
        fi
        
        echo -e "${GREEN}✅ Бэкап настроен${NC}"
    fi

    echo -e "${BLUE}-----------------------------------------${NC}"
    log_message "Выбор компонентов для установки"
    
    if confirm_action "Установить обновления и базовые пакеты?" "y"; then
        INSTALL_PACKAGES=true
    fi
    
    if confirm_action "Настроить системные конфиги?" "y"; then
        SETUP_CONFIG=true
    fi
    
    if confirm_action "Установить .NET SDK?" "n"; then
        INSTALL_DOTNET=true
    fi
    
    if confirm_action "Установить Portainer?" "y"; then
        INSTALL_PORTAINER=true
    fi
    
    if confirm_action "Создать структуру папок и установить контейнеры?" "y"; then
        INSTALL_CONTAINERS=true
    fi
    
    if confirm_action "Установить SteamCMD и Box64 (для игровых серверов)?" "n"; then
        INSTALL_STEAMCMD=true
    fi

    if confirm_action "Настроить nginx с SSL?" "n"; then
        INSTALL_NGINX=true
    fi
    
    echo -e "${GREEN}✅ Конфигурация сохранена${NC}"
}

# Функция: Получить путь к config.txt
get_config_path() {
    if [ "$OS_TYPE" = "debian" ] && [ -f "/boot/firmware/config.txt" ]; then
        echo "/boot/firmware/config.txt"
    elif [ -f "/boot/config.txt" ]; then
        echo "/boot/config.txt"
    else
        echo ""
    fi
}

# Функция: Добавить настройки в config.txt
add_fan_config() {
    local config_file=$1
    
    if [ -z "$config_file" ] || [ ! -f "$config_file" ]; then
        echo -e "${YELLOW}⚠️  Файл config.txt не найден, пропускаем настройку вентилятора${NC}"
        return
    fi
    
    log_message "Добавление настроек вентилятора в $config_file"
    
    cp "$config_file" "${config_file}.backup"
    
	sed -i '/^#dtparam=i2c_arm=on/s/^#//' "$config_file"
	
    grep -v "dtparam=fan_temp" "$config_file" > "${config_file}.tmp"
    
    cat >> "${config_file}.tmp" << EOF
dtparam=pciex1_gen=3
# Fan control settings
dtparam=fan_temp0=40000
dtparam=fan_temp0_hyst=5000
dtparam=fan_temp0_speed=50
dtparam=fan_temp1=50000
dtparam=fan_temp1_hyst=5000
dtparam=fan_temp1_speed=75
dtparam=fan_temp2=60000
dtparam=fan_temp2_hyst=5000
dtparam=fan_temp2_speed=150
dtparam=fan_temp3=70000
dtparam=fan_temp3_hyst=10000
dtparam=fan_temp3_speed=255
EOF

    mv "${config_file}.tmp" "$config_file"
    echo -e "${GREEN}✅ Настройки вентилятора добавлены в $config_file${NC}"
}

# Функция: Настройка sudoers
setup_sudoers() {
    log_message "Настройка sudoers"
    
    if [ "$OS_TYPE" = "arch" ]; then
        if [ -f "/etc/sudoers.back" ]; then
            echo -e "${YELLOW}⚠️  Бэкап sudoers уже существует${NC}"
        else
            cp /etc/sudoers /etc/sudoers.back
        fi
        
        curl -sL "https://github.com/LevGamer39/Raspberry-Pi-5-Homelab/raw/refs/heads/main/Config/sudoers" -o /etc/sudoers
        chmod 440 /etc/sudoers
        echo -e "${GREEN}✅ sudoers настроен для Arch${NC}"
    else
        if [ "$CREATE_USER" = true ] && [ "$USERNAME" != "root" ]; then
            usermod -aG sudo "$USERNAME"
            echo -e "${GREEN}✅ Пользователь $USERNAME добавлен в группу sudo${NC}"
        fi
    fi
}

# Функция: Установка Docker для Debian
install_docker_debian() {
    log_message "Установка Docker для Debian"

    apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

    apt update
    apt install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release

    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt update
    apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    mkdir -p /etc/systemd/system/docker.service.d
    cat > /etc/systemd/system/docker.service.d/override.conf << 'EOF'
[Service]
Environment=DOCKER_MIN_API_VERSION=1.24
EOF

    systemctl daemon-reload
    systemctl restart docker

    echo -e "${GREEN}✅ Docker установлен${NC}"
}

# Функция: Установка пакетов для Arch
install_packages_arch() {
    log_message "Обновление системы и установка пакетов (Arch)"
    
    echo -e "${YELLOW}⏳ Обновление системы...${NC}"
    pacman -Syu --noconfirm
    
    echo -e "${YELLOW}⏳ Установка базовых пакетов...${NC}"
    pacman -S --noconfirm docker git python python-pip flashrom i2c-tools sudo nginx rsync base-devel docker-compose wget
    
    systemctl start docker
    systemctl enable --now docker
    
    if [ "$menager_name" = "yay" ]; then
        log_message "Установка yay"
        git clone https://aur.archlinux.org/yay.git /tmp/yay
        cd /tmp/yay
        makepkg -si --noconfirm
        cd /
        rm -rf /tmp/yay
    elif [ "$menager_name" = "paru" ]; then
        log_message "Установка paru"
        git clone https://aur.archlinux.org/paru.git /tmp/paru
        cd /tmp/paru
        makepkg -si --noconfirm
        cd /
        rm -rf /tmp/paru
    fi
}

# Функция: Установка пакетов для Debian/Raspbian
install_packages_debian() {
    log_message "Обновление системы и установка пакетов (Debian/Raspbian)"
    
    echo -e "${YELLOW}⏳ Обновление системы...${NC}"
    apt update && apt upgrade -y
    
    echo -e "${YELLOW}⏳ Установка базовых пакетов...${NC}"
    apt install -y git python3 python3-pip flashrom i2c-tools sudo nginx rsync build-essential wget util-linux-extra libarchive-tools
    
    install_docker_debian
    
    pip3 install docker-compose --break-system-packages
    
    systemctl start docker
    systemctl enable --now docker
}

# Функция: Установка базовых пакетов
install_packages() {
    if [ "$INSTALL_PACKAGES" = true ]; then
        log_message "Установка пакетов"
        
        case "$OS_TYPE" in
            "arch")
                install_packages_arch
                ;;
            "debian")
                install_packages_debian
                ;;
        esac
        echo -e "${GREEN}✅ Пакеты установлены${NC}"
    else
        echo -e "${YELLOW}⚠️  Пропущена установка пакетов${NC}"
    fi
}

# Функция: Настройка локалей
setup_locales() {
    log_message "Настройка локалей"
    
    if [ "$OS_TYPE" = "arch" ]; then
        sed -i 's/^#\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen
        sed -i 's/^#\(ru_RU.UTF-8 UTF-8\)/\1/' /etc/locale.gen
        locale-gen
        echo "LANG=en_US.UTF-8" > /etc/locale.conf
        echo "LC_ALL=en_US.UTF-8" >> /etc/locale.conf
    elif [ "$OS_TYPE" = "debian" ]; then
        apt install -y locales
        
        sed -i 's/^# \(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen
        sed -i 's/^# \(ru_RU.UTF-8 UTF-8\)/\1/' /etc/locale.gen
        locale-gen
        
        update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
    fi
    
    export LANG=en_US.UTF-8
    export LC_ALL=en_US.UTF-8
    export LANGUAGE=en_US:en
    
    echo -e "${GREEN}✅ Локали настроены (основная: en_US.UTF-8, дополнительная: ru_RU.UTF-8)${NC}"
}

# Функция: Настройка конфигурации
setup_config() {
    if [ "$SETUP_CONFIG" = true ]; then
        log_message "Настройка системной конфигурации"
        
        setup_locales
        
        local config_path=$(get_config_path)
        if [ -n "$config_path" ]; then
            if confirm_action "Добавить настройки управления вентилятором в config.txt?" "y"; then
                add_fan_config "$config_path"
            fi
        fi
        
        setup_sudoers
        
        timedatectl set-timezone Europe/Kaliningrad
        hwclock -s
        
        setup_git_config

        echo -e "${GREEN}✅ Конфиги настроены${NC}"
    else
        echo -e "${YELLOW}⚠️  Пропущена настройка конфигов${NC}"
    fi
}

# Функция: Создание пользователя
add_user() {
    if [ "$CREATE_USER" = true ]; then
        log_message "Создание пользователя: $USERNAME"
        
        if ! id "$USERNAME" &>/dev/null; then
            useradd -m -s /bin/bash "$USERNAME"
            echo -e "${GREEN}✅ Пользователь $USERNAME создан${NC}"
        else
            echo -e "${YELLOW}⚠️  Пользователь $USERNAME уже существует${NC}"
        fi
        
        if [ -n "$PASSWORD" ]; then
            echo "$USERNAME:$PASSWORD" | chpasswd
            echo -e "${GREEN}✅ Пароль установлен${NC}"
        else
            echo -e "${YELLOW}⚠️  Установите пароль для пользователя $USERNAME:${NC}"
            passwd "$USERNAME"
        fi
        
        usermod -aG wheel "$USERNAME"
        if [ "$OS_TYPE" = "debian" ]; then
            usermod -aG sudo "$USERNAME"
        fi
		
        echo -e "${GREEN}✅ Пользователь $USERNAME добавлен в группы wheel/sudo${NC}"
    else
        echo -e "${YELLOW}⚠️  Создание пользователя пропущено${NC}"
        echo -e "${GREEN}✅ Используется текущий пользователь: $USERNAME${NC}"
    fi
}

# Функция: Создание служебных пользователей
add_service_users() {
    log_message "Создание служебных пользователей для сервисов"
    
    if ! id "$DOCKER_USER" &>/dev/null; then
        useradd -r -s /usr/sbin/nologin "$DOCKER_USER"
        echo -e "${GREEN}✅ Служебный пользователь $DOCKER_USER создан${NC}"
    else
        echo -e "${YELLOW}⚠️  Служебный пользователь $DOCKER_USER уже существует${NC}"
    fi
    
    if [ "$INSTALL_STEAMCMD" = true ]; then
        if ! id "$STEAM_USER" &>/dev/null; then
            useradd -r -s /usr/sbin/nologin "$STEAM_USER"
            echo -e "${GREEN}✅ Служебный пользователь $STEAM_USER создан${NC}"
        else
            echo -e "${YELLOW}⚠️  Служебный пользователь $STEAM_USER уже существует${NC}"
        fi
    fi
	
    if ! id "$DOCKER_USER" &>/dev/null; then
        useradd -r -s /usr/sbin/nologin "$ASF_USER"
        echo -e "${GREEN}✅ Служебный пользователь $ASF_USER создан${NC}"
    else
        echo -e "${YELLOW}⚠️  Служебный пользователь $ASF_USER уже существует${NC}"
    fi
    
    if getent group docker >/dev/null; then
        usermod -aG docker "$USERNAME"
        echo -e "${GREEN}✅ Пользователь $USERNAME добавлен в группу docker (для Portainer и управления)${NC}"
    fi
}

# Функция: Настройка скриптов бэкапа
setup_backup_scripts() {
    if [ "$SETUP_BACKUP" = true ]; then
        log_message "Настройка скриптов бэкапа"
        
        cd /srv/containers/backup
        
        echo -e "${YELLOW}⏳ Загрузка скриптов бэкапа...${NC}"
        curl -sL "https://github.com/LevGamer39/Raspberry-Pi-5-Homelab/raw/refs/heads/main/Scripts/push.sh" -o push.sh
        curl -sL "https://github.com/LevGamer39/Raspberry-Pi-5-Homelab/raw/refs/heads/main/Scripts/pull.sh" -o pull.sh
        
        chmod +x push.sh pull.sh
        
        if [ -n "$BACKUP_REPO_OWNER" ] && [ -n "$BACKUP_REPO_NAME" ]; then
            mkdir -p /srv/containers/backup/backup_repo
            cat > /srv/containers/backup/backup_repo/backup_config << CONFIG
REPO_OWNER="$BACKUP_REPO_OWNER"
REPO_NAME="$BACKUP_REPO_NAME"
BRANCH="$BACKUP_BRANCH"
GITHUB_TOKEN="$BACKUP_GITHUB_TOKEN"
CONFIG
            echo -e "${GREEN}✅ Конфигурация бэкапа сохранена${NC}"
        fi
        
        echo -e "${GREEN}✅ Скрипты бэкапа настроены${NC}"
    fi
}

# Функция: Установка LCD сервиса
setup_lcd() {
    if [ "$INSTALL_LCD" = true ]; then
        log_message "Установка LCD сервиса"
        
        mkdir -p /opt/lcdmonitor/
        cd /opt/lcdmonitor/
        
        echo -e "${YELLOW}⏳ Загрузка файлов LCD...${NC}"
        curl -sL "https://github.com/LevGamer39/LCD-Monitor/raw/refs/heads/main/shutdown_lcd.py" -o shutdown_lcd.py
        curl -sL "https://github.com/LevGamer39/LCD-Monitor/raw/refs/heads/main/lcd_monitor.py" -o lcd_monitor.py
        curl -sL "https://github.com/LevGamer39/LCD-Monitor/raw/refs/heads/main/requirements.txt" -o requirements.txt
        
        echo -e "${YELLOW}⏳ Установка зависимостей Python...${NC}"
        if [ "$OS_TYPE" = "arch" ]; then
            pip install -r requirements.txt --break-system-packages
        else
            pip3 install -r requirements.txt --break-system-packages
        fi
        
        echo -e "${YELLOW}⏳ Настройка сервисов...${NC}"
        cd /etc/systemd/system/
        curl -sL "https://github.com/LevGamer39/LCD-Monitor/raw/refs/heads/main/lcd-shutdown.service" -o lcd-shutdown.service
        curl -sL "https://github.com/LevGamer39/LCD-Monitor/raw/refs/heads/main/lcd-reboot.service" -o lcd-reboot.service
        curl -sL "https://github.com/LevGamer39/LCD-Monitor/raw/refs/heads/main/lcdmonitor.service" -o lcdmonitor.service

        systemctl daemon-reload
        systemctl enable lcd-shutdown.service
        systemctl enable lcd-reboot.service
        systemctl enable lcdmonitor.service
        
        echo -e "${GREEN}✅ LCD сервис установлен и включен${NC}"
    fi
}

# Функция: Установка .NET
install_dotnet() {
    if [ "$INSTALL_DOTNET" = true ]; then
        log_message "Установка .NET SDK"
        
        cd /tmp
        curl -L https://dot.net/v1/dotnet-install.sh -o dotnet-install.sh
        chmod +x ./dotnet-install.sh
        
        echo -e "${YELLOW}⏳ Установка .NET...${NC}"
        ./dotnet-install.sh --version latest
        
        export DOTNET_ROOT=$HOME/.dotnet
        export PATH=$PATH:$DOTNET_ROOT:$DOTNET_ROOT/tools
        
        if [ "$CREATE_USER" = true ]; then
            echo "export DOTNET_ROOT=\$HOME/.dotnet" >> /home/$USERNAME/.bashrc
            echo "export PATH=\$PATH:\$DOTNET_ROOT:\$DOTNET_ROOT/tools" >> /home/$USERNAME/.bashrc
        fi
        echo "export DOTNET_ROOT=\$HOME/.dotnet" >> /root/.bashrc
        echo "export PATH=\$PATH:\$DOTNET_ROOT:\$DOTNET_ROOT/tools" >> /root/.bashrc
        
        echo -e "${GREEN}✅ .NET SDK установлен${NC}"
    fi
}

# Функция: Установка Portainer
install_portainer() {
    if [ "$INSTALL_PORTAINER" = true ]; then
        log_message "Установка Portainer"
        
        echo -e "${YELLOW}⏳ Запуск Portainer...${NC}"
        docker volume create portainer_data
        docker run -d -p 8000:8000 -p 9443:9443 --name portainer --restart=always \
                 -v /var/run/docker.sock:/var/run/docker.sock \
                 -v portainer_data:/data \
                 portainer/portainer-ce:latest
        
        echo -e "${GREEN}✅ Portainer установлен и запущен${NC}"
        echo -e "${BLUE}📊 Portainer доступен по адресу: https://localhost:9443${NC}"
    fi
}

# Функция: Установка SteamCMD и Box64
install_steam_env() {
    if [ "$INSTALL_STEAMCMD" = true ]; then
        log_message "Установка Box64 и SteamCMD"
        
        echo -e "${YELLOW}⏳ Установка Box64 (эмуляция x86_64)...${NC}"
        if [ "$OS_TYPE" = "debian" ]; then
            wget https://ryanfortner.github.io/box64-debs/box64.list -O /etc/apt/sources.list.d/box64.list
            wget -qO- https://ryanfortner.github.io/box64-debs/KEY.gpg | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/box64-debs-archive-keyring.gpg
            apt update
            apt install -y box64
        elif [ "$OS_TYPE" = "arch" ]; then
             log_message "Сборка Box64 через AUR..."
             sudo -u "$USERNAME" $menager_name -S --noconfirm box64
        fi
        
        echo -e "${YELLOW}⏳ Настройка структуры серверов...${NC}"
        mkdir -p /srv/servers/steamcmd
        
        echo -e "${YELLOW}⏳ Загрузка SteamCMD...${NC}"
        cd /srv/servers/steamcmd
        curl -sqL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" | tar zxvf -
        
        chown -R "$STEAM_USER":"$STEAM_USER" /srv/servers
        
        echo -e "${GREEN}✅ SteamCMD установлен в /srv/servers/steamcmd${NC}"
        echo -e "${GREEN}✅ Box64 установлен${NC}"
    fi
}

# Функция: Установка контейнеров
install_containers() {
    if [ "$INSTALL_CONTAINERS" = true ]; then
        log_message "Установка контейнеров и создание структуры папок"
        
        echo -e "${YELLOW}⏳ Создание структуры папок...${NC}"
        mkdir -p /srv/containers/{backup,compose,configs,backup/backup_repo}
        mkdir -p /srv/mediahub/{downloads,media,media/films}
        
        # Получаем PUID и PGID для служебного пользователя mediauser
        local PUID=$(id -u "$DOCKER_USER" 2>/dev/null || echo 1000)
        local PGID=$(id -g "$DOCKER_USER" 2>/dev/null || echo 1000)
        
        cat > /srv/containers/compose/.env << ENV
PUID=$PUID
PGID=$PGID
TZ=Europe/Kaliningrad
ENV
        
        echo -e "${YELLOW}⏳ Загрузка docker-compose.yml...${NC}"
        cd /srv/containers/compose
        curl -sL "https://github.com/LevGamer39/Raspberry-Pi-5-Homelab/raw/refs/heads/main/Containers/docker-compose.yml" -o docker-compose.yml
        
        setup_backup_scripts
        
        chown -R "$DOCKER_USER":"$DOCKER_USER" /srv/containers /srv/mediahub
        
        echo -e "${GREEN}✅ Docker контейнеры настроены (PUID=$PUID, PGID=$PGID)${NC}"
        
        if confirm_action "Запустить docker-compose сейчас?" "y"; then
            cd /srv/containers/compose
            if command -v docker-compose &>/dev/null; then
                docker-compose up -d
            else
                docker compose up -d
            fi
            echo -e "${GREEN}✅ Docker контейнеры запущены${NC}"
        fi
    fi
}

# Функция: Установка nginx
install_nginx() {
    if [ "$INSTALL_NGINX" = true ]; then
        log_message "Настройка nginx"
        
        mkdir -p /etc/nginx/ssl
        if [ ! -f /etc/nginx/ssl/selfsigned.crt ]; then
            openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                -keyout /etc/nginx/ssl/selfsigned.key \
                -out /etc/nginx/ssl/selfsigned.crt \
                -subj "/C=RU/ST=KLD/L=KLD/O=Home/OU=Dev/CN=raspberry-pi-5"
        fi

        CURRENT_IP=$(hostname -I | awk '{print $1}')
        echo -e "${GREEN}✅ IP Detected: $CURRENT_IP${NC}"

        cat > /etc/nginx/conf.d/homer-proxy.conf	 <<EOF
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ''      close;
}

server {
    listen 443 ssl;
    http2 on;
    server_name raspberry-pi-5 $CURRENT_IP;
    
    ssl_certificate     /etc/nginx/ssl/selfsigned.crt;
    ssl_certificate_key /etc/nginx/ssl/selfsigned.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers on;
    
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    
    proxy_http_version   1.1;
    proxy_set_header     Host              \$host;
    proxy_set_header     X-Real-IP         \$remote_addr;
    proxy_set_header     X-Forwarded-For   \$proxy_add_x_forwarded_for;
    proxy_set_header     X-Forwarded-Proto \$scheme;
    proxy_set_header     Upgrade           \$http_upgrade;
    proxy_set_header     Connection        \$connection_upgrade;

    add_header Access-Control-Allow-Origin  * always;

    # HOMER
    location / {
        proxy_pass http://$CURRENT_IP:8080/;
    }
    
    # PORTAINER (Installed separately)
    location /portainer/ {
        proxy_pass       https://$CURRENT_IP:9443/;
        proxy_ssl_verify off;
    }
    
    # SONARR
    location /sonarr/ {
        proxy_pass http://$CURRENT_IP:8989/sonarr/;
    }

    # QBITTORRENT
    location /qbittorrent/ {
        proxy_pass http://$CURRENT_IP:8068/;
        proxy_cookie_path / /qbittorrent/;
    }

    # JACKETT
    location /jackett/ {
        proxy_pass http://$CURRENT_IP:9117/jackett/;
    }

    # JELLYFIN
    location /jellyfin/ {
        proxy_pass http://$CURRENT_IP:8096/;
    } 
}

server {
    listen      80;
    server_name raspberry-pi-5 $CURRENT_IP;
    return      301 https://\$host\$request_uri;
}
EOF

        nginx -t && systemctl restart nginx && systemctl enable nginx
    fi
}

# Функция: Завершение установки
show_summary() {
    log_message "Установка завершена!"
    echo -e "${GREEN}=========================================${NC}"
    echo -e "${GREEN}           Сводка установки${NC}"
    echo -e "${GREEN}=========================================${NC}"
    echo -e "👤 Основной пользователь: $USERNAME"
    echo -e "👥 Создан новый: $CREATE_USER"
    echo -e "📟 LCD сервис: $INSTALL_LCD"
    echo -e "📦 Базовые пакеты: $INSTALL_PACKAGES"
    echo -e "⚙️  Конфиги системы: $SETUP_CONFIG"
    echo -e "🔧 .NET SDK: $INSTALL_DOTNET"
    echo -e "🎮 SteamCMD & Box64: $INSTALL_STEAMCMD"
    echo -e "🐳 Portainer: $INSTALL_PORTAINER"
    echo -e "📦 Контейнеры: $INSTALL_CONTAINERS"
    echo -e "🌐 nginx: $INSTALL_NGINX"
    echo -e "💾 Бэкап конфигов: $SETUP_BACKUP"
    if [ "$OS_TYPE" = "arch" ]; then
        echo -e "📦 AUR менеджер: $menager_name"
    fi
    echo -e "${GREEN}-----------------------------------------${NC}"
    
    # Информация о служебных пользователях
    if [ -n "$DOCKER_USER" ]; then
        local PUID=$(id -u "$DOCKER_USER" 2>/dev/null)
        local PGID=$(id -g "$DOCKER_USER" 2>/dev/null)
        echo -e "🐳 Пользователь Media/Docker: $DOCKER_USER (UID=$PUID, GID=$PGID)${NC}"
    fi
    if [ "$INSTALL_STEAMCMD" = true ]; then
        echo -e "🎮 Пользователь SteamCMD: $STEAM_USER${NC}"
    fi

    if [ "$INSTALL_PORTAINER" = true ]; then
        echo -e "${BLUE}📊 Portainer: https://localhost:9443${NC}"
    fi
    if [ "$INSTALL_NGINX" = true ]; then
        echo -e "${BLUE}🌐 nginx: http://localhost:80${NC}"
    fi
    if [ "$SETUP_BACKUP" = true ]; then
        echo -e "${BLUE}💾 Скрипты бэкапа: /srv/containers/backup/{push.sh,pull.sh}${NC}"
    fi
    if [ "$INSTALL_STEAMCMD" = true ]; then
        echo -e "${BLUE}🎮 Сервера: /srv/servers/steamcmd${NC}"
    fi
    
    echo -e "${YELLOW}⚠️  Рекомендуется перезагрузить систему!${NC}"
    echo -e "${YELLOW}🔄 Команда: reboot${NC}"
}

# Главная функция
main() {
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}    Raspberry Pi Homelab Installer${NC}"
    echo -e "${BLUE}=========================================${NC}"
    
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}❌ Запустите скрипт от root${NC}"
        exit 1
    fi
    
    detect_os
    
    ask_all_questions
    
    echo -e "${BLUE}-----------------------------------------${NC}"
    if ! confirm_action "Начать установку выбранных компонентов?" "y"; then
        echo -e "${YELLOW}⚠️  Установка отменена${NC}"
        exit 0
    fi
    
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}           Начало установки${NC}"
    echo -e "${BLUE}=========================================${NC}"
    
    add_service_users
    install_packages
    add_user
    setup_config
    setup_lcd
    install_dotnet
    install_portainer
    install_steam_env
    install_containers
    install_nginx
    
    show_summary
}

main "$@"
