#!/usr/bin/env bash
# scripts/linux/01_setup_wsl.sh
# Настройка базового окружения WSL2: systemd, автомонтирование, структура /data
# Совместимо с Ubuntu 22.04 / 24.04

set -euo pipefail

# 🎨 Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

WSL_CONF="/etc/wsl.conf"
DATA_DIR="/data"

echo -e "${GREEN}[1/5] Configuring WSL environment...${NC}"

# 🔒 Проверка прав root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}✗ This script must be run with sudo.${NC}"
    echo -e "   Usage: sudo bash scripts/linux/01_setup_wsl.sh"
    exit 1
fi

# ⚙️ 1. Настройка wsl.conf (идемпотентно)
if ! grep -q "^systemd=true" "$WSL_CONF" 2>/dev/null; then
    # Создаём файл, если его нет, и добавляем конфигурацию
    cat >> "$WSL_CONF" << 'EOF'
[boot]
systemd=true

[automount]
enabled = true
options = "metadata,umask=22,fmask=11"
root = /mnt/
EOF
    echo -e "${GREEN}✓ systemd and automount configured in $WSL_CONF${NC}"
else
    echo -e "${YELLOW}ℹ systemd is already enabled in $WSL_CONF${NC}"
fi

# 📁 2. Создание структуры каталогов
echo -e "${GREEN}   Creating data directories...${NC}"
mkdir -p "$DATA_DIR"/{media,docs,backups,shared}

CURRENT_USER=$(whoami)
# Устанавливаем владельца и базовые права
chown -R "$CURRENT_USER:$CURRENT_USER" "$DATA_DIR"
chmod 775 "$DATA_DIR"
chmod 775 "$DATA_DIR/shared"

echo -e "${GREEN}✓ Directories created & ownership set to '$CURRENT_USER'${NC}"

# 📝 3. Инструкции для пользователя
echo ""
echo -e "${YELLOW}⚠️  IMPORTANT NEXT STEP:${NC}"
echo -e "   Run the following command in Windows PowerShell to apply changes:"
echo -e "   ${GREEN}wsl --shutdown${NC}"
echo -e "   Then reopen your WSL terminal."
echo ""
echo -e "${GREEN}✅ WSL base configuration complete.${NC}"