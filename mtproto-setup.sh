#!/bin/bash

set -e

# ─────────────────────────────────────────────────────────────
#  MTProto Proxy — автоматическая установка (nineseconds/mtg)
# ─────────────────────────────────────────────────────────────

CONFIG_DIR="/etc/mtproto-proxy"
CONFIG_FILE="${CONFIG_DIR}/config"
LOG_FILE="/var/log/mtproto-setup.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

AUTO_MODE=false

print_header() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${BOLD}    MTProto Proxy — Автоматическая установка     ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}║         nineseconds/mtg v2 (Docker)              ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Ошибка: скрипт нужно запускать от root (sudo)${NC}"
        exit 1
    fi
}

detect_ip() {
    local ip=""
    ip=$(curl -4 -s --max-time 5 https://ifconfig.me 2>/dev/null) \
        || ip=$(curl -4 -s --max-time 5 https://api.ipify.org 2>/dev/null) \
        || ip=$(curl -4 -s --max-time 5 https://icanhazip.com 2>/dev/null) \
        || ip=$(hostname -I 2>/dev/null | awk '{print $1}') \
        || ip="YOUR_SERVER_IP"
    echo "$ip"
}

prompt_value() {
    local varname="$1"
    local description="$2"
    local default="$3"

    if [[ "$AUTO_MODE" == true ]]; then
        eval "$varname=\"$default\""
        return
    fi

    echo -en "${YELLOW}${description}${NC} [${GREEN}${default}${NC}]: "
    read -r input
    input="${input:-$default}"
    eval "$varname=\"$input\""
}

prompt_yes_no() {
    local prompt_text="$1"
    local default="${2:-y}"

    if [[ "$AUTO_MODE" == true ]]; then
        [[ "$default" == "y" ]]
        return
    fi

    if [[ "$default" == "y" ]]; then
        echo -en "${YELLOW}${prompt_text}${NC} [${GREEN}Y/n${NC}]: "
    else
        echo -en "${YELLOW}${prompt_text}${NC} [${GREEN}y/N${NC}]: "
    fi
    read -r answer
    answer="${answer:-$default}"
    [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]]
}

save_config() {
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_FILE" <<EOF
SECRET=${SECRET}
FAKE_DOMAIN=${FAKE_DOMAIN}
SERVER_IP=${SERVER_IP}
EXT_PORT=${EXT_PORT}
INTERNAL_PORT=${INTERNAL_PORT}
DNS_SERVER=${DNS_SERVER}
IP_PREFER=${IP_PREFER}
CONTAINER_NAME=${CONTAINER_NAME}
EOF
    chmod 600 "$CONFIG_FILE"
}

load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        # shellcheck disable=SC1090
        source "$CONFIG_FILE"
        return 0
    fi
    return 1
}

install_docker() {
    if command -v docker &>/dev/null; then
        echo -e "${GREEN}✓ Docker уже установлен: $(docker --version)${NC}"
        return
    fi

    echo -e "${CYAN}➜ Установка Docker...${NC}"

    if command -v apt-get &>/dev/null; then
        apt-get update -qq
        apt-get install -y -qq docker.io
    elif command -v yum &>/dev/null; then
        yum install -y docker
        systemctl start docker
    elif command -v dnf &>/dev/null; then
        dnf install -y docker
        systemctl start docker
    else
        echo -e "${YELLOW}➜ Пакетный менеджер не найден, пробуем официальный скрипт Docker...${NC}"
        curl -fsSL https://get.docker.com | sh
    fi

    systemctl enable docker
    systemctl start docker
    echo -e "${GREEN}✓ Docker установлен: $(docker --version)${NC}"
}

stop_existing_container() {
    local name="$1"
    if docker ps -a --format '{{.Names}}' | grep -qw "$name"; then
        echo -e "${YELLOW}➜ Останавливаю существующий контейнер '${name}'...${NC}"
        docker rm -f "$name" &>/dev/null || true
    fi
}

generate_secret() {
    local domain="$1"
    docker run --rm nineseconds/mtg generate-secret --hex "$domain" 2>/dev/null
}

wait_for_container() {
    local name="$1"
    local max_attempts=10
    local attempt=0

    echo -e "${CYAN}➜ Ожидание запуска контейнера...${NC}"
    while (( attempt < max_attempts )); do
        if docker ps --format '{{.Names}}' | grep -qw "$name"; then
            echo -e "${GREEN}✓ Контейнер '${name}' запущен${NC}"
            return 0
        fi
        (( attempt++ ))
        sleep 1
    done

    echo -e "${RED}✗ Контейнер не запустился за ${max_attempts} секунд. Логи:${NC}"
    docker logs "$name" 2>&1 || true
    return 1
}

check_port_available() {
    local port="$1"
    local pid_info

    if command -v ss &>/dev/null; then
        pid_info=$(ss -tulpn 2>/dev/null | grep ":${port} " || true)
    elif command -v netstat &>/dev/null; then
        pid_info=$(netstat -tulpn 2>/dev/null | grep ":${port} " || true)
    else
        return 0
    fi

    if [[ -n "$pid_info" ]]; then
        echo -e "${RED}✗ Порт ${port} уже занят:${NC}"
        echo -e "  ${YELLOW}${pid_info}${NC}"
        echo ""

        if [[ "$AUTO_MODE" == true ]]; then
            echo -e "${RED}Ошибка: порт ${port} занят (авто-режим, прерываю)${NC}"
            exit 1
        fi

        if prompt_yes_no "  Продолжить установку на этот порт?" "n"; then
            return 0
        fi

        echo -en "${YELLOW}  Введите другой порт: ${NC}"
        read -r new_port
        if [[ -z "$new_port" ]]; then
            echo -e "${RED}Порт не указан, прерываю${NC}"
            exit 1
        fi
        EXT_PORT="$new_port"
        check_port_available "$EXT_PORT"
    fi
}

validate_domain() {
    local domain="$1"

    if command -v dig &>/dev/null; then
        if ! dig +short "$domain" A 2>/dev/null | grep -qE '^[0-9]+\.' ; then
            echo -e "${YELLOW}⚠ Домен '${domain}' не резолвится. Fake-TLS может не работать.${NC}"
            if [[ "$AUTO_MODE" == false ]]; then
                if ! prompt_yes_no "  Продолжить с этим доменом?" "y"; then
                    prompt_value FAKE_DOMAIN "  Введите другой домен" "apple.com"
                    validate_domain "$FAKE_DOMAIN"
                fi
            fi
        else
            echo -e "${GREEN}✓ Домен '${domain}' резолвится${NC}"
        fi
    elif command -v nslookup &>/dev/null; then
        if ! nslookup "$domain" 8.8.8.8 &>/dev/null; then
            echo -e "${YELLOW}⚠ Домен '${domain}' не резолвится. Fake-TLS может не работать.${NC}"
            if [[ "$AUTO_MODE" == false ]]; then
                if ! prompt_yes_no "  Продолжить с этим доменом?" "y"; then
                    prompt_value FAKE_DOMAIN "  Введите другой домен" "apple.com"
                    validate_domain "$FAKE_DOMAIN"
                fi
            fi
        else
            echo -e "${GREEN}✓ Домен '${domain}' резолвится${NC}"
        fi
    elif command -v host &>/dev/null; then
        if ! host "$domain" &>/dev/null; then
            echo -e "${YELLOW}⚠ Домен '${domain}' не резолвится. Fake-TLS может не работать.${NC}"
        else
            echo -e "${GREEN}✓ Домен '${domain}' резолвится${NC}"
        fi
    fi
}

verify_proxy_connection() {
    local port="$1"
    local max_attempts=5
    local attempt=0

    echo -e "${CYAN}➜ Проверка доступности порта ${port}...${NC}"
    while (( attempt < max_attempts )); do
        if (echo >/dev/tcp/127.0.0.1/"$port") 2>/dev/null; then
            echo -e "${GREEN}✓ Порт ${port} отвечает — прокси работает${NC}"
            return 0
        fi
        (( attempt++ ))
        sleep 1
    done

    echo -e "${YELLOW}⚠ Порт ${port} не отвечает локально (может быть нормально при NAT)${NC}"
    return 0
}

install_qrencode() {
    if command -v qrencode &>/dev/null; then
        return 0
    fi

    if command -v apt-get &>/dev/null; then
        apt-get install -y -qq qrencode &>/dev/null && return 0
    elif command -v yum &>/dev/null; then
        yum install -y -q qrencode &>/dev/null && return 0
    elif command -v dnf &>/dev/null; then
        dnf install -y -q qrencode &>/dev/null && return 0
    fi

    return 1
}

print_qr_code() {
    local link="$1"

    if install_qrencode; then
        echo -e "  ${BOLD}QR-код (наведите камеру телефона):${NC}"
        echo ""
        qrencode -t ANSIUTF8 "$link"
        echo ""
    fi
}

open_firewall_port() {
    local port="$1"

    if command -v ufw &>/dev/null; then
        echo -e "${CYAN}➜ Открываю порт ${port} в UFW...${NC}"
        ufw allow "${port}/tcp" &>/dev/null
        echo -e "${GREEN}✓ Порт ${port}/tcp открыт в UFW${NC}"
    fi

    if command -v firewall-cmd &>/dev/null; then
        echo -e "${CYAN}➜ Открываю порт ${port} в firewalld...${NC}"
        firewall-cmd --permanent --add-port="${port}/tcp" &>/dev/null
        firewall-cmd --reload &>/dev/null
        echo -e "${GREEN}✓ Порт ${port}/tcp открыт в firewalld${NC}"
    fi
}

close_firewall_port() {
    local port="$1"

    if command -v ufw &>/dev/null; then
        ufw delete allow "${port}/tcp" &>/dev/null || true
        echo -e "${GREEN}✓ Порт ${port}/tcp закрыт в UFW${NC}"
    fi

    if command -v firewall-cmd &>/dev/null; then
        firewall-cmd --permanent --remove-port="${port}/tcp" &>/dev/null || true
        firewall-cmd --reload &>/dev/null
        echo -e "${GREEN}✓ Порт ${port}/tcp закрыт в firewalld${NC}"
    fi
}

print_result() {
    local tme_link="https://t.me/proxy?server=${SERVER_IP}&port=${EXT_PORT}&secret=${SECRET}"
    local tg_link="tg://proxy?server=${SERVER_IP}&port=${EXT_PORT}&secret=${SECRET}"

    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${BOLD}            Установка завершена!                  ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BOLD}Сервер:${NC}      ${SERVER_IP}"
    echo -e "  ${BOLD}Порт:${NC}        ${EXT_PORT}"
    echo -e "  ${BOLD}Секрет:${NC}      ${SECRET}"
    echo -e "  ${BOLD}Домен:${NC}       ${FAKE_DOMAIN}"
    echo -e "  ${BOLD}DNS:${NC}         ${DNS_SERVER}"
    echo -e "  ${BOLD}Контейнер:${NC}   ${CONTAINER_NAME}"
    echo ""
    echo -e "${CYAN}──────────────────────────────────────────────────${NC}"
    echo -e "  ${BOLD}Ссылки для подключения в Telegram:${NC}"
    echo ""
    echo -e "  ${GREEN}${tme_link}${NC}"
    echo ""
    echo -e "  ${GREEN}${tg_link}${NC}"
    echo ""
    echo -e "${CYAN}──────────────────────────────────────────────────${NC}"

    print_qr_code "$tme_link"

    echo -e "${CYAN}──────────────────────────────────────────────────${NC}"
    echo -e "  ${BOLD}Полезные команды:${NC}"
    echo -e "  Статус:     $0 --status"
    echo -e "  Ссылки:     $0 --show"
    echo -e "  Обновить:   $0 --update"
    echo -e "  Удалить:    $0 --uninstall"
    echo ""
}

# ─── Команда: --status ───────────────────────────────────────

do_status() {
    check_root

    if ! load_config; then
        echo -e "${RED}MTProto Proxy не установлен (конфигурация не найдена)${NC}"
        exit 1
    fi

    local name="${CONTAINER_NAME:-mtproto}"

    echo ""
    echo -e "${BOLD}MTProto Proxy — Статус${NC}"
    echo -e "${CYAN}──────────────────────────────────────────────────${NC}"

    if docker ps --format '{{.Names}}' 2>/dev/null | grep -qw "$name"; then
        local status_line
        status_line=$(docker ps --format 'table {{.Status}}\t{{.Ports}}' --filter "name=^${name}$" | tail -1)
        echo -e "  ${BOLD}Состояние:${NC}   ${GREEN}работает${NC}"
        echo -e "  ${BOLD}Детали:${NC}      ${status_line}"
    elif docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qw "$name"; then
        local status_line
        status_line=$(docker ps -a --format '{{.Status}}' --filter "name=^${name}$" | tail -1)
        echo -e "  ${BOLD}Состояние:${NC}   ${RED}остановлен${NC}"
        echo -e "  ${BOLD}Детали:${NC}      ${status_line}"
    else
        echo -e "  ${BOLD}Состояние:${NC}   ${RED}контейнер не найден${NC}"
    fi

    echo -e "  ${BOLD}Сервер:${NC}      ${SERVER_IP}"
    echo -e "  ${BOLD}Порт:${NC}        ${EXT_PORT}"
    echo -e "  ${BOLD}Секрет:${NC}      ${SECRET}"
    echo -e "  ${BOLD}Домен:${NC}       ${FAKE_DOMAIN}"
    echo -e "  ${BOLD}DNS:${NC}         ${DNS_SERVER}"
    echo -e "  ${BOLD}Контейнер:${NC}   ${name}"

    echo ""
    echo -e "${CYAN}──────────────────────────────────────────────────${NC}"
    echo -e "  ${BOLD}Ссылки:${NC}"
    echo -e "  ${GREEN}https://t.me/proxy?server=${SERVER_IP}&port=${EXT_PORT}&secret=${SECRET}${NC}"
    echo -e "  ${GREEN}tg://proxy?server=${SERVER_IP}&port=${EXT_PORT}&secret=${SECRET}${NC}"
    echo ""
    exit 0
}

# ─── Команда: --show ─────────────────────────────────────────

do_show() {
    check_root

    if ! load_config; then
        echo -e "${RED}MTProto Proxy не установлен (конфигурация не найдена)${NC}"
        exit 1
    fi

    local tme_link="https://t.me/proxy?server=${SERVER_IP}&port=${EXT_PORT}&secret=${SECRET}"
    local tg_link="tg://proxy?server=${SERVER_IP}&port=${EXT_PORT}&secret=${SECRET}"

    echo ""
    echo -e "${BOLD}MTProto Proxy — Ссылки для подключения${NC}"
    echo -e "${CYAN}──────────────────────────────────────────────────${NC}"
    echo ""
    echo -e "  ${GREEN}${tme_link}${NC}"
    echo ""
    echo -e "  ${GREEN}${tg_link}${NC}"
    echo ""
    echo -e "${CYAN}──────────────────────────────────────────────────${NC}"

    print_qr_code "$tme_link"

    exit 0
}

# ─── Команда: --uninstall ────────────────────────────────────

do_uninstall() {
    print_header
    check_root

    local name="mtproto"
    local port=""

    if load_config; then
        name="${CONTAINER_NAME:-mtproto}"
        port="${EXT_PORT}"
    fi

    echo -e "${YELLOW}➜ Удаление MTProto Proxy...${NC}"

    if docker ps -a --format '{{.Names}}' | grep -qw "$name"; then
        docker rm -f "$name" &>/dev/null || true
        echo -e "${GREEN}✓ Контейнер '${name}' удалён${NC}"
    else
        echo -e "${YELLOW}  Контейнер '${name}' не найден${NC}"
    fi

    if [[ -n "$port" ]]; then
        close_firewall_port "$port"
    fi

    if prompt_yes_no "  Удалить Docker-образ nineseconds/mtg?" "n"; then
        docker rmi nineseconds/mtg &>/dev/null || true
        echo -e "${GREEN}✓ Образ удалён${NC}"
    fi

    if prompt_yes_no "  Удалить конфигурацию (${CONFIG_DIR})?" "n"; then
        rm -rf "$CONFIG_DIR"
        echo -e "${GREEN}✓ Конфигурация удалена${NC}"
    fi

    echo ""
    echo -e "${GREEN}✓ MTProto Proxy полностью удалён${NC}"
    exit 0
}

# ─── Команда: --update ───────────────────────────────────────

do_update() {
    print_header
    check_root

    if ! load_config; then
        echo -e "${RED}Ошибка: конфигурация не найдена (${CONFIG_FILE}).${NC}"
        echo -e "${YELLOW}Сначала выполните установку: $0${NC}"
        exit 1
    fi

    local name="${CONTAINER_NAME:-mtproto}"

    echo -e "${CYAN}➜ Обновление образа nineseconds/mtg...${NC}"
    docker pull nineseconds/mtg
    echo -e "${GREEN}✓ Образ обновлён${NC}"

    stop_existing_container "$name"

    echo -e "${CYAN}➜ Перезапуск контейнера с сохранёнными параметрами...${NC}"
    docker run -d \
        --name "$name" \
        --restart always \
        -p "${EXT_PORT}:${INTERNAL_PORT}" \
        --dns "$DNS_SERVER" \
        nineseconds/mtg simple-run \
        -n "$DNS_SERVER" \
        -i "$IP_PREFER" \
        "0.0.0.0:${INTERNAL_PORT}" \
        "$SECRET"

    if wait_for_container "$name"; then
        verify_proxy_connection "$EXT_PORT"
        print_result
    else
        exit 1
    fi
    exit 0
}

# ─── Обработка аргументов ────────────────────────────────────

case "${1:-}" in
    --uninstall|-u)
        do_uninstall
        ;;
    --update|-U)
        do_update
        ;;
    --status|-s)
        do_status
        ;;
    --show)
        do_show
        ;;
    --auto|-a)
        AUTO_MODE=true
        ;;
    --help|-h)
        echo "Использование: $0 [ОПЦИЯ]"
        echo ""
        echo "  (без опций)      Интерактивная установка / переустановка"
        echo "  --auto, -a       Установка без вопросов (значения по умолчанию или из env)"
        echo "  --update, -U     Обновить образ и перезапустить контейнер"
        echo "  --uninstall, -u  Удалить контейнер, образ и конфигурацию"
        echo "  --status, -s     Показать статус прокси"
        echo "  --show           Показать ссылки для подключения и QR-код"
        echo "  --help, -h       Показать эту справку"
        echo ""
        echo "Переменные окружения (для --auto):"
        echo "  MT_SERVER_IP     IP сервера (по умолчанию: автоопределение)"
        echo "  MT_PORT          Внешний порт (по умолчанию: 443)"
        echo "  MT_DOMAIN        Домен маскировки (по умолчанию: apple.com)"
        echo "  MT_DNS           DNS сервер (по умолчанию: 1.1.1.1)"
        echo "  MT_IP_MODE       Режим IP (по умолчанию: prefer-ipv4)"
        echo "  MT_CONTAINER     Имя контейнера (по умолчанию: mtproto)"
        exit 0
        ;;
esac

# ─── Основной поток: установка ───────────────────────────────

print_header
check_root

SERVER_IP=$(detect_ip)

if [[ "$AUTO_MODE" == true ]]; then
    echo -e "${CYAN}Режим автоматической установки (--auto)${NC}"
fi

echo -e "${CYAN}Обнаруженный IP сервера: ${GREEN}${SERVER_IP}${NC}"

SAVED_SECRET=""
SAVED_DOMAIN=""
if load_config; then
    SAVED_SECRET="$SECRET"
    SAVED_DOMAIN="$FAKE_DOMAIN"
    echo -e "${CYAN}Найдена предыдущая конфигурация (${CONFIG_FILE})${NC}"
fi

echo ""
if [[ "$AUTO_MODE" == false ]]; then
    echo -e "${BOLD}Настройка параметров прокси (Enter — значение по умолчанию):${NC}"
    echo -e "${CYAN}──────────────────────────────────────────────────${NC}"
fi

prompt_value SERVER_IP      "  IP сервера"                      "${MT_SERVER_IP:-$SERVER_IP}"
prompt_value EXT_PORT       "  Внешний порт"                    "${MT_PORT:-${EXT_PORT:-443}}"
prompt_value INTERNAL_PORT  "  Внутренний порт контейнера"      "${INTERNAL_PORT:-3128}"
prompt_value FAKE_DOMAIN    "  Домен маскировки (fake-tls)"     "${MT_DOMAIN:-${FAKE_DOMAIN:-apple.com}}"
prompt_value DNS_SERVER     "  DNS сервер"                      "${MT_DNS:-${DNS_SERVER:-1.1.1.1}}"
prompt_value IP_PREFER      "  Режим IP (prefer-ipv4/prefer-ipv6/only-ipv4/only-ipv6)" "${MT_IP_MODE:-${IP_PREFER:-prefer-ipv4}}"
prompt_value CONTAINER_NAME "  Имя контейнера"                  "${MT_CONTAINER:-${CONTAINER_NAME:-mtproto}}"

echo ""
echo -e "${CYAN}──────────────────────────────────────────────────${NC}"

# ─── Проверка порта ──────────────────────────────────────────

check_port_available "$EXT_PORT"

# ─── Валидация домена ────────────────────────────────────────

validate_domain "$FAKE_DOMAIN"

# ─── Обновление системы ──────────────────────────────────────

echo -e "${CYAN}➜ Обновление системы...${NC}"
if command -v apt-get &>/dev/null; then
    apt-get update -qq && apt-get upgrade -y -qq
elif command -v yum &>/dev/null; then
    yum update -y -q
elif command -v dnf &>/dev/null; then
    dnf upgrade -y -q
fi
echo -e "${GREEN}✓ Система обновлена${NC}"

install_docker

echo -e "${CYAN}➜ Загрузка образа nineseconds/mtg...${NC}"
docker pull nineseconds/mtg
echo -e "${GREEN}✓ Образ загружен${NC}"

# ─── Секрет: переиспользование или генерация нового ──────────

REUSE_SECRET=false
if [[ -n "$SAVED_SECRET" ]]; then
    if [[ "$FAKE_DOMAIN" == "$SAVED_DOMAIN" ]]; then
        echo ""
        echo -e "${CYAN}Найден сохранённый секрет от предыдущей установки.${NC}"
        if prompt_yes_no "  Использовать существующий секрет? (клиентские ссылки не изменятся)" "y"; then
            SECRET="$SAVED_SECRET"
            REUSE_SECRET=true
        fi
    else
        echo ""
        echo -e "${YELLOW}Домен маскировки изменился (${SAVED_DOMAIN} → ${FAKE_DOMAIN}), нужен новый секрет.${NC}"
    fi
fi

if [[ "$REUSE_SECRET" == false ]]; then
    echo -e "${CYAN}➜ Генерация секрета для домена '${FAKE_DOMAIN}'...${NC}"
    SECRET=$(generate_secret "$FAKE_DOMAIN")

    if [[ -z "$SECRET" ]]; then
        echo -e "${RED}Ошибка: не удалось сгенерировать секрет${NC}"
        exit 1
    fi
fi
echo -e "${GREEN}✓ Секрет: ${SECRET}${NC}"

stop_existing_container "$CONTAINER_NAME"

echo -e "${CYAN}➜ Запуск контейнера...${NC}"
docker run -d \
    --name "$CONTAINER_NAME" \
    --restart always \
    -p "${EXT_PORT}:${INTERNAL_PORT}" \
    --dns "$DNS_SERVER" \
    nineseconds/mtg simple-run \
    -n "$DNS_SERVER" \
    -i "$IP_PREFER" \
    "0.0.0.0:${INTERNAL_PORT}" \
    "$SECRET"

if ! wait_for_container "$CONTAINER_NAME"; then
    exit 1
fi

# ─── Проверка соединения ─────────────────────────────────────

verify_proxy_connection "$EXT_PORT"

# ─── Файрвол ─────────────────────────────────────────────────

open_firewall_port "$EXT_PORT"

# ─── Сохранение конфигурации ─────────────────────────────────

save_config
echo -e "${GREEN}✓ Конфигурация сохранена в ${CONFIG_FILE}${NC}"

print_result
