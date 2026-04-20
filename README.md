# 🗄️ WSL2 Self-Hosted NAS

> ⚠️ **Дисклеймер:** Решение предназначено для домашнего использования, разработки и медиатеки. Оно **не заменяет** TrueNAS/OMV/Unraid, не имеет аппаратного RAID и засыпает вместе с Windows. Не храните критически важные данные без регулярных проверенных бэкапов.

[![MIT License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![CI Lint](https://github.com/thrxx/wsl-nas/actions/workflows/lint.yml/badge.svg)](https://github.com/thrxx/wsl-nas/actions/workflows/lint.yml)
[![Windows 10/11](https://img.shields.io/badge/OS-Windows%2010%2F11-blue)]()
[![Ubuntu](https://img.shields.io/badge/Distro-Ubuntu-orange)]()

Автоматизированный набор скриптов и конфигураций для превращения Windows с WSL2 в быстрый сетевой накопитель (SMB/CIFS) с автозапуском, пробросом портов и мониторингом.

---

## 🚀 Быстрый старт

### 1️⃣ Требования
- Windows 10 21H2+ / Windows 11 22H2+
- WSL2 с дистрибутивом `Ubuntu`
- PowerShell (от администратора) + терминал Linux
- SSD с ≥20% свободного места

### 2️⃣ Установка (строго в указанном порядке)
```bash
# 1. Клонируйте репозиторий и перейдите в Linux-часть
git clone https://github.com/thrxx/wsl-nas.git
cd wsl-nas/scripts/linux
sudo bash 01_setup_wsl.sh
```
⏸️ **Выполните в Windows PowerShell:** `wsl --shutdown` (обязательно для применения systemd)

```bash
# 2. Завершите настройку Linux (Samba)
cd wsl-nas/scripts/linux
sudo bash 02_setup_samba.sh
# Введите пароль для сетевого доступа при запросе
```

```powershell
# 3. Настройте Windows (PortProxy, Брандмауэр, Планировщик)
# Запускать в PowerShell ОТ АДМИНИСТРАТОРА
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
cd wsl-nas/scripts/windows
.\03_configure_windows.ps1

# Применить без перезагрузки:
Start-ScheduledTask -TaskName "WSL-NAS-Start"
Start-ScheduledTask -TaskName "WSL-NAS-PortProxy"
```

```bash
# 4. Проверка состояния
bash wsl-nas/scripts/linux/04_health_check.sh
```

### 3️⃣ Подключение
| Сценарий | Путь в проводнике |
|----------|-------------------|
| С этого ПК | `\\localhost\data` или `\\127.0.0.1\data` |
| Из LAN | `\\<IP_ВАШЕГО_ПК>\data` |
| Ручное управление | `\\wsl$\Ubuntu\data` (медленнее, только для администрирования) |

---

##  Архитектура: 4 уровня взаимодействия

```
┌─────────────────────────────────────────┐
│ 4. КЛИЕНТЫ (Win/macOS/TV/Phone)         │
│    • SMB://IP:445                       │
└────────────┬────────────────────────────┘
             │
┌─────────────────────────────────────────┐
│ 3. СЕТЕВОЙ СЛОЙ (Windows Host)          │
│    • vEthernet (WSL) / NAT              │
│    • Брандмауэр / PortProxy             │
└────────────┬────────────────────────────┘
             │
┌───────────────────────────────────────┐
│ 2. LINUX-СЛОЙ (WSL2 VM)               │
│    • systemd → smbd                   │
│    • ext4 внутри .vhdx                │
└──────────────────────────────────────┘
             │
┌─────────────────────────────────────────────────────────────┐
│ 1. ФИЗИЧЕСКОЕ ХРАНИЛИЩЕ (Windows Disk)                      │
│    • AppData\Local\Packages\...\ext4.vhdx                   │
└─────────────────────────────────────────────────────────────┘
```
📖 Подробно: [Архитектура и I/O Path](docs/architecture.md)

---

## 🔐 Аутентификация: 3 независимых контекста

| Контекст | Где хранится | Для чего используется |
|----------|--------------|------------------------|
| **Windows User** | SAM / AD | Вход в ОС, доступ к `\\wsl$` |
| **Linux User (WSL)** | `/etc/passwd` | Права на файлы в ext4, выполнение скриптов |
| **Samba User** | `passdb.tdb` | **Только** для подключения по SMB |

⛔ **Важно:** Пароли не синхронизируются. Сетевой пароль задаётся **только** через `sudo smbpasswd -a $USER`.

---

## 🌐 Сеть и доступ из LAN

- **Localhost:** Работает «из коробки» на Win11 22H2+ (`\\localhost\data`)
- **LAN:** Используется `netsh portproxy` + автоматическое обновление IP через Планировщик задач
- **Брандмауэр:** Правило создаётся **только для профиля `Private`**. Открытие 445 в публичных сетях запрещено.

📖 Подробно: [Настройка сети, PortProxy и Брандмауэра](docs/networking.md)

---

## 💾 Хранение данных и бэкапы

⛔ **Никогда не храните активные данные в `/mnt/c/`** (протокол 9P теряет 30–70% скорости и ломает права POSIX). Используйте нативный `/data` (ext4).

| Метод | Частота | Надёжность |
|-------|---------|------------|
| `rsync` инкрементальный | Ежедневно | ⭐⭐⭐⭐ |
| `restic` шифрованный | 2–3 раза/нед | ⭐⭐⭐⭐⭐ |
| Снапшот `.vhdx` | Перед изменениями | ⭐⭐⭐ |
| Cloud sync (`rclone`) | Еженедельно | ⭐⭐⭐ |

📖 Подробно: [Стратегии бэкапа и обслуживание VHDX](docs/backup.md)

---

## 🚦 Устранение неполадок

| Симптом | Решение |
|---------|---------|
| `Failed to start smbd.service` | Проверьте `/etc/wsl.conf`, выполните `wsl --shutdown` |
| `Permission denied` при записи | Убедитесь, что `force user = %S` в `smb.conf` и права на `/data` верны |
| Сервер не виден в LAN | Запустите `Update-WSLPortProxy.ps1` вручную, проверьте правило брандмауэра `Private` |
| Медленная запись мелких файлов | Переместите данные из `/mnt/c/` в `/data` (ext4) |
| IP WSL меняется после ребута | Задача `WSL-NAS-PortProxy` обновляет `portproxy` автоматически при входе |

---

## 📦 Структура репозитория
```
wsl-nas/
├── docs/           # Подробные гайды (Архитектура, Сеть, Безопасность, Бэкапы)
├── scripts/        # Идемпотентные скрипты настройки
│   ├── linux/      # 01_setup_wsl.sh → 05_setup_backup.sh
│   └── windows/    # 03_configure_windows.ps1, Update-WSLPortProxy.ps1
├── config/         # Эталонные smb.conf и wsl.conf
├── .github/        # CI/CD, Issue-шаблоны
└── README.md       # Вы здесь
```

---

## ✅ Чек-лист безопасности
- [ ] `guest ok = no` и `map to guest = never` активны
- [ ] `server min protocol = SMB2_10` (SMBv1 отключён)
- [ ] Брандмауэр разрешает 445 только для `Private`
- [ ] Пароли Samba заданы через `smbpasswd`, не совпадают с системными
- [ ] Данные хранятся в `/data`, а не в `/mnt/c/` или `\\wsl$`
- [ ] Нет проброса порта 445 на внешний IP роутера
- [ ] Настроен минимум 1 инкрементальный бэкап с тестовым восстановлением

---

## 🤝 Contributing
1. Форкните репозиторий
2. Создайте ветку `feature/ваше-улучшение`
3. Убедитесь, что скрипты проходят `ShellCheck` / `PSScriptAnalyzer`
4. Откройте Pull Request

## 📄 Лицензия
MIT. См. [LICENSE](LICENSE).

---
💡 **Совет:** Для стабильного IP в LAN без PortProxy рекомендуется использовать `wsl-vpnkit` или `macvlan`. Подробности в [docs/networking.md](docs/networking.md).