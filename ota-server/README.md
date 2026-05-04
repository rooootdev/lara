# LARA OTA Server

OTA сервер для автоматической подписи и установки LARA через Safari.

## 🚀 Быстрый деплой

```bash
cd ota-server
chmod +x upload.sh
./upload.sh
```

Скрипт автоматически:
- Загрузит файлы на Oracle сервер (79.72.18.198)
- Установит все зависимости
- Настроит systemd service
- Установит Cloudflare Tunnel

## 📋 Что нужно после деплоя

### 1. Настроить подпись с Apple ID

На сервере:
```bash
ssh -i "/home/orkenlk/Загрузки/ssh-key-2026-04-29 (1).key" ubuntu@79.72.18.198
```

Скопировать сертификат и профиль:
```bash
sudo mkdir -p /root/.zsign
# Загрузить cert.p12 и profile.mobileprovision
```

### 2. Настроить Cloudflare Tunnel

```bash
# Логин в Cloudflare
cloudflared tunnel login

# Создать туннель
cloudflared tunnel create lara-ota

# Настроить DNS (замени на свой домен)
cloudflared tunnel route dns lara-ota lara.yourdomain.com

# Создать конфиг
sudo mkdir -p /etc/cloudflared
sudo nano /etc/cloudflared/config.yml
```

Содержимое config.yml:
```yaml
tunnel: <TUNNEL-ID>
credentials-file: /root/.cloudflared/<TUNNEL-ID>.json

ingress:
  - hostname: lara.yourdomain.com
    service: http://localhost:8080
  - service: http_status:404
```

Запустить туннель:
```bash
sudo cloudflared service install
sudo systemctl start cloudflared
sudo systemctl enable cloudflared
```

### 3. Проверить работу

```bash
# Статус OTA сервера
sudo systemctl status lara-ota

# Логи
sudo journalctl -u lara-ota -f

# Статус туннеля
sudo systemctl status cloudflared
```

## 🌐 Использование

После настройки:
1. Открой в Safari: `https://lara.yourdomain.com`
2. Нажми "Скачать и подписать LARA"
3. Дождись подписи (автоматически)
4. Нажми "Установить подписанную версию"
5. Подтверди установку в iOS

## 🔧 Компоненты

- **server.py** - Flask сервер с OTA установкой
- **deploy.sh** - Скрипт деплоя на сервер
- **upload.sh** - Загрузка файлов на Oracle
- **requirements.txt** - Python зависимости

## 📱 Как работает

1. Пользователь открывает сайт в Safari
2. Сервер скачивает IPA из GitHub Release
3. Подписывает через zsign с твоим Apple ID
4. Генерирует manifest.plist для OTA
5. iOS устанавливает через itms-services://

## ⚙️ Технологии

- Flask - веб-сервер
- zsign - подпись IPA
- Cloudflare Tunnel - HTTPS без сертификатов
- systemd - автозапуск
- gunicorn - production WSGI

## 🔐 Безопасность

- Сертификат хранится в /root/.zsign (только root)
- HTTPS через Cloudflare Tunnel
- Подписанные IPA удаляются после скачивания
- Логи не содержат credentials

## 📊 Мониторинг

```bash
# Проверить здоровье
curl http://localhost:8080/health

# Логи в реальном времени
sudo journalctl -u lara-ota -f

# Перезапустить сервис
sudo systemctl restart lara-ota
```
