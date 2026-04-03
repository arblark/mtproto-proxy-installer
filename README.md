# MTProto Proxy Installer

One-script automated MTProto proxy setup for Telegram using [mtg](https://github.com/9seconds/mtg) (Docker).

Автоматическая установка MTProto прокси для Telegram одним скриптом. Два режима: Fake-TLS и Real-TLS.

---

> **Не хотите разбираться с консолью?** Есть Telegram-бот, который полностью установит и настроит MTProto прокси на вашем сервере — без SSH, без команд, всё через бот. Ссылку на бота можно получить у автора: [@arblark](https://t.me/arblark)
>
> **Вопросы, помощь, предложения** — пишите в Telegram: [@arblark](https://t.me/arblark)

---

## Features / Возможности

- **Two TLS modes** — Fake-TLS (стандартный) или Real-TLS (реальный домен + сертификат)
- **One command** — установка за одну команду на любом свежем VDS/VPS
- **Interactive** — интерактивный выбор режима, порта, DNS, домена с дефолтами
- **Auto mode** — неинтерактивный режим для автоматизации (`--auto`)
- **Real-TLS with TOML config** — полный конфиг mtg с doppelganger, anti-replay, blocklist
- **Doppelganger** — mtg имитирует TLS-паттерны реального сайта (защита от DPI)
- **Anti-replay** — защита от active probing (повторного воспроизведения соединений)
- **IP Blocklist** — автоматическая блокировка известных вредоносных IP (FireHOL)
- **Auto-detect IP** — автоопределение внешнего IP сервера
- **Port check** — проверка занятости порта перед запуском
- **Domain validation** — проверка DNS: домен → IP сервера (Real-TLS) или резолв (Fake-TLS)
- **Connection verify** — проверка доступности прокси после старта
- **QR code** — QR-код ссылки прямо в терминале
- **Docker** — всё работает в контейнере с `--restart always`
- **Firewall support** — автоматическое открытие порта (UFW + firewalld)
- **Ready-to-use links** — готовые `https://t.me/proxy` и `tg://proxy` ссылки
- **Secret persistence** — секрет сохраняется между запусками, ссылки не ломаются
- **Update & Uninstall** — встроенные команды обновления и удаления
- **Status & Doctor** — статус, диагностика mtg + nginx + сертификат + порты
- **Multi-distro** — Debian, Ubuntu, CentOS, Fedora и другие

## TLS Modes / Режимы TLS

### Fake-TLS (стандартный)

Прокси маскируется под HTTPS-соединение к указанному домену (например, apple.com). Не требует реального домена. Используется `simple-run` режим mtg.

### Real-TLS (рекомендуемый)

Реальный TLS-сертификат Let's Encrypt для вашего домена. mtg слушает на порту 443 напрямую и использует встроенный механизм domain fronting:

- **Telegram-клиент** → mtg:443 → MTProto (прокси работает)
- **Браузер / цензор** → mtg:443 → domain fronting → nginx:8443 → реальный сайт

mtg сам определяет тип входящего соединения. Если это не MTProto — перенаправляет на nginx, который отдаёт сайт-заглушку с настоящим SSL-сертификатом. Для цензора сервер неотличим от обычного HTTPS-сайта.

Дополнительные защиты в Real-TLS:
- **Doppelganger** — mtg периодически запрашивает страницы сайта и имитирует их TLS-паттерны
- **Anti-replay** — кеш отпечатков соединений для защиты от active probing
- **Blocklist** — автоматическая блокировка IP из списков FireHOL

```
Telegram  ──TLS:443──► mtg (--network host) ──► Telegram DC
Browser   ──TLS:443──► mtg ──domain fronting──► nginx:8443 ──► Сайт-заглушка
                       nginx:80 ──► HTTP→HTTPS редирект + ACME
```

Требует: домен с A-записью на IP сервера.

## Quick Start / Быстрый старт

### Установка (одна команда)

Подключитесь к серверу по SSH и выполните:

```bash
curl -sSL https://raw.githubusercontent.com/arblark/mtproto-proxy-installer/main/mtproto-setup.sh -o mtproto-setup.sh && chmod +x mtproto-setup.sh && sudo ./mtproto-setup.sh
```

Или через `wget`:

```bash
wget -qO mtproto-setup.sh https://raw.githubusercontent.com/arblark/mtproto-proxy-installer/main/mtproto-setup.sh && chmod +x mtproto-setup.sh && sudo ./mtproto-setup.sh
```

Скрипт предложит выбрать режим (Fake-TLS / Real-TLS) и задаст вопросы с дефолтами.

### Установка Real-TLS (пошагово)

1. Купите VPS/VDS и домен
2. Направьте A-запись домена на IP сервера
3. Подключитесь: `ssh root@IP_СЕРВЕРА`
4. Скачайте и запустите:

```bash
curl -sSL https://raw.githubusercontent.com/arblark/mtproto-proxy-installer/main/mtproto-setup.sh -o mtproto-setup.sh
chmod +x mtproto-setup.sh
sudo ./mtproto-setup.sh
```

5. Выберите `2) Real-TLS`
6. Введите домен и email для Let's Encrypt
7. Скопируйте ссылку или отсканируйте QR-код

### Клонирование

```bash
git clone https://github.com/arblark/mtproto-proxy-installer.git
cd mtproto-proxy-installer
chmod +x mtproto-setup.sh
sudo ./mtproto-setup.sh
```

## Configuration / Параметры

### Общие

| Параметр | По умолчанию | Env-переменная | Описание |
|---|---|---|---|
| TLS mode | `fake` | `MT_TLS_MODE` | Режим: `fake` или `real` |
| Server IP | авто | `MT_SERVER_IP` | Внешний IP сервера |
| External port | `443` | `MT_PORT` | Порт для подключения клиентов |
| Internal port | `3128` | — | Порт внутри контейнера (только Fake-TLS) |
| DNS server | `1.1.1.1` | `MT_DNS` | DNS-сервер (DoH в Real-TLS) |
| IP mode | `prefer-ipv4` | `MT_IP_MODE` | `prefer-ipv4` / `prefer-ipv6` / `only-ipv4` / `only-ipv6` |
| Container name | `mtproto` | `MT_CONTAINER` | Имя Docker-контейнера |

### Fake-TLS

| Параметр | По умолчанию | Env-переменная | Описание |
|---|---|---|---|
| Domain | `apple.com` | `MT_DOMAIN` | Домен маскировки трафика |

### Real-TLS

| Параметр | По умолчанию | Env-переменная | Описание |
|---|---|---|---|
| Domain | — | `MT_DOMAIN` | Реальный домен (A-запись → IP сервера) |
| Email | — | `MT_LE_EMAIL` | Email для Let's Encrypt |

## Commands / Команды

```bash
sudo ./mtproto-setup.sh              # интерактивная установка
sudo ./mtproto-setup.sh --auto       # установка без вопросов
sudo ./mtproto-setup.sh --status     # статус + диагностика
sudo ./mtproto-setup.sh --doctor     # диагностика (Telegram DC, nginx, сертификат, порты)
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
- Контейнер с port mapping (`-p EXT_PORT:INTERNAL_PORT`)

### Real-TLS

- Docker + образ `nineseconds/mtg:2`
- qrencode (для QR-кода)
- Контейнер с `--network host` (mtg слушает на порту 443 напрямую)
- TOML-конфиг mtg (`/etc/mtproto-proxy/mtg.toml`) с doppelganger, anti-replay, blocklist
- Nginx (порты 80 + 8443 — редирект и HTTPS-сайт)
- Certbot (Let's Encrypt сертификат)
- Сайт-заглушка (`/var/www/mtproto-stub/` — 3 страницы)
- Cron для автообновления сертификата

## How Real-TLS Works / Как работает Real-TLS

1. **mtg** запускается с `--network host` и слушает на порту 443
2. Telegram-клиент подключается через Fake-TLS (секрет содержит домен)
3. mtg распознаёт MTProto-трафик и проксирует его к Telegram DC
4. Если подключение **не** MTProto (браузер, цензор, бот) — mtg перенаправляет TCP-поток на `127.0.0.1:8443` (domain fronting)
5. **nginx** на порту 8443 принимает TLS-соединение и отдаёт сайт с реальным сертификатом Let's Encrypt
6. **nginx** на порту 80 — редирект HTTP→HTTPS + ACME challenge для обновления сертификата
7. **Doppelganger** — mtg каждые 6 часов запрашивает страницы сайта и собирает статистику TLS-пакетов для имитации

## Safety Checks / Проверки

- **Порт** — перед запуском проверяется, не занят ли порт (Fake-TLS)
- **Домен (Fake-TLS)** — проверяется DNS-резолв
- **Домен (Real-TLS)** — проверяется, что A-запись указывает на IP сервера
- **Контейнер** — retry-loop с 10 попытками
- **Соединение** — после запуска проверяется доступность порта
- **Doctor** — диагностика mtg (Telegram DC, DNS/SNI) + nginx + сертификат + порты 443/8443

## Secret Persistence / Сохранение секрета

Секрет и параметры сохраняются в `/etc/mtproto-proxy/config`. При повторном запуске скрипт предложит переиспользовать существующий секрет — клиентские ссылки не сломаются.

## Requirements / Требования

- Linux (Debian / Ubuntu / CentOS / Fedora / и др.)
- Root-доступ (sudo)
- Доступ в интернет
- Для Real-TLS: домен с A-записью на IP сервера

## Keywords

MTProto, MTProto proxy, Telegram proxy, mtg, mtg proxy, fake-tls, real-tls, doppelganger, anti-replay, domain fronting, Telegram MTProto, proxy installer, VPS proxy, VDS proxy, обход блокировок, Telegram unblock, MTProto setup, Docker proxy, one-click proxy, Telegram proxy server, QR code proxy, Let's Encrypt

## License

MIT
