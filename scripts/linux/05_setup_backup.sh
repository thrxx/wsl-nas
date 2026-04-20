#!/usr/bin/env bash
# scripts/linux/05_setup_backup.sh
# Настройка автоматического инкрементального бэкапа через rsync + cron
# Совместимо с Ubuntu 22.04 / 24.04

set -euo pipefail

# 🎨 Цвета
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}[5/5] Setting up automated backup (rsync)...${NC}"

# 🔒 Проверка прав root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}✗ This script must be run with sudo.${NC}"
    exit 1
fi

# 📍 Пункт назначения бэкапа (по умолчанию внешний/второй диск)
BACKUP_DEST="${1:-/mnt/d/nas-backup}"

# ✅ Валидация и создание каталога
if [[ ! -d "$BACKUP_DEST" ]]; then
    echo -e "${YELLOW}⚠️ Creating backup destination: $BACKUP_DEST${NC}"
    mkdir -p "$BACKUP_DEST" || { echo -e "${RED}✗ Failed to create $BACKUP_DEST. Check mount & permissions.${NC}"; exit 1; }
fi

# 📦 Установка rsync (если отсутствует)
if ! command -v rsync &> /dev/null; then
    echo -e "${GREEN}   Installing rsync...${NC}"
    apt-get update -qq && apt-get install -y rsync
else
    echo -e "${GREEN}✓ rsync already installed${NC}"
fi

# 📝 Генерация скрипта бэкапа
BACKUP_SCRIPT="/usr/local/bin/nas-backup.sh"
echo -e "${GREEN}   Creating backup script at $BACKUP_SCRIPT...${NC}"

# Используем heredoc без кавычек вокруг EOF, но экранируем переменные, 
# чтобы они записались в файл literally, а не раскрылись сейчас.
cat > "$BACKUP_SCRIPT" << EOF
#!/usr/bin/env bash
set -euo pipefail
DEST="${BACKUP_DEST}"
LOG="/var/log/nas-backup.log"

echo "[\$(date '+%Y-%m-%d %H:%M:%S')] 🚀 Starting rsync backup..." >> "\$LOG"
rsync -avh --delete --info=progress2 /data/ "\$DEST/" >> "\$LOG" 2>&1
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] ✅ Backup finished." >> "\$LOG"
EOF

chmod +x "$BACKUP_SCRIPT"
echo -e "${GREEN}✓ Backup script created & made executable${NC}"

# 📅 Настройка cron (идемпотентно, безопасно для set -e)
CRON_JOB="0 2 * * * $BACKUP_SCRIPT"
CURRENT_CRON=$(crontab -l 2>/dev/null || true)

if echo "$CURRENT_CRON" | grep -qF "nas-backup.sh" 2>/dev/null; then
    echo -e "${YELLOW}ℹ Cron job already exists for $BACKUP_SCRIPT${NC}"
else
    echo "$CURRENT_CRON" | { cat; echo "$CRON_JOB"; } | crontab -
    echo -e "${GREEN}✅ Cron job added (daily at 02:00)${NC}"
fi

echo -e "\n${YELLOW}⚠️  IMPORTANT:${NC}"
echo -e "   1. Ensure '$BACKUP_DEST' points to a persistent Windows drive (e.g., /mnt/d/ or /mnt/e/)"
echo -e "   2. Verify mount: ${GREEN}ls -ld $BACKUP_DEST${NC}"
echo -e "   3. Test manually: ${GREEN}sudo bash $BACKUP_SCRIPT${NC}"
echo -e "   4. View logs: ${GREEN}tail -f /var/log/nas-backup.log${NC}"
echo -e "\n${GREEN}✅ Backup automation setup complete.${NC}"