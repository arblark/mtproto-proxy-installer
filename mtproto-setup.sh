#!/bin/bash

set -e

# ─────────────────────────────────────────────────────────────
#  MTProto Proxy — автоматическая установка (nineseconds/mtg)
# ─────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

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

    echo -en "${YELLOW}${description}${NC} [${GREEN}${default}${NC}]: "
    read -r input
    input="${input:-$default}"
    eval "$varname=\"$input\""
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
    local secret
    secret=$(docker run --rm nineseconds/mtg generate-secret --hex "$domain" 2>/dev/null)
    echo "$secret"
}

# ─── Основной поток ──────────────────────────────────────────

print_header
check_root

SERVER_IP=$(detect_ip)
echo -e "${CYAN}Обнаруженный IP сервера: ${GREEN}${SERVER_IP}${NC}"
echo ""
echo -e "${BOLD}Настройка параметров прокси (Enter — значение по умолчанию):${NC}"
echo -e "${CYAN}──────────────────────────────────────────────────${NC}"

prompt_value SERVER_IP      "  IP сервера"                      "$SERVER_IP"
prompt_value EXT_PORT       "  Внешний порт"                    "443"
prompt_value INTERNAL_PORT  "  Внутренний порт контейнера"      "3128"
prompt_value FAKE_DOMAIN    "  Домен маскировки (fake-tls)"     "apple.com"
prompt_value DNS_SERVER     "  DNS сервер"                      "1.1.1.1"
prompt_value IP_PREFER      "  Режим IP (prefer-ipv4/prefer-ipv6/only-ipv4/only-ipv6)" "prefer-ipv4"
prompt_value CONTAINER_NAME "  Имя контейнера"                  "mtproto"

echo ""
echo -e "${CYAN}──────────────────────────────────────────────────${NC}"
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

echo -e "${CYAN}➜ Генерация секрета для домена '${FAKE_DOMAIN}'...${NC}"
SECRET=$(generate_secret "$FAKE_DOMAIN")

if [[ -z "$SECRET" ]]; then
    echo -e "${RED}Ошибка: не удалось сгенерировать секрет${NC}"
    exit 1
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

sleep 2

if docker ps --format '{{.Names}}' | grep -qw "$CONTAINER_NAME"; then
    echo -e "${GREEN}✓ Контейнер '${CONTAINER_NAME}' запущен${NC}"
else
    echo -e "${RED}✗ Контейнер не запустился. Логи:${NC}"
    docker logs "$CONTAINER_NAME"
    exit 1
fi

# ─── Настройка файрвола (если ufw установлен) ────────────────
if command -v ufw &>/dev/null; then
    echo -e "${CYAN}➜ Открываю порт ${EXT_PORT} в UFW...${NC}"
    ufw allow "$EXT_PORT"/tcp &>/dev/null
    echo -e "${GREEN}✓ Порт ${EXT_PORT}/tcp открыт в UFW${NC}"
fi

# ─── Итоги ───────────────────────────────────────────────────
PROXY_LINK="https://t.me/proxy?server=${SERVER_IP}&port=${EXT_PORT}&secret=${SECRET}"

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
echo -e "  ${BOLD}Ссылка для подключения в Telegram:${NC}"
echo ""
echo -e "  ${GREEN}${PROXY_LINK}${NC}"
echo ""
echo -e "${CYAN}──────────────────────────────────────────────────${NC}"
echo -e "  ${BOLD}Полезные команды:${NC}"
echo -e "  Статус:    docker ps | grep ${CONTAINER_NAME}"
echo -e "  Логи:      docker logs -f ${CONTAINER_NAME}"
echo -e "  Стоп:      docker stop ${CONTAINER_NAME}"
echo -e "  Удалить:   docker rm -f ${CONTAINER_NAME}"
echo -e "  Рестарт:   docker restart ${CONTAINER_NAME}"
echo ""
