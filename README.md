# MTProto Proxy Installer

One-script automated MTProto proxy setup for Telegram using [mtg](https://github.com/9seconds/mtg) (Docker).

Автоматическая установка MTProto прокси для Telegram одним скриптом. Docker, fake-tls, интерактивная настройка.

---

## Features / Возможности

- **One command** — установка за одну команду на любом свежем VDS/VPS
- **Interactive** — интерактивный выбор порта, DNS, домена маскировки с дефолтами
- **Fake-TLS** — маскировка трафика под HTTPS (обход блокировок DPI)
- **Auto-detect IP** — автоопределение внешнего IP сервера
- **Docker** — всё работает в контейнере с `--restart always`
- **Firewall support** — автоматическое открытие порта (UFW + firewalld)
- **Ready-to-use links** — на выходе готовые `https://t.me/proxy` и `tg://proxy` ссылки
- **Secret persistence** — секрет сохраняется между запусками, клиентские ссылки не ломаются
- **Update & Uninstall** — встроенные команды обновления и удаления
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
5. Скопируйте готовую ссылку и откройте её в Telegram

### Ручной способ (клонирование репозитория)

```bash
git clone https://github.com/arblark/mtproto-proxy-installer.git
cd mtproto-proxy-installer
chmod +x mtproto-setup.sh
sudo ./mtproto-setup.sh
```

Скрипт сам установит Docker, обновит систему и настроит всё автоматически. На выходе — готовая ссылка для Telegram.

## Configuration / Параметры

| Parameter | Default | Description |
|---|---|---|
| Server IP | auto-detect | Внешний IP вашего VDS/VPS |
| External port | `443` | Порт для подключения клиентов |
| Internal port | `3128` | Порт внутри Docker-контейнера |
| Fake-TLS domain | `apple.com` | Домен маскировки трафика |
| DNS server | `1.1.1.1` | DNS (Cloudflare по умолчанию) |
| IP mode | `prefer-ipv4` | `prefer-ipv4` / `prefer-ipv6` / `only-ipv4` / `only-ipv6` |
| Container name | `mtproto` | Имя Docker-контейнера |

При повторном запуске скрипт подставляет значения из предыдущей конфигурации (`/etc/mtproto-proxy/config`).

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
```

## Management / Управление

```bash
sudo ./mtproto-setup.sh              # установка / переустановка
sudo ./mtproto-setup.sh --update     # обновить образ и перезапустить
sudo ./mtproto-setup.sh --uninstall  # удалить контейнер, образ, конфигурацию
sudo ./mtproto-setup.sh --help       # справка
```

Ручные Docker-команды:

```bash
docker ps | grep mtproto        # статус
docker logs -f mtproto          # логи
docker restart mtproto          # перезапуск
```

## Secret Persistence / Сохранение секрета

Секрет и все параметры сохраняются в `/etc/mtproto-proxy/config`. При повторном запуске скрипт предложит переиспользовать существующий секрет — клиентские ссылки не сломаются. Новый секрет генерируется только если вы сменили домен маскировки или явно отказались от старого.

## Requirements / Требования

- Linux (Debian / Ubuntu / CentOS / Fedora / и др.)
- Root-доступ (sudo)
- Доступ в интернет

## Keywords

MTProto, MTProto proxy, Telegram proxy, mtg, mtg proxy, fake-tls, Telegram MTProto, proxy installer, VPS proxy, VDS proxy, обход блокировок, Telegram unblock, MTProto setup, Docker proxy, one-click proxy, Telegram proxy server

## License

MIT
