# MTProto Proxy Installer

One-script automated MTProto proxy setup for Telegram using [mtg](https://github.com/9seconds/mtg) (Docker).

Автоматическая установка MTProto прокси для Telegram одним скриптом. Docker, fake-tls, интерактивная настройка, QR-код.

---

## Features / Возможности

- **One command** — установка за одну команду на любом свежем VDS/VPS
- **Interactive** — интерактивный выбор порта, DNS, домена маскировки с дефолтами
- **Auto mode** — неинтерактивный режим для автоматизации (`--auto`)
- **Fake-TLS** — маскировка трафика под HTTPS (обход блокировок DPI)
- **Auto-detect IP** — автоопределение внешнего IP сервера
- **Port check** — проверка занятости порта перед запуском
- **Domain validation** — проверка DNS-резолва домена маскировки
- **Connection verify** — проверка доступности прокси после старта
- **QR code** — QR-код ссылки прямо в терминале (навёл камеру — подключился)
- **Docker** — всё работает в контейнере с `--restart always`
- **Firewall support** — автоматическое открытие порта (UFW + firewalld)
- **Ready-to-use links** — на выходе готовые `https://t.me/proxy` и `tg://proxy` ссылки
- **Secret persistence** — секрет сохраняется между запусками, клиентские ссылки не ломаются
- **Update & Uninstall** — встроенные команды обновления и удаления
- **Status & Show** — просмотр статуса и ссылок без переустановки
- **Multi-distro** — поддержка Debian, Ubuntu, CentOS, Fedora и других

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

### Пошаговая установка

1. Купите VPS/VDS (Debian, Ubuntu, CentOS — любой Linux)
2. Подключитесь к серверу: `ssh root@IP_СЕРВЕРА`
3. Скачайте и запустите скрипт:

```bash
curl -sSL https://raw.githubusercontent.com/arblark/mtproto-proxy-installer/main/mtproto-setup.sh -o mtproto-setup.sh
chmod +x mtproto-setup.sh
sudo ./mtproto-setup.sh
```

4. Ответьте на вопросы (или нажимайте Enter для значений по умолчанию)
5. Скопируйте готовую ссылку или отсканируйте QR-код в Telegram

### Ручной способ (клонирование репозитория)

```bash
git clone https://github.com/arblark/mtproto-proxy-installer.git
cd mtproto-proxy-installer
chmod +x mtproto-setup.sh
sudo ./mtproto-setup.sh
```

## Configuration / Параметры

| Parameter | Default | Env variable | Description |
|---|---|---|---|
| Server IP | auto-detect | `MT_SERVER_IP` | Внешний IP вашего VDS/VPS |
| External port | `443` | `MT_PORT` | Порт для подключения клиентов |
| Internal port | `3128` | — | Порт внутри Docker-контейнера |
| Fake-TLS domain | `apple.com` | `MT_DOMAIN` | Домен маскировки трафика |
| DNS server | `1.1.1.1` | `MT_DNS` | DNS (Cloudflare по умолчанию) |
| IP mode | `prefer-ipv4` | `MT_IP_MODE` | `prefer-ipv4` / `prefer-ipv6` / `only-ipv4` / `only-ipv6` |
| Container name | `mtproto` | `MT_CONTAINER` | Имя Docker-контейнера |

При повторном запуске скрипт подставляет значения из предыдущей конфигурации (`/etc/mtproto-proxy/config`).

## Commands / Команды

```bash
sudo ./mtproto-setup.sh              # интерактивная установка
sudo ./mtproto-setup.sh --auto       # установка без вопросов
sudo ./mtproto-setup.sh --status     # статус прокси (работает / остановлен)
sudo ./mtproto-setup.sh --show       # показать ссылки и QR-код
sudo ./mtproto-setup.sh --update     # обновить образ и перезапустить
sudo ./mtproto-setup.sh --uninstall  # удалить всё
sudo ./mtproto-setup.sh --help       # справка
```

## Auto Mode / Автоматический режим

Для автоматизации (Ansible, cloud-init, скрипты) используйте `--auto` с переменными окружения:

```bash
sudo MT_PORT=8443 MT_DOMAIN=google.com MT_DNS=8.8.8.8 ./mtproto-setup.sh --auto
```

Все параметры берутся из переменных окружения или используются значения по умолчанию. Никаких интерактивных вопросов.

## Output / Результат

После установки скрипт выведет:

```
  Сервер:      203.0.113.1
  Порт:        443
  Секрет:      ee00000000000000000000000000000000056170706c652e636f6d
  Домен:       apple.com
  DNS:         1.1.1.1

  Ссылки для подключения в Telegram:

  https://t.me/proxy?server=203.0.113.1&port=443&secret=ee...
  tg://proxy?server=203.0.113.1&port=443&secret=ee...

  QR-код (наведите камеру телефона):
  █████████████████████████
  █ ▄▄▄▄▄ █ ... █ ▄▄▄▄▄ █
  ...
```

## Secret Persistence / Сохранение секрета

Секрет и все параметры сохраняются в `/etc/mtproto-proxy/config`. При повторном запуске скрипт предложит переиспользовать существующий секрет — клиентские ссылки не сломаются. Новый секрет генерируется только если вы сменили домен маскировки или явно отказались от старого.

## Safety Checks / Проверки

- **Порт** — перед запуском проверяется, не занят ли порт другим процессом. Если занят — предупреждение и предложение выбрать другой.
- **Домен** — проверяется DNS-резолв домена маскировки (`dig`/`nslookup`/`host`). Если домен не резолвится — предупреждение.
- **Контейнер** — retry-loop с 10 попытками вместо фиксированной задержки.
- **Соединение** — после запуска проверяется доступность порта локально.

## Requirements / Требования

- Linux (Debian / Ubuntu / CentOS / Fedora / и др.)
- Root-доступ (sudo)
- Доступ в интернет

## Keywords

MTProto, MTProto proxy, Telegram proxy, mtg, mtg proxy, fake-tls, Telegram MTProto, proxy installer, VPS proxy, VDS proxy, обход блокировок, Telegram unblock, MTProto setup, Docker proxy, one-click proxy, Telegram proxy server, QR code proxy

## License

MIT
