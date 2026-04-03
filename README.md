# MTProto Proxy Installer

Автоматическая установка MTProto прокси для Telegram одним скриптом на базе [mtg v2](https://github.com/9seconds/mtg) (Docker).

Два режима работы: **Fake-TLS** (быстрая настройка) и **Real-TLS** (максимальная маскировка с реальным доменом, сертификатом и TOML-конфигом).

---

> **Не хотите разбираться с консолью?** Есть Telegram-бот, который полностью установит и настроит прокси на вашем сервере — без SSH, без команд. Ссылку на бота можно получить у автора: [@arblark](https://t.me/arblark)
>
> **Вопросы, помощь, предложения** — [@arblark](https://t.me/arblark)

---

## Важно: текущая ситуация с MTProto в России (2026)

С 2024–2025 года системы DPI (глубокой инспекции трафика) и ТСПУ в России научились достаточно уверенно определять MTProto Fake-TLS трафик. Это касается **всех** реализаций MTProto прокси, не только mtg — включая [mtprotoproxy](https://github.com/alexbers/mtprotoproxy), [telemt](https://github.com/telemt/telemt) и другие.

### Что это значит на практике

- MTProto прокси **может работать нестабильно или не работать вовсе** в зависимости от вашего оператора, региона и конкретного VPS
- DPI обрывает соединение на этапе TLS-handshake ещё до того, как прокси успевает что-либо сделать — на стороне скрипта или сервера это исправить невозможно
- Обычный HTTPS к тому же серверу при этом проходит свободно — блокируется именно MTProto внутри TLS
- Одни IP/подсети могут работать, другие — нет. Смена VPS иногда помогает, но не гарантированно

### Что можно попробовать

1. **Другой VPS** — сменить хостер, страну, подсеть. DPI фильтрует неодинаково, иногда помогает
2. **Другая реализация** — [telemt](https://github.com/telemt/telemt) (Rust), [mtprotoproxy](https://github.com/alexbers/mtprotoproxy) (Python) — другой TLS-отпечаток, DPI может не распознать
3. **Другой оператор / Wi-Fi** — фильтрация отличается у разных провайдеров
4. **Real-TLS режим** этого скрипта — реальный домен + сертификат + doppelganger. Не гарантия, но максимум того, что можно сделать в рамках MTProto

### Если нужен гарантированный обход

MTProto прокси задумывался как простой инструмент: одна ссылка — подключился к Telegram. Но для надёжного обхода блокировок в 2026 году лучше подходят полноценные VPN-протоколы:

- **[AmneziaWG](https://amnezia.org/)** — модифицированный WireGuard, устойчив к DPI
- **VLESS/Reality** ([Xray](https://github.com/XTLS/Xray-core)) — маскировка неотличима от реального TLS
- **[Outline](https://getoutline.org/)** (Shadowsocks) — простой в настройке
- **[sing-box](https://sing-box.sagernet.org/)** — мультипротокольный клиент

Эти решения шифруют **весь трафик** (не только Telegram), и DPI не может отличить его от обычного HTTPS или WireGuard. Если MTProto прокси у вас не работает — рекомендуем перейти на один из этих вариантов.

Автор mtg также описывает текущую ситуацию в [Best Practices](https://github.com/9seconds/mtg/blob/master/BEST_PRACTICES.md) (март 2026).

---

## Возможности

- Два режима — Fake-TLS и Real-TLS (TOML-конфиг + nginx + Let's Encrypt)
- Установка за одну команду на любом свежем VPS/VDS
- Интерактивный и автоматический (`--auto`) режимы
- **Real-TLS**: полный TOML-конфиг mtg с doppelganger, anti-replay, blocklist
- **Doppelganger**: mtg имитирует TLS-паттерны реального сайта для обхода DPI
- **Anti-replay**: защита от active probing
- **IP Blocklist**: блокировка вредоносных IP по спискам FireHOL
- Автоопределение внешнего IP сервера
- Проверка порта, DNS, доступности прокси после старта
- QR-код ссылки в терминале
- Docker-контейнер с `--restart always`
- Автооткрытие порта в файрволе (UFW + firewalld)
- Готовые `t.me/proxy` и `tg://proxy` ссылки
- Секрет сохраняется между запусками
- Встроенные команды: `--status`, `--doctor`, `--show`, `--update`, `--uninstall`
- Поддержка Debian, Ubuntu, CentOS, Fedora

## Режимы TLS

### Fake-TLS

Прокси маскируется под HTTPS-соединение к указанному домену (например `apple.com`). Не требует реального домена. mtg запускается с TOML-конфигом, включающим anti-replay и blocklist.

```
Telegram  ──:443──►  mtg (TOML, -p EXT:INT)  ──►  Telegram DC
```

### Real-TLS (рекомендуемый)

Продвинутый режим по [рекомендациям автора mtg](https://github.com/9seconds/mtg/blob/master/BEST_PRACTICES.md). mtg работает с полным TOML-конфигом, слушает на порту 443 напрямую (`--network host`) и использует встроенный domain fronting:

- **Telegram-клиент** → mtg:443 → распознаёт MTProto → проксирует к Telegram DC
- **Браузер / цензор** → mtg:443 → не MTProto → domain fronting → nginx:8443 → сайт с настоящим сертификатом

```
Telegram  ──TLS:443──►  mtg (TOML, --network host)  ──►  Telegram DC
Browser   ──TLS:443──►  mtg  ──domain fronting──►  nginx:8443  ──►  Сайт-заглушка
                         nginx:80  ──►  HTTP→HTTPS + ACME challenge
```

Что делает Real-TLS помимо проксирования:


| Защита              | Описание                                                                                                                                                                                                                        |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Doppelganger**    | mtg каждые 6 часов запрашивает страницы сайта-заглушки и собирает статистику TLS-пакетов — задержки, размер чанков. Затем имитирует эти паттерны при обслуживании Telegram-клиентов. Для DPI трафик неотличим от обычного HTTPS |
| **Anti-replay**     | Кеш отпечатков соединений. Блокирует повторное воспроизведение перехваченных запросов (active probing)                                                                                                                          |
| **Blocklist**       | Автоматическая блокировка IP из списков FireHOL (обновление каждые 24 часа)                                                                                                                                                     |
| **Domain fronting** | Не-MTProto запросы прозрачно перенаправляются на nginx:8443, который отвечает реальным сертификатом Let's Encrypt                                                                                                               |


Требования: домен с A-записью на IP сервера.

## Быстрый старт

### Одна команда

```bash
curl -sSL https://raw.githubusercontent.com/arblark/mtproto-proxy-installer/main/mtproto-setup.sh -o mtproto-setup.sh && chmod +x mtproto-setup.sh && sudo ./mtproto-setup.sh
```

Или через wget:

```bash
wget -qO mtproto-setup.sh https://raw.githubusercontent.com/arblark/mtproto-proxy-installer/main/mtproto-setup.sh && chmod +x mtproto-setup.sh && sudo ./mtproto-setup.sh
```

### Установка Real-TLS (пошагово)

1. Купите VPS и домен
2. Направьте A-запись домена на IP сервера (подождите 5–10 минут)
3. Подключитесь: `ssh root@IP_СЕРВЕРА`
4. Запустите:

```bash
curl -sSL https://raw.githubusercontent.com/arblark/mtproto-proxy-installer/main/mtproto-setup.sh -o mtproto-setup.sh
chmod +x mtproto-setup.sh
sudo ./mtproto-setup.sh
```

1. Выберите `2) Real-TLS`
2. Введите домен и email для Let's Encrypt
3. Скопируйте ссылку или отсканируйте QR-код

### Через git clone

```bash
git clone https://github.com/arblark/mtproto-proxy-installer.git
cd mtproto-proxy-installer
chmod +x mtproto-setup.sh
sudo ./mtproto-setup.sh
```

## Параметры

### Общие


| Параметр        | По умолчанию  | Env-переменная | Описание                                                  |
| --------------- | ------------- | -------------- | --------------------------------------------------------- |
| Режим TLS       | `fake`        | `MT_TLS_MODE`  | `fake` или `real`                                         |
| IP сервера      | авто          | `MT_SERVER_IP` | Внешний IP                                                |
| Внешний порт    | `443`         | `MT_PORT`      | Порт для клиентов                                         |
| Внутренний порт | `3128`        | —              | Порт внутри контейнера (только Fake-TLS)                  |
| DNS             | `1.1.1.1`     | `MT_DNS`       | DNS-сервер (DoH `https://` в Real-TLS)                    |
| Режим IP        | `prefer-ipv4` | `MT_IP_MODE`   | `prefer-ipv4` / `prefer-ipv6` / `only-ipv4` / `only-ipv6` |
| Контейнер       | `mtproto`     | `MT_CONTAINER` | Имя Docker-контейнера                                     |


### Fake-TLS


| Параметр | По умолчанию | Env-переменная | Описание         |
| -------- | ------------ | -------------- | ---------------- |
| Домен    | `apple.com`  | `MT_DOMAIN`    | Домен маскировки |


### Real-TLS


| Параметр | По умолчанию | Env-переменная | Описание                               |
| -------- | ------------ | -------------- | -------------------------------------- |
| Домен    | —            | `MT_DOMAIN`    | Реальный домен (A-запись → IP сервера) |
| Email    | —            | `MT_LE_EMAIL`  | Email для Let's Encrypt                |


## Команды

```bash
sudo ./mtproto-setup.sh              # интерактивная установка
sudo ./mtproto-setup.sh --auto       # установка без вопросов (из env-переменных)
sudo ./mtproto-setup.sh --status     # статус контейнера + диагностика
sudo ./mtproto-setup.sh --doctor     # диагностика mtg (Telegram DC) + nginx + сертификат + порты
sudo ./mtproto-setup.sh --show       # показать ссылки и QR-код
sudo ./mtproto-setup.sh --update     # обновить образ mtg и перезапустить
sudo ./mtproto-setup.sh --uninstall  # удалить контейнер, конфиг, nginx, сертификат
sudo ./mtproto-setup.sh --help       # справка
```

## Автоматический режим

```bash
# Fake-TLS
sudo MT_TLS_MODE=fake MT_DOMAIN=google.com ./mtproto-setup.sh --auto

# Real-TLS
sudo MT_TLS_MODE=real MT_DOMAIN=proxy.example.com MT_LE_EMAIL=me@example.com ./mtproto-setup.sh --auto
```

## Что устанавливается

### Fake-TLS


| Компонент | Описание |
|---|---|
| Docker | Если не установлен |
| `nineseconds/mtg:2` | Docker-образ mtg v2 |
| qrencode | Генерация QR-кода в терминале |
| TOML-конфиг mtg | `/etc/mtproto-proxy/mtg.toml` — secret, anti-replay, blocklist, таймауты |
| Контейнер | `-p EXT_PORT:3128`, режим `run /config.toml` |


### Real-TLS


| Компонент                    | Путь / описание                                                                                                   |
| ---------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| Docker + `nineseconds/mtg:2` | Docker-образ mtg v2                                                                                               |
| qrencode                     | Генерация QR-кода                                                                                                 |
| Контейнер                    | `--network host`, режим `run /config.toml`                                                                        |
| TOML-конфиг mtg              | `/etc/mtproto-proxy/mtg.toml` — secret, bind-to, doppelganger, anti-replay, blocklist, domain-fronting, dns (DoH) |
| Конфиг скрипта               | `/etc/mtproto-proxy/config` — параметры для `--status`, `--update`, `--show`                                      |
| Nginx                        | Порт 80 (HTTP→HTTPS + ACME) + порт 8443 (HTTPS-сайт с LE-сертификатом)                                            |
| Certbot                      | Получение сертификата Let's Encrypt                                                                               |
| Cron                         | Автообновление сертификата (ежедневно в 3:00)                                                                     |
| Сайт-заглушка                | `/var/www/mtproto-stub/` — 3 страницы (главная, о компании, статус)                                               |


## Как работает Real-TLS

```
┌─────────────────────────────────────────────────────┐
│  VPS                                                │
│                                                     │
│  :443   mtg (Docker, --network host)                │
│         ├─ MTProto? → Telegram DC                   │
│         └─ Не MTProto? → 127.0.0.1:8443            │
│                                                     │
│  :8443  nginx (HTTPS, LE-сертификат)                │
│         └─ Сайт-заглушка                            │
│                                                     │
│  :80    nginx (HTTP)                                │
│         ├─ /.well-known/acme-challenge → certbot    │
│         └─ Остальное → 301 redirect на HTTPS        │
│                                                     │
│  /etc/mtproto-proxy/mtg.toml                        │
│         ├─ [defense.doppelganger] — имитация TLS    │
│         ├─ [defense.anti-replay]  — защита от проб  │
│         ├─ [defense.blocklist]    — блок вредных IP  │
│         └─ [domain-fronting] port = 8443            │
└─────────────────────────────────────────────────────┘
```

1. mtg слушает на порту 443 с `--network host`
2. Telegram-клиент подключается (секрет содержит закодированный домен)
3. mtg распознаёт MTProto — проксирует к Telegram DC
4. Если подключение не MTProto — mtg передаёт TCP-поток на `127.0.0.1:8443` (domain fronting)
5. nginx на 8443 принимает TLS и отдаёт сайт с реальным сертификатом
6. Doppelganger каждые 6 часов обходит страницы сайта и калибрует TLS-паттерны
7. Anti-replay кеширует отпечатки соединений и отклоняет повторы

## Проверки безопасности


| Проверка             | Когда                                                                            |
| -------------------- | -------------------------------------------------------------------------------- |
| Порт занят           | Перед запуском (Fake-TLS)                                                        |
| DNS резолв           | Fake-TLS: домен резолвится; Real-TLS: A-запись = IP сервера                      |
| Контейнер запустился | Retry-loop, 10 попыток                                                           |
| Порт отвечает        | После запуска контейнера                                                         |
| Doctor               | `--status` / `--doctor`: Telegram DC, DNS/SNI, nginx, сертификат, порты 443/8443 |


## Сохранение секрета

Секрет и все параметры сохраняются в `/etc/mtproto-proxy/config`. При повторном запуске скрипт предложит переиспользовать секрет — клиентские ссылки не сломаются.

TOML-конфиг mtg хранится в `/etc/mtproto-proxy/mtg.toml` и перегенерируется при каждой установке или `--update`.

## Требования

- Linux (Debian, Ubuntu, CentOS, Fedora и др.)
- Root-доступ
- Доступ в интернет
- Для Real-TLS: домен с A-записью на IP сервера

## Полезные ссылки

- [mtg — GitHub](https://github.com/9seconds/mtg)
- [Best Practices (mtg)](https://github.com/9seconds/mtg/blob/master/BEST_PRACTICES.md) — рекомендации автора по настройке
- [Пример TOML-конфига (mtg)](https://github.com/9seconds/mtg/blob/master/example.config.toml)

## Keywords

MTProto, MTProto proxy, Telegram proxy, mtg, mtg proxy, mtg toml, fake-tls, real-tls, doppelganger, anti-replay, domain fronting, blocklist, Telegram MTProto, proxy installer, VPS proxy, VDS proxy, обход блокировок, Telegram unblock, MTProto setup, Docker proxy, one-click proxy, Telegram proxy server, QR code proxy, Let's Encrypt, nginx

## License

MIT