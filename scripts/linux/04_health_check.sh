#!/usr/bin/env bash
# scripts/linux/04_health_check.sh
# Диагностика состояния WSL2 NAS: сервисы, сеть, конфиги, хранилище
# Совместимо с Ubuntu 22.04 / 24.04

set -euo pipefail

# 🎨 Цвета
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

echo -e "${GREEN}[4/5] Running WSL-NAS Health Check...${NC}"
echo "-------------------------------------------"

# 🔍 Функция проверки (безопасна для set -e)
run_check() {
    local cmd="$1"
    local pass_msg="$2"
    local fail_msg="$3"
    
    if eval "$cmd" >/dev/null 2>&1; then
        echo -e "  ${GREEN}✅ ${pass_msg}${NC}"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}❌ ${fail_msg}${NC}"
        FAIL=$((FAIL + 1))
    fi
}

# 🧪 Проверки
run_check "systemctl is-active --quiet smbd" \
    "SMB service (smbd) is active" \
    "SMB service is NOT running"

run_check "systemctl is-active --quiet nmbd" \
    "NetBIOS service (nmbd) is active" \
    "NetBIOS service is NOT running"

run_check "test -d /data" \
    "/data directory exists" \
    "/data directory is MISSING"

run_check "grep -q '^systemd=true' /etc/wsl.conf 2>/dev/null" \
    "systemd enabled in /etc/wsl.conf" \
    "systemd NOT configured in wsl.conf"

run_check "ss -tlnp 2>/dev/null | grep -q ':445 '" \
    "Port 445 is listening" \
    "Port 445 is NOT listening"

run_check "testparm -s /etc/samba/smb.conf >/dev/null 2>&1" \
    "Samba config syntax is valid" \
    "Samba config is INVALID"

run_check "df /data 2>/dev/null | awk 'NR==2{gsub(/%/,\"\",\$5); exit (\$5>=95)?1:0}'" \
    "Free disk space ≥ 5%" \
    "Disk usage ≥ 95% (CRITICAL)"

echo "-------------------------------------------"
echo -e "${YELLOW}Results: ${GREEN}$PASS passed${YELLOW}, ${RED}$FAIL failed${NC}"

if [[ $FAIL -gt 0 ]]; then
    echo -e "\n${RED}⚠️  Fix the issues above before using the NAS.${NC}"
    echo -e "   Useful commands:"
    echo -e "   ${YELLOW}journalctl -u smbd -n 20${NC}"
    echo -e "   ${YELLOW}systemctl status smbd nmbd${NC}"
    echo -e "   ${YELLOW}testparm -s /etc/samba/smb.conf${NC}"
    exit 1
fi

echo -e "\n${GREEN}🎉 All systems operational.${NC}"
exit 0