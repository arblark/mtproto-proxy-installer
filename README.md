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
- **UFW support** — автоматическое открытие порта в файрволе
- **Ready-to-use link** — на выходе готовая `tg://proxy` ссылка для Telegram
- **Multi-distro** — поддержка Debian, Ubuntu, CentOS, Fedora, и других

## Quick Start / Быстрый старт

```bash
chmod +x mtproto-setup.sh
sudo ./mtproto-setup.sh
```

Скрипт задаст вопросы — можно просто нажимать Enter для значений по умолчанию.

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

## Output / Результат

После установки скрипт выведет:

```
  Сервер:      203.0.113.1
  Порт:        443
  Секрет:      ee00000000000000000000000000000000056170706c652e636f6d
  Домен:       apple.com
  DNS:         1.1.1.1

  Ссылка для подключения в Telegram:

  https://t.me/proxy?server=203.0.113.1&port=443&secret=ee...
```

## Management / Управление

```bash
docker ps | grep mtproto        # статус
docker logs -f mtproto          # логи
docker restart mtproto          # перезапуск
docker stop mtproto             # остановка
docker rm -f mtproto            # удаление
```

## Requirements / Требования

- Linux (Debian / Ubuntu / CentOS / Fedora / и др.)
- Root-доступ (sudo)
- Доступ в интернет

## Keywords

MTProto, MTProto proxy, Telegram proxy, mtg, mtg proxy, fake-tls, Telegram MTProto, proxy installer, VPS proxy, VDS proxy, обход блокировок, Telegram unblock, MTProto setup, Docker proxy, one-click proxy, Telegram proxy server

## License

MIT
