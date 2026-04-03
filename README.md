# MTProto Proxy Installer

One-script automated MTProto proxy setup for Telegram using [mtg](https://github.com/9seconds/mtg) (Docker).

Автоматическая установка MTProto прокси для Telegram одним скриптом. Два режима: Fake-TLS и Real-TLS (nginx + Let's Encrypt).

---

> **Не хотите разбираться с консолью?** Есть Telegram-бот, который полностью установит и настроит MTProto прокси на вашем сервере — без SSH, без команд, всё через бот. Ссылку на бота можно получить у автора: [@arblark](https://t.me/arblark)
>
> **Вопросы, помощь, предложения** — пишите в Telegram: [@arblark](https://t.me/arblark)

---

## Features / Возможности

- **Two TLS modes** — Fake-TLS (стандартный) или Real-TLS (nginx + Let's Encrypt + реальный домен)
- **One command** — установка за одну команду на любом свежем VDS/VPS
- **Interactive** — интерактивный выбор режима, порта, DNS, домена с дефолтами
- **Auto mode** — неинтерактивный режим для автоматизации (`--auto`)
- **Real-TLS** — настоящий сертификат, nginx как фронтенд, сайт-заглушка при прямом заходе
- **Auto-detect IP** — автоопределение внешнего IP сервера
- **Port check** — проверка занятости порта перед запуском
- **Domain validation** — проверка DNS: домен -> IP сервера (Real-TLS) или резолв (Fake-TLS)
- **Connection verify** — проверка доступности прокси после старта
- **QR code** — QR-код ссылки прямо в терминале (навёл камеру — подключился)
- **Docker** — всё работает в контейнере с `--restart always`
- **Firewall support** — автоматическое открытие порта (UFW + firewalld)
- **Ready-to-use links** — на выходе готовые `https://t.me/proxy` и `tg://proxy` ссылки
- **Secret persistence** — секрет сохраняется между запусками, клиентские ссылки не ломаются
- **Update & Uninstall** — встроенные команды обновления и удаления
- **Status & Doctor** — статус, диагностика mtg + nginx + сертификат
- **Multi-distro** — поддержка Debian, Ubuntu, CentOS, Fedora и других

## TLS Modes / Режимы TLS

### Fake-TLS (стандартный)

Прокси маскируется под HTTPS-соединение к указанному домену (например, apple.com). Не требует реального домена. Подходит для большинства случаев.

### Real-TLS (nginx + Let's Encrypt)

Настоящий TLS-сертификат для вашего домена. Nginx на порту 443 выполняет две роли:
- При обычном HTTPS-запросе (браузер) — показывает реальный сайт-заглушку
- MTProto-трафик (Telegram) — проксируется на mtg

Для цензоров сервер выглядит как обычный HTTPS-сайт. Требует домен, направленный A-записью на IP сервера.

```
Telegram Client ──TLS:443──► Nginx ──stream──► mtg (:3128)
Browser         ──HTTPS:443─► Nginx ──http───► Сайт-заглушка (:8443)
```

## Quick Start / Быстрый старт

### Установка на свежий VPS/VDS (одна команда)

Подключитесь к серверу по SSH и выполните:

```bash
curl -sSL https://raw.githubusercontent.com/arblark/mtproto-proxy-installer/main/mtproto-setup.sh -o mtproto-setup.sh && chmod +x mtproto-setup.sh && sudo ./mtproto-setup.sh
```

Или через `wget`:

```bash
wget -qO mtproto-setup.sh https://raw.githubusercontent.com/arblark/mtproto-proxy-installer/main/mtproto-setup.sh && chmod +x mtproto-setup.sh && sudo ./mtproto-setup.sh
```

Скрипт предложит выбрать режим (Fake-TLS / Real-TLS) и задаст вопросы с дефолтами.

### Пошаговая установка (Real-TLS)

1. Купите VPS/VDS и домен
2. Направьте A-запись домена на IP сервера
3. Подключитесь к серверу: `ssh root@IP_СЕРВЕРА`
4. Скачайте и запустите скрипт:

```bash
curl -sSL https://raw.githubusercontent.com/arblark/mtproto-proxy-installer/main/mtproto-setup.sh -o mtproto-setup.sh
chmod +x mtproto-setup.sh
sudo ./mtproto-setup.sh
```

5. Выберите режим `2) Real-TLS`
6. Введите домен и email для Let's Encrypt
7. Скопируйте ссылку или отсканируйте QR-код

### Ручной способ (клонирование)

```bash
git clone https://github.com/arblark/mtproto-proxy-installer.git
cd mtproto-proxy-installer
chmod +x mtproto-setup.sh
sudo ./mtproto-setup.sh
```

## Configuration / Параметры

### Общие

| Parameter | Default | Env variable | Description |
|---|---|---|---|
| TLS mode | `fake` | `MT_TLS_MODE` | Режим: `fake` или `real` |
| Server IP | auto-detect | `MT_SERVER_IP` | Внешний IP вашего VDS/VPS |
| External port | `443` | `MT_PORT` | Порт для подключения клиентов |
| Internal port | `3128` | — | Порт внутри Docker-контейнера |
| DNS server | `1.1.1.1` | `MT_DNS` | DNS (Cloudflare по умолчанию) |
| IP mode | `prefer-ipv4` | `MT_IP_MODE` | `prefer-ipv4` / `prefer-ipv6` / `only-ipv4` / `only-ipv6` |
| Container name | `mtproto` | `MT_CONTAINER` | Имя Docker-контейнера |

### Fake-TLS

| Parameter | Default | Env variable | Description |
|---|---|---|---|
| Domain | `apple.com` | `MT_DOMAIN` | Домен маскировки трафика |

### Real-TLS

| Parameter | Default | Env variable | Description |
|---|---|---|---|
| Domain | — | `MT_DOMAIN` | Реальный домен (A-запись на IP сервера) |
| Email | — | `MT_LE_EMAIL` | Email для Let's Encrypt |

## Commands / Команды

```bash
sudo ./mtproto-setup.sh              # интерактивная установка
sudo ./mtproto-setup.sh --auto       # установка без вопросов
sudo ./mtproto-setup.sh --status     # статус + диагностика
sudo ./mtproto-setup.sh --doctor     # диагностика (Telegram DC, nginx, сертификат)
sudo ./mtproto-setup.sh --show       # показать ссылки и QR-код
sudo ./mtproto-setup.sh --update     # обновить образ и перезапустить
sudo ./mtproto-setup.sh --uninstall  # удалить всё
sudo ./mtproto-setup.sh --help       # справка
```

## Auto Mode / Автоматический режим

### Fake-TLS

```bash
sudo MT_TLS_MODE=fake MT_DOMAIN=google.com ./mtproto-setup.sh --auto
```

### Real-TLS

```bash
sudo MT_TLS_MODE=real MT_DOMAIN=proxy.example.com MT_LE_EMAIL=me@example.com ./mtproto-setup.sh --auto
```

## What Gets Installed / Что устанавливается

### Fake-TLS

- Docker + образ `nineseconds/mtg:2`
- qrencode (для QR-кода)

### Real-TLS (дополнительно)

- Nginx (фронтенд на порту 443)
- Certbot (Let's Encrypt сертификат)
- Сайт-заглушка (`/var/www/mtproto-stub/`)
- Stream-модуль nginx (ssl_preread для маршрутизации)
- Cron для автообновления сертификата

## Safety Checks / Проверки

- **Порт** — перед запуском проверяется, не занят ли порт другим процессом
- **Домен (Fake-TLS)** — проверяется DNS-резолв домена маскировки
- **Домен (Real-TLS)** — проверяется, что A-запись указывает на IP сервера
- **Контейнер** — retry-loop с 10 попытками вместо фиксированной задержки
- **Соединение** — после запуска проверяется доступность порта локально
- **Doctor** — диагностика mtg (Telegram DC, DNS/SNI) + nginx + сертификат

## Secret Persistence / Сохранение секрета

Секрет и все параметры сохраняются в `/etc/mtproto-proxy/config`. При повторном запуске скрипт предложит переиспользовать существующий секрет — клиентские ссылки не сломаются.

## Requirements / Требования

- Linux (Debian / Ubuntu / CentOS / Fedora / и др.)
- Root-доступ (sudo)
- Доступ в интернет
- Для Real-TLS: домен с A-записью на IP сервера

## Keywords

MTProto, MTProto proxy, Telegram proxy, mtg, mtg proxy, fake-tls, real-tls, nginx, Let's Encrypt, Telegram MTProto, proxy installer, VPS proxy, VDS proxy, обход блокировок, Telegram unblock, MTProto setup, Docker proxy, one-click proxy, Telegram proxy server, QR code proxy

## License

MIT
