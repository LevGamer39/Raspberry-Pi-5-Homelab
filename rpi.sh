#!/bin/bash

lcd_services=false
USERNAME=""
PASSWORD=""

# Функция: Вопросы
questions(){
    echo "Включить LCD сервис"
    echo "1. Да"
    echo "2. Нет"
    read -p "Введите 1 или 2 (по умолчанию будет выключен): " lcd_choice

    if [ "$lcd_choice" = "1" ]; then
        lcd_services=true
    elif [ "$lcd_choice" = "2" ]; then
        lcd_services=false
    else
        echo "Некорректный ввод. По умолчанию будет выключен."
        lcd_services=false
    fi
    
    echo "Выберите пакетный менеджер:"
    echo "1. Yay"
    echo "2. Paru"
    read -p "Введите 1 или 2 (по умолчанию будет yay): " menager_choice

    if [ "$menager_choice" = "1" ]; then
        menager_name="yay"
    elif [ "$menager_choice" = "2" ]; then
        menager_name="paru"
    else
        echo "Некорректный ввод. По умолчанию будет установлен Yay."
        menager_name="yay"
    fi
    
    echo "Изменить имя пользователя"
    echo "1. Да"
    echo "2. Нет"
    read -p "Введите 1 или 2 (по умолчанию будет 'user'): " name_choice

    if [ "$name_choice" = "1" ]; then
        while true; do
            read -p "Введите имя пользователя: " USERNAME
            if [[ "$USERNAME" =~ ^[A-Za-z0-9._-]+$ ]]; then
                break
            else
                echo "❌ Ошибка: допустимы только A–Z, a–z, 0–9, . _ -"
            fi
        done
    elif [ "$name_choice" = "2" ]; then
        USERNAME="user"
    else
        echo "Некорректный ввод. По умолчанию будет имя 'user'."
        USERNAME="user"
    fi
    
    echo "Изменить пароль пользователя"
    echo "1. Да"
    echo "2. Нет"
    read -p "Введите 1 или 2 (по умолчанию будет запрошен позже): " password_choice

    if [ "$password_choice" = "1" ]; then
        while true; do
            read -s -p "Введите пароль: " PASSWORD
            echo
            if [ ${#PASSWORD} -ge 5 ]; then
                break
            else
                echo "❌ Пароль должен быть не короче 5 символов"
            fi
        done
    elif [ "$password_choice" = "2" ]; then
        PASSWORD=""
    else
        echo "Некорректный ввод. Пароль будет запрошен позже."
        PASSWORD=""
    fi
}

# Функция: Установка базовых пакетов 
install_packages(){
    pacman -Syu --noconfirm docker git python python-pip flashrom i2c-tools sudo nginx rsync base-devel docker-compose
    systemctl start docker
    systemctl enable docker
    if [ "$menager_name" = "yay" ]; then
        git clone https://aur.archlinux.org/yay.git
        cd yay
        makepkg -si --noconfirm
        cd ..
    elif [ "$menager_name" = "paru" ]; then
        git clone https://aur.archlinux.org/paru.git
        cd paru
        makepkg -si --noconfirm
        cd ..
    fi
    cd ~
}

# Функция: Установка конфигов
setup_config(){
    cd /boot/
    mv config.txt config.txt.back
    curl -sL "https://raw.githubusercontent.com/LevGamer39/Raspberry-Pi-5-Homelab/main/Config/config.txt" -o config.txt
    cd /etc/
    rm -rf sudoers
    curl -sL "https://raw.githubusercontent.com/LevGamer39/Raspberry-Pi-5-Homelab/main/Config/sudoers" -o sudoers
    timedatectl set-timezone Europe/Kaliningrad
    hwclock -s
    
    sudo -u "$USERNAME" git config --global user.name "YourName"
    sudo -u "$USERNAME" git config --global user.email "your@email.com"

    # Установка русской локали и UTF-8 символов
    sed -i 's/^#\(ru_RU.UTF-8 UTF-8\)/\1/' /etc/locale.gen
    locale-gen
    echo "LANG=ru_RU.UTF-8" > /etc/locale.conf
    export LANG=ru_RU.UTF-8
    export LC_ALL=ru_RU.UTF-8
    cd ~
}

# Функция: Создание пользователя 
add_user(){
    if ! id "$USERNAME" &>/dev/null; then
        useradd -m "$USERNAME"
    fi
    if [ -n "$PASSWORD" ]; then
        echo "$USERNAME:$PASSWORD" | chpasswd
    else
        passwd "$USERNAME"
    fi
    usermod -aG wheel "$USERNAME"
}

# Функция: Установка LCD
setup_lcd(){
    mkdir -p /opt/lcdmonitor/
    cd /opt/lcdmonitor/
    curl -sL "https://raw.githubusercontent.com/LevGamer39/LCD-Monitor/main/LCD/shutdown_lcd.py" -o shutdown_lcd.py
    curl -sL "https://raw.githubusercontent.com/LevGamer39/LCD-Monitor/main/LCD/lcd_monitor.py" -o lcd_monitor.py
    curl -sL "https://raw.githubusercontent.com/LevGamer39/LCD-Monitor/main/LCD/requirements.txt" -o requirements.txt
    pip install -r requirements.txt --break-system-packages
    cd /etc/systemd/system/
    curl -sL "https://raw.githubusercontent.com/LevGamer39/LCD-Monitor/main/LCD/lcd-shutdown.service" -o lcd-shutdown.service
    curl -sL "https://raw.githubusercontent.com/LevGamer39/LCD-Monitor/main/LCD/lcd-reboot.service" -o lcd-reboot.service
    curl -sL "https://raw.githubusercontent.com/LevGamer39/LCD-Monitor/main/LCD/lcdmonitor.service" -o lcdmonitor.service

    systemctl daemon-reload

    if [ "$lcd_services" = true ] ; then
        systemctl enable lcd-shutdown.service
        systemctl enable lcd-reboot.service
        systemctl enable lcdmonitor.service
    fi
    cd ~
}

# Функция: Установка dotnet
install_dotnet(){
    cd ~
    curl -L https://dot.net/v1/dotnet-install.sh -o dotnet-install.sh
    chmod +x ./dotnet-install.sh
    ./dotnet-install.sh --version latest
    export DOTNET_ROOT=$HOME/.dotnet
    export PATH=$PATH:$DOTNET_ROOT:$DOTNET_ROOT/tools
    cd ~
}

# Функция: Установка portainer
install_portainer(){
    docker volume create portainer_data
    docker run -d -p 8000:8000 -p 9443:9443 --name portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:latest
}

# Функция: Установка контейнеров
install_containers(){
    mkdir -p /srv/containers/{backup,compose,configs,backup/backup_repo}
    mkdir -p /srv/mediahub/{downloads,media,media/films}
    cd /srv/containers/backup
    curl -sL "https://raw.githubusercontent.com/LevGamer39/Raspberry-Pi-5-Homelab/main/Scripts/pull.sh" -o pull.sh
    curl -sL "https://raw.githubusercontent.com/LevGamer39/Raspberry-Pi-5-Homelab/main/Scripts/push.sh" -o push.sh
    chmod +x ./push.sh ./pull.sh
    cd /srv/containers/compose
    curl -sL "https://raw.githubusercontent.com/LevGamer39/Raspberry-Pi-5-Homelab/main/Scripts/push.sh" -o push.sh
    if command -v docker-compose &>/dev/null; then
        docker-compose up -d
    else
        docker compose up -d
    fi
}

# Функция: Установка nginx
install_nginx(){
    mkdir -p /etc/nginx/ssl
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/nginx/ssl/selfsigned.key \
        -out /etc/nginx/ssl/selfsigned.crt \
        -subj "/C=RU/ST=Kaliningrad/L=Kaliningrad/O=LevGamer39/OU=Dev/CN=raspberry-pi-5"
}

if [ "$EUID" -ne 0 ]; then
    echo "Запусти скрипт от root"
    exit 1
fi

questions
install_packages
setup_config
add_user
setup_lcd
install_dotnet
install_portainer
install_containers
install_nginx
