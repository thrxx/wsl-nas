#!/usr/bin/env bash
# scripts/linux/02_setup_samba.sh
# Установка и настройка Samba для WSL2 NAS
# Совместимо с Ubuntu 22.04 / 24.04

set -euo pipefail

# 🎨 Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}[2/5] Installing & Configuring Samba...${NC}"

# 🔒 Проверка прав root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}✗ This script must be run with sudo.${NC}"
    exit 1
fi

# 🔍 Pre-flight checks
if ! grep -q "^systemd=true" /etc/wsl.conf 2>/dev/null; then
    echo -e "${YELLOW}⚠️ systemd not enabled in /etc/wsl.conf${NC}"
    echo -e "   Run 01_setup_wsl.sh and execute 'wsl --shutdown' first."
    exit 1
fi
if [[ ! -d "/data" ]]; then
    echo -e "${YELLOW}⚠️ /data directory not found. Creating it now...${NC}"
    mkdir -p /data
    chown "$(whoami):$(whoami)" /data
fi

# 📦 1. Установка пакетов
echo -e "${GREEN}   Installing Samba packages...${NC}"
apt update -qq
apt install -y samba samba-common-bin

# 📝 2. Резервное копирование и запись конфига
CONF="/etc/samba/smb.conf"
if [ -f "$CONF" ]; then
    cp "$CONF" "${CONF}.bak.$(date +%F)"
    echo -e "${GREEN}✓ Original smb.conf backed up${NC}"
fi

echo -e "${GREEN}   Writing optimized smb.conf...${NC}"
cat > "$CONF" << 'EOF'
[global]
   workgroup = WORKGROUP
   server string = WSL2-NAS
   dns proxy = no
   log file = /var/log/samba/log.%m
   max log size = 1000
   logging = file
   panic action = /usr/share/samba/panic-action %d

   server role = standalone server
   map to guest = never
   server min protocol = SMB2_10
   restrict anonymous = 2
   obey pam restrictions = yes
   unix password sync = yes
   passwd program = /usr/bin/passwd %u
   passwd chat = *Enter\snew\s*\spassword:* %n\n *Retype\snew\s*\spassword:* %n\n *password\supdated\ssuccessfully* .
   pam password change = yes

[data]
   comment = WSL NAS Primary Storage
   path = /data
   browseable = yes
   read only = no
   guest ok = no
   create mask = 0664
   directory mask = 0775
   force user = %S
   force group = %S
   veto files = /._*/.DS_Store/Thumbs.db/desktop.ini/
   delete veto files = yes
EOF

# ✅ 3. Валидация синтаксиса
if ! testparm -s "$CONF" > /dev/null 2>&1; then
    echo -e "${RED}✗ Invalid smb.conf! Restoring backup and aborting.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ smb.conf syntax valid${NC}"

# 🚀 4. Запуск сервисов
echo -e "${GREEN}   Enabling & starting Samba services...${NC}"
systemctl enable --now smbd nmbd
sleep 2

if systemctl is-active --quiet smbd; then
    echo -e "${GREEN}✓ smbd is active and listening${NC}"
else
    echo -e "${RED}✗ smbd failed to start. Check: journalctl -u smbd --no-pager -n 20${NC}"
    exit 1
fi

# 🔑 5. Настройка пользователя Samba
CURRENT_USER=$(whoami)
echo -e "${YELLOW}🔑 Setting Samba password for user: '$CURRENT_USER'${NC}"
echo -e "${YELLOW}   (This password is for NETWORK access only)${NC}"
smbpasswd -a "$CURRENT_USER"
echo -e "${GREEN}✓ Samba user '$CURRENT_USER' configured${NC}"

echo -e "${GREEN}✅ Samba setup complete.${NC}"
echo -e "${YELLOW}   Next step: Run Windows configuration script (03_configure_windows.ps1)${NC}"