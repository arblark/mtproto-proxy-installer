#!/bin/bash

set -e

# ─────────────────────────────────────────────────────────────
#  MTProto Proxy — автоматическая установка (nineseconds/mtg)
# ─────────────────────────────────────────────────────────────

CONFIG_DIR="/etc/mtproto-proxy"
CONFIG_FILE="${CONFIG_DIR}/config"

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

prompt_yes_no() {
    local prompt_text="$1"
    local default="${2:-y}"

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
    echo -e "  ${BOLD}Полезные команды:${NC}"
    echo -e "  Статус:     docker ps | grep ${CONTAINER_NAME}"
    echo -e "  Логи:       docker logs -f ${CONTAINER_NAME}"
    echo -e "  Рестарт:    docker restart ${CONTAINER_NAME}"
    echo -e "  Обновить:   $0 --update"
    echo -e "  Удалить:    $0 --uninstall"
    echo ""
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
    --help|-h)
        echo "Использование: $0 [ОПЦИЯ]"
        echo ""
        echo "  (без опций)    Установка / переустановка MTProto Proxy"
        echo "  --update, -U   Обновить образ и перезапустить контейнер"
        echo "  --uninstall, -u  Удалить контейнер, образ и конфигурацию"
        echo "  --help, -h     Показать эту справку"
        exit 0
        ;;
esac

# ─── Основной поток: установка ───────────────────────────────

print_header
check_root

SERVER_IP=$(detect_ip)
echo -e "${CYAN}Обнаруженный IP сервера: ${GREEN}${SERVER_IP}${NC}"

SAVED_SECRET=""
SAVED_DOMAIN=""
if load_config; then
    SAVED_SECRET="$SECRET"
    SAVED_DOMAIN="$FAKE_DOMAIN"
    echo -e "${CYAN}Найдена предыдущая конфигурация (${CONFIG_FILE})${NC}"
fi

echo ""
echo -e "${BOLD}Настройка параметров прокси (Enter — значение по умолчанию):${NC}"
echo -e "${CYAN}──────────────────────────────────────────────────${NC}"

prompt_value SERVER_IP      "  IP сервера"                      "$SERVER_IP"
prompt_value EXT_PORT       "  Внешний порт"                    "${EXT_PORT:-443}"
prompt_value INTERNAL_PORT  "  Внутренний порт контейнера"      "${INTERNAL_PORT:-3128}"
prompt_value FAKE_DOMAIN    "  Домен маскировки (fake-tls)"     "${FAKE_DOMAIN:-apple.com}"
prompt_value DNS_SERVER     "  DNS сервер"                      "${DNS_SERVER:-1.1.1.1}"
prompt_value IP_PREFER      "  Режим IP (prefer-ipv4/prefer-ipv6/only-ipv4/only-ipv6)" "${IP_PREFER:-prefer-ipv4}"
prompt_value CONTAINER_NAME "  Имя контейнера"                  "${CONTAINER_NAME:-mtproto}"

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

open_firewall_port "$EXT_PORT"

save_config
echo -e "${GREEN}✓ Конфигурация сохранена в ${CONFIG_FILE}${NC}"

print_result
