# 🌐 Сетевая настройка: PortProxy, Брандмауэр и доступ из LAN

> ⚠️ **Критическое предупреждение:** SMB/CIFS (порт 445) **категорически не предназначен** для прямого доступа из интернета. Протокол не имеет встроенного шифрования, подвержен эксплуатации уязвимостей (EternalBlue и др.) и раскрывает структуру файловой системы. Доступ должен быть ограничен локальной сетью, VPN или решениями типа Tailscale/Cloudflare Tunnel.

## 📐 Архитектурный контекст (Уровень 3)
WSL2 работает в изолированной подсети Hyper-V (`172.16.0.0/12`), получая динамический IP через внутренний DHCP. Физический сетевой адаптер ПК видит WSL только как виртуальный интерфейс `vEthernet (WSL)`. Прямой доступ из LAN невозможен без трансляции портов на стороне Windows-хоста.

```
[Клиент в LAN] → 192.168.1.x:445 (Хост Windows)
                      ↓
              netsh portproxy / localhost-forwarding
                      ↓
              vEthernet (WSL) NAT
                      ↓
           [WSL2 VM] 172.x.x.x:445 → smbd
```

---

## 🔌 Сценарии подключения

### ✅ Вариант А: Доступ с этого ПК (`localhost`)
**Требования:** Windows 11 22H2+ или обновлённая Win10 22H2+  
**Как работает:** Windows автоматически проксирует `127.0.0.1:445` в WSL2, если служба слушает порт внутри Linux.
```powershell
# Подключение
\\localhost\data
# или
\\127.0.0.1\data
```
- **Плюсы:** Работает «из коробки», не требует прав администратора, не зависит от DHCP.
- **Минусы:** Доступен **только с хоста**. Устройства в LAN не увидят сервер.

### ✅ Вариант Б: Доступ из локальной сети (LAN)
**Требования:** PowerShell (Admin), `netsh`, правило брандмауэра  
**Как работает:** Windows выступает как статический транслятор портов.
```powershell
netsh interface portproxy add v4tov4 `
  listenport=445 listenaddress=0.0.0.0 `
  connectport=445 connectaddress=<WSL_IP>
```
```
Другой ПК → 192.168.1.10:445 (Хост) → portproxy → 172.x.x.x:445 (WSL) → smbd
```
- **Плюсы:** Полноценный доступ из LAN для всех устройств (Windows, macOS, TV, Linux).
- **Минусы:** Требует админ-прав, IP WSL меняется при перезагрузке → нужен автоматический скрипт обновления.

---

## 🛡️ Настройка Брандмауэра Windows (Обязательно!)
По умолчанию Windows блокирует входящие SMB-соединения. Разрешите порт **только для профиля `Private`**.

```powershell
# Выполнить в PowerShell (от администратора)
New-NetFirewallRule -DisplayName "WSL-NAS-SMB" `
  -Direction Inbound -Protocol TCP -LocalPort 445 `
  -Action Allow -Profile Private
```
🔍 **Проверка:** `Get-NetFirewallRule -DisplayName "WSL-NAS-SMB" | Select-Object DisplayName, Profile, Action`

⛔ **Никогда не используйте:** `-Profile Public` или `-Profile Any`. Это открывает SMB для всех сетей, включая кафе/аэропорты.

---

## 🔄 Автоматизация обновления IP (PortProxy)
IP WSL2 меняется при каждом `wsl --shutdown` или перезагрузке ПК. Скрипт ниже автоматически находит текущий IP и обновляет `portproxy`.

### 📜 `Update-WSLPortProxy.ps1`
```powershell
#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
$WSL_DISTRO = "Ubuntu"
$PORT = 445

# Получаем IP WSL (первый из списка)
$WSL_IP = (wsl -d $WSL_DISTRO -e hostname -I 2>$null).Trim().Split(" ")[0]

if (-not $WSL_IP -or $WSL_IP -eq "") {
    Write-Warning "❌ WSL не запущен или не получил IP. Пропуск обновления."
    exit 1
}

# Удаляем старое правило (если есть)
netsh interface portproxy delete v4tov4 listenport=$PORT listenaddress=0.0.0.0 2>$null

# Создаём новое
netsh interface portproxy add v4tov4 listenport=$PORT listenaddress=0.0.0.0 connectport=$PORT connectaddress=$WSL_IP

Write-Host "✅ PortProxy обновлён: 0.0.0.0:$PORT -> $WSL_IP:$PORT" -ForegroundColor Green
```

### 📅 Интеграция в Планировщик задач
```powershell
# Создаём задачу, которая запускается при входе в систему с задержкой 60 сек
$TaskName = "WSL-NAS-PortProxy"
$Action = New-ScheduledTaskAction -Execute "powershell.exe" `
  -Argument "-ExecutionPolicy Bypass -File `"C:\ProgramData\WSL-NAS\Update-WSLPortProxy.ps1`""
$Trigger = New-ScheduledTaskTrigger -AtLogOn -Delay (New-TimeSpan -Seconds 60)
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger `
  -Settings $Settings -RunLevel Highest -Force
```
💡 **Почему задержка 60 сек?** Сети Hyper-V и маршрутизация WSL инициализируются после входа пользователя. Ранний запуск приведёт к `exit 1` и отсутствию доступа.

---

## 🌐 Альтернативные методы (для продвинутых)

| Метод | Когда использовать | Настройка |
|-------|-------------------|-----------|
| **`wsl-vpnkit`** | Нужен стабильный `192.168.1.x` без portproxy | Заменяет виртуальный адаптер, даёт WSL прямой доступ к LAN |
| **Hyper-V `macvlan`** | Изоляция сети, фиксированный IP | Создаётся виртуальный коммутатор, WSL получает MAC-адрес как отдельное устройство |
| **Tailscale / ZeroTier** | Удалённый доступ из интернета без проброса портов | Устанавливается в WSL и на клиент. Доступ по `tailscale-ip:445` через Wireguard |
| **Cloudflare Tunnel** | Корпоративный доступ без открытия портов | `cloudflared` проксирует SMB через защищённый туннель (требует домена) |

---

## 🚦 Устранение неполадок

| Симптом | Диагностика | Решение |
|---------|-------------|---------|
| `\\IP\data` не доступен из LAN | `Test-NetConnection <IP_ХОСТА> -Port 445` | Проверьте правило брандмауэра (`-Profile Private`), запустите `Update-WSLPortProxy.ps1` вручную |
| `Access denied` при подключении | `smbclient -L //localhost -U %USER%` | Убедитесь, что пароль задан через `smbpasswd -a`, а не системный Linux/Windows |
| WSL IP меняется каждый день | `wsl -d Ubuntu -e hostname -I` | Скрипт PortProxy + Task Scheduler решает проблему автоматически |
| PortProxy не работает после сна ПК | `netsh interface portproxy show v4tov4` | WSL может "заснуть". Добавьте задачу `wsl -d Ubuntu -e true` в Планировщик при возобновлении работы |
| Медленный отклик при подключении | `ping <WSL_IP> -t` | Проверьте, не блокирует ли антивирус SMB-трафик. Отключите `SMB Multichannel` в реестре, если используется 1 Gbps сеть |

---

## ✅ Сетевой чек-лист безопасности
- [ ] Порт 445 открыт **только** в профиле `Private`
- [ ] `netsh portproxy` обновляется автоматически при входе в систему
- [ ] Нет правил маршрутизации, пробрасывающих 445 на внешний интерфейс роутера
- [ ] Для удалённого доступа используется VPN/Tailscale, а не проброс портов
- [ ] В `smb.conf` указано `server min protocol = SMB2_10` (отключён SMBv1)
- [ ] `generateResolvConf = true` в `/etc/wsl.conf` (корректное DNS-разрешение внутри WSL)

---

## 📚 Связанные документы
- 🏗️ [Архитектура и потоки данных](architecture.md)
- 🔒 [Безопасность, права и аутентификация](security.md)
- 💾 [Стратегии бэкапа и обслуживание](backup.md)
- 🚦 [Общие проблемы и диагностика](../README.md#🛠️-устранение-проблем)

---
📝 *Документ обновлён: 2026-04-21 | Совместимо с WSL2 + Windows 10 21H2+ / Win11 22H2+ | Samba 4.15+*