# 🚦 Устранение неполадок

> 💡 **Перед созданием Issue** обязательно запустите встроенную диагностику:
> ```bash
> bash scripts/linux/04_health_check.sh
> ```
> Прикрепите вывод к сообщению об ошибке. Это ускорит решение проблемы на 80%.

---

## 🔌 1. Сетевые проблемы

| Симптом | Возможная причина | Решение |
|---------|-------------------|---------|
| **Сервер не виден в LAN** | Брандмауэр блокирует порт 445 или `portproxy` не обновлён | 1. `Test-NetConnection <IP_ХОСТА> -Port 445`<br>2. Запустите `Update-WSLPortProxy.ps1` вручную<br>3. Проверьте правило: `Get-NetFirewallRule -DisplayName "WSL-NAS-SMB"` |
| **IP WSL меняется после перезагрузки** | Динамическая аренда DHCP в виртуальной сети Hyper-V | Задача `WSL-NAS-PortProxy` в Планировщике автоматически обновляет проброс при входе. Убедитесь, что она активна и имеет триггер `AtLogOn` с задержкой 60 сек. |
| **`\\localhost\data` не работает** | Устаревшая версия Windows или WSL не слушает порт 445 | Требуется Windows 11 22H2+ или Win10 22H2+. Проверьте: `ss -tlnp \| grep ':445'` внутри WSL. Если порт не открыт, перезапустите `smbd`. |
| **Подключение есть, но нет доступа к шарам** | Сетевой профиль Windows установлен как `Public` | Откройте `Параметры → Сеть и Интернет → Ethernet/Wi-Fi` → измените профиль на `Частная сеть`. SMB блокируется в публичных сетях по умолчанию. |

---

## 🔐 2. Аутентификация и права доступа

| Симптом | Возможная причина | Решение |
|---------|-------------------|---------|
| **`Permission denied` при записи** | Права на `/data` не совпадают с UID пользователя Samba | 1. `sudo chown -R $USER:$USER /data`<br>2. Убедитесь, что в `smb.conf` есть `force user = %S`<br>3. Не изменяйте права через Проводник Windows (`\\wsl$`) |
| **`NT_STATUS_LOGON_FAILURE`** | Введён пароль Windows или Linux вместо пароля Samba | Samba использует отдельную БД. Задайте пароль явно: `sudo smbpasswd -a $USER`. Пароль может отличаться от системного. |
| **Файлы создаются от имени `root`** | Отсутствует маппинг пользователя в конфиге | Добавьте в секцию `[data]`:<br>`force user = %S`<br>`force group = %S`<br>Перезапустите: `sudo systemctl restart smbd` |
| **Запрос пароля появляется бесконечно** | Кэширование учётных данных Windows конфликтует с Samba | Очистите кэш: `cmdkey /delete:target=<IP_ИЛИ_HOSTNAME>` или подключитесь с флагом `/persistent:no`. |

---

## ⚙️ 3. Запуск сервисов и системные ошибки

| Симптом | Возможная причина | Решение |
|---------|-------------------|---------|
| **`Failed to start smbd.service`** / `Failed to connect to bus` | `systemd` не включён в `/etc/wsl.conf` | 1. Проверьте наличие `systemd=true` в `/etc/wsl.conf`<br>2. Выполните `wsl --shutdown` в PowerShell<br>3. Откройте WSL заново и проверьте: `systemctl is-system-running` |
| **Порт 445 занят другой службой** | Конфликт с встроенным SMB-сервером Windows | Отключите `SMB 1.0/CIFS File Sharing Support` и службу `Server` в `appwiz.cpl → Включение компонентов Windows`. Перезагрузитесь. |
| **WSL не запускается автоматически** | Ошибка в Планировщике задач или отсутствие прав | Проверьте задачу `WSL-NAS-Start`: должна иметь `RunLevel Highest`, триггер `AtLogOn`, действие `wsl -d Ubuntu -e true`. Запустите вручную: `Start-ScheduledTask -TaskName "WSL-NAS-Start"` |

---

## 🐌 4. Производительность и хранение

| Симптом | Возможная причина | Решение |
|---------|-------------------|---------|
| **Медленная запись/чтение мелких файлов** | Данные хранятся в `/mnt/c/` (протокол 9P) | Протокол 9P теряет 30–70% скорости. Переместите данные в нативный том: `mv /mnt/c/nas_data/* /data/`. Подключайтесь только по `\\localhost` или `\\IP`. |
| **Виртуальный диск `.vhdx` разросся и не уменьшается** | Динамический VHDX не сжимается автоматически при удалении файлов | 1. `wsl --shutdown`<br>2. PowerShell (Admin): `wsl --manage Ubuntu --compact`<br>3. Альтернатива: `Optimize-VHD -Path "<путь_к_vhdx>" -Mode Full` |
| **Высокая нагрузка на CPU при копировании** | Антивирус/Defender сканирует каждый файл в реальном времени | Добавьте исключения в Windows Security: папку `C:\Users\%USERNAME%\AppData\Local\Packages\...\LocalState\` и процесс `wslservice.exe`. |

---

## 📝 5. Ошибки конфигурации и пакетов

| Симптом | Возможная причина | Решение |
|---------|-------------------|---------|
| **`smbpasswd: command not found`** | Не установлен пакет утилит Samba | `sudo apt update && sudo apt install samba-common-bin` |
| **`testparm` выдаёт ошибки синтаксиса** | Опечатка в `smb.conf` или некорректный heredoc | Сравните с эталоном `config/smb.conf`. Исправьте, затем проверьте: `testparm -s /etc/samba/smb.conf` |
| **Логи Samba пусты или не ротируются** | Отключён `logrotate` или неверный путь | Проверьте: `ls -lh /var/log/samba/`. Убедитесь, что в `smb.conf` указано `log file = /var/log/samba/log.%m` |

---

## 🛠️ Набор команд для ручной диагностики

Скопируйте и выполните в соответствующей среде для сбора полной картины:

### 🐧 Внутри WSL (Linux)
```bash
# Статус сервисов
systemctl status smbd nmbd --no-pager -l

# Последние 50 строк логов smbd
journalctl -u smbd --no-pager -n 50

# Валидация конфига
testparm -s /etc/samba/smb.conf

# Слушаемые порты
ss -tlnp | grep ':445'

# Текущий IP дистрибутива
hostname -I
```

### 🪟 В Windows PowerShell (Admin)
```powershell
# Проверка проброса портов
netsh interface portproxy show v4tov4

# Тест доступности порта с клиента
Test-NetConnection -ComputerName localhost -Port 445

# Статус правила брандмауэра
Get-NetFirewallRule -DisplayName "WSL-NAS-SMB" | Select-Object DisplayName, Enabled, Profile, Action

# Принудительный запуск фоновой VM
wsl -d Ubuntu -e true
```

---

## ✅ Чек-лист перед обращением в поддержку
- [ ] Запущен `04_health_check.sh` и приложены результаты
- [ ] Проверено, что данные лежат в `/data`, а не в `/mnt/c/`
- [ ] В `/etc/wsl.conf` прописано `systemd=true` и выполнен `wsl --shutdown`
- [ ] Пароль задан через `sudo smbpasswd -a`, а не через Windows/Linux
- [ ] Брандмауэр разрешает TCP 445 только для профиля `Private`
- [ ] Задача `WSL-NAS-PortProxy` активна в Планировщике

---

## 📚 Связанные документы
- 🏗️ [Архитектура и потоки данных](architecture.md)
- 🌐 [Настройка сети и проброс портов](networking.md)
- 🔒 [Безопасность и управление правами](security.md)
- 💾 [Бэкапы и обслуживание VHDX](backup.md)

---
📝 *Документ обновлён: 2026-04-21 | Совместимо с WSL2 + Ubuntu 22.04/24.04 + Samba 4.15+*