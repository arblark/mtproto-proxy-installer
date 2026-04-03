#!/bin/bash

set -e

# ─────────────────────────────────────────────────────────────
#  MTProto Proxy — автоматическая установка (nineseconds/mtg)
#  Поддержка Fake-TLS и Real-TLS (nginx + Let's Encrypt)
# ─────────────────────────────────────────────────────────────

CONFIG_DIR="/etc/mtproto-proxy"
CONFIG_FILE="${CONFIG_DIR}/config"
MTG_IMAGE="nineseconds/mtg:2"
NGINX_CONF="/etc/nginx/sites-available/mtproto-proxy.conf"
NGINX_CONF_ENABLED="/etc/nginx/sites-enabled/mtproto-proxy.conf"
NGINX_STREAM_CONF="/etc/nginx/modules-enabled/mtproto-stream.conf"
STUB_DIR="/var/www/mtproto-stub"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

AUTO_MODE=false

# ─── Утилиты ─────────────────────────────────────────────────

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

is_valid_ip() {
    local ip="$1"
    [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

detect_ip() {
    local ip="" raw=""
    local services=(
        "https://ifconfig.me"
        "https://api.ipify.org"
        "https://icanhazip.com"
        "https://checkip.amazonaws.com"
        "https://ipinfo.io/ip"
    )

    for svc in "${services[@]}"; do
        raw=$(curl -4 -sf --max-time 5 "$svc" 2>/dev/null | tr -d '[:space:]') || continue
        if is_valid_ip "$raw"; then
            ip="$raw"
            break
        fi
    done

    if [[ -z "$ip" ]]; then
        raw=$(hostname -I 2>/dev/null | awk '{print $1}')
        if is_valid_ip "$raw"; then
            ip="$raw"
        fi
    fi

    echo "${ip:-YOUR_SERVER_IP}"
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

prompt_choice() {
    local varname="$1"
    local description="$2"
    shift 2
    local options=("$@")
    local default="${options[0]}"

    if [[ "$AUTO_MODE" == true ]]; then
        eval "$varname=\"$default\""
        return
    fi

    echo -e "${YELLOW}${description}${NC}"
    local i=1
    for opt in "${options[@]}"; do
        if (( i == 1 )); then
            echo -e "  ${GREEN}${i})${NC} ${opt} ${CYAN}(по умолчанию)${NC}"
        else
            echo -e "  ${GREEN}${i})${NC} ${opt}"
        fi
        (( i++ ))
    done
    echo -en "${YELLOW}  Выбор: ${NC}"
    read -r choice
    choice="${choice:-1}"

    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
        eval "$varname=\"${options[$((choice-1))]}\""
    else
        eval "$varname=\"$default\""
    fi
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

# ─── Конфигурация ────────────────────────────────────────────

save_config() {
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_FILE" <<EOF
TLS_MODE=${TLS_MODE}
SECRET=${SECRET}
FAKE_DOMAIN=${FAKE_DOMAIN}
REAL_DOMAIN=${REAL_DOMAIN}
LE_EMAIL=${LE_EMAIL}
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
        TLS_MODE="${TLS_MODE:-fake}"
        return 0
    fi
    return 1
}

# ─── Установка пакетов ───────────────────────────────────────

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

install_nginx() {
    if command -v nginx &>/dev/null; then
        echo -e "${GREEN}✓ Nginx уже установлен: $(nginx -v 2>&1 | head -1)${NC}"
    else
        echo -e "${CYAN}➜ Установка Nginx...${NC}"
        if command -v apt-get &>/dev/null; then
            apt-get install -y -qq nginx
        elif command -v yum &>/dev/null; then
            yum install -y nginx
        elif command -v dnf &>/dev/null; then
            dnf install -y nginx
        fi
        echo -e "${GREEN}✓ Nginx установлен${NC}"
    fi
    systemctl enable nginx
    systemctl start nginx
}

install_certbot() {
    if command -v certbot &>/dev/null; then
        echo -e "${GREEN}✓ Certbot уже установлен${NC}"
        return
    fi

    echo -e "${CYAN}➜ Установка Certbot...${NC}"
    if command -v apt-get &>/dev/null; then
        apt-get install -y -qq certbot
    elif command -v yum &>/dev/null; then
        yum install -y certbot
    elif command -v dnf &>/dev/null; then
        dnf install -y certbot
    fi
    echo -e "${GREEN}✓ Certbot установлен${NC}"
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

# ─── Docker / контейнер ──────────────────────────────────────

stop_existing_container() {
    local name="$1"
    if docker ps -a --format '{{.Names}}' | grep -qw "$name"; then
        echo -e "${YELLOW}➜ Останавливаю существующий контейнер '${name}'...${NC}"
        docker rm -f "$name" &>/dev/null || true
    fi
}

generate_secret() {
    local domain="$1"
    docker run --rm "$MTG_IMAGE" generate-secret --hex "$domain" 2>&1
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

start_mtg_container_fake() {
    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart always \
        -p "${EXT_PORT}:${INTERNAL_PORT}" \
        --dns "$DNS_SERVER" \
        "$MTG_IMAGE" simple-run \
        -n "$DNS_SERVER" \
        -i "$IP_PREFER" \
        "0.0.0.0:${INTERNAL_PORT}" \
        "$SECRET"
}

start_mtg_container_real() {
    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart always \
        -p "127.0.0.1:${INTERNAL_PORT}:${INTERNAL_PORT}" \
        --dns "$DNS_SERVER" \
        "$MTG_IMAGE" simple-run \
        -n "$DNS_SERVER" \
        -i "$IP_PREFER" \
        "0.0.0.0:${INTERNAL_PORT}" \
        "$SECRET"
}

# ─── Проверки ────────────────────────────────────────────────

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
            echo -e "${YELLOW}⚠ Домен '${domain}' не резолвится.${NC}"
        else
            echo -e "${GREEN}✓ Домен '${domain}' резолвится${NC}"
        fi
    fi
}

validate_domain_points_to_server() {
    local domain="$1"
    local expected_ip="$2"

    echo -e "${CYAN}➜ Проверка DNS: ${domain} → ${expected_ip}...${NC}"

    local resolved_ip=""
    if command -v dig &>/dev/null; then
        resolved_ip=$(dig +short "$domain" A 2>/dev/null | grep -E '^[0-9]+\.' | head -1)
    elif command -v nslookup &>/dev/null; then
        resolved_ip=$(nslookup "$domain" 8.8.8.8 2>/dev/null | awk '/^Address: / { print $2 }' | tail -1)
    elif command -v host &>/dev/null; then
        resolved_ip=$(host "$domain" 2>/dev/null | awk '/has address/ { print $4 }' | head -1)
    fi

    if [[ -z "$resolved_ip" ]]; then
        echo -e "${RED}✗ Домен '${domain}' не резолвится. Направьте A-запись на ${expected_ip}${NC}"
        if [[ "$AUTO_MODE" == true ]]; then
            exit 1
        fi
        if ! prompt_yes_no "  Продолжить всё равно? (Let's Encrypt не выдаст сертификат)" "n"; then
            exit 1
        fi
        return 1
    fi

    if [[ "$resolved_ip" != "$expected_ip" ]]; then
        echo -e "${YELLOW}⚠ Домен '${domain}' указывает на ${resolved_ip}, а не на ${expected_ip}${NC}"
        if [[ "$AUTO_MODE" == true ]]; then
            echo -e "${RED}Ошибка: DNS не совпадает (авто-режим)${NC}"
            exit 1
        fi
        if ! prompt_yes_no "  Продолжить? (Let's Encrypt может не выдать сертификат)" "n"; then
            exit 1
        fi
        return 1
    fi

    echo -e "${GREEN}✓ Домен '${domain}' корректно указывает на ${expected_ip}${NC}"
    return 0
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

# ─── Real-TLS: nginx + certbot ───────────────────────────────

obtain_certificate() {
    local domain="$1"
    local email="$2"

    echo -e "${CYAN}➜ Получение сертификата Let's Encrypt для '${domain}'...${NC}"

    systemctl stop nginx 2>/dev/null || true

    certbot certonly \
        --standalone \
        --preferred-challenges http \
        -d "$domain" \
        --email "$email" \
        --agree-tos \
        --non-interactive \
        --keep-until-expiring

    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        echo -e "${RED}✗ Не удалось получить сертификат. Проверьте:${NC}"
        echo -e "  - Домен ${domain} указывает на IP этого сервера"
        echo -e "  - Порт 80 открыт и не занят"
        systemctl start nginx 2>/dev/null || true
        exit 1
    fi

    echo -e "${GREEN}✓ Сертификат получен: /etc/letsencrypt/live/${domain}/fullchain.pem${NC}"
}

configure_nginx_real_tls() {
    local domain="$1"
    local mtg_port="$2"

    echo -e "${CYAN}➜ Настройка Nginx (Real-TLS)...${NC}"

    rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

    cat > "$NGINX_CONF" <<NGINXEOF
server {
    listen 80;
    listen [::]:80;
    server_name ${domain};

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 8443 ssl http2;
    listen [::]:8443 ssl http2;
    server_name ${domain};

    ssl_certificate /etc/letsencrypt/live/${domain}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${domain}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    root ${STUB_DIR};
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
NGINXEOF

    if [[ -d /etc/nginx/sites-enabled ]]; then
        ln -sf "$NGINX_CONF" "$NGINX_CONF_ENABLED"
    fi

    local stream_dir="/etc/nginx/modules-enabled"
    if [[ ! -d "$stream_dir" ]]; then
        stream_dir="/etc/nginx/conf.d"
    fi

    cat > "${stream_dir}/mtproto-stream.conf" <<STREAMEOF
stream {
    upstream mtproto_backend {
        server 127.0.0.1:${mtg_port};
    }

    upstream web_backend {
        server 127.0.0.1:8443;
    }

    map \$ssl_preread_server_name \$backend {
        ${domain}    web_backend;
        default      mtproto_backend;
    }

    server {
        listen 443;
        listen [::]:443;
        proxy_pass \$backend;
        ssl_preread on;
    }
}
STREAMEOF

    if ! grep -q "load_module.*ngx_stream_module" /etc/nginx/nginx.conf 2>/dev/null; then
        if [[ -f /usr/lib/nginx/modules/ngx_stream_module.so ]] || [[ -f /usr/lib64/nginx/modules/ngx_stream_module.so ]]; then
            local module_path="/usr/lib/nginx/modules/ngx_stream_module.so"
            [[ -f /usr/lib64/nginx/modules/ngx_stream_module.so ]] && module_path="/usr/lib64/nginx/modules/ngx_stream_module.so"

            if ! grep -q "stream" /etc/nginx/nginx.conf 2>/dev/null; then
                sed -i "1i load_module ${module_path};" /etc/nginx/nginx.conf
            fi
        fi
    fi

    if grep -q "^stream {" /etc/nginx/nginx.conf 2>/dev/null; then
        echo -e "${YELLOW}⚠ Обнаружен блок stream в nginx.conf — возможен конфликт. Проверьте вручную.${NC}"
    fi

    nginx -t 2>&1
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}✗ Ошибка конфигурации Nginx. Проверьте:${NC}"
        echo -e "  ${NGINX_CONF}"
        echo -e "  ${stream_dir}/mtproto-stream.conf"
        exit 1
    fi

    systemctl restart nginx
    echo -e "${GREEN}✓ Nginx настроен и перезапущен${NC}"
}

create_stub_website() {
    local domain="$1"

    echo -e "${CYAN}➜ Создание сайта-заглушки...${NC}"
    mkdir -p "$STUB_DIR"

    cat > "${STUB_DIR}/index.html" <<'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Welcome</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #0f172a;
            color: #e2e8f0;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .container {
            text-align: center;
            padding: 2rem;
        }
        h1 {
            font-size: 2.5rem;
            font-weight: 700;
            background: linear-gradient(135deg, #60a5fa, #a78bfa);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            margin-bottom: 1rem;
        }
        p {
            font-size: 1.1rem;
            color: #94a3b8;
            max-width: 480px;
            line-height: 1.6;
        }
        .status {
            margin-top: 2rem;
            padding: 0.75rem 1.5rem;
            background: rgba(96, 165, 250, 0.1);
            border: 1px solid rgba(96, 165, 250, 0.2);
            border-radius: 8px;
            display: inline-block;
            font-size: 0.9rem;
            color: #60a5fa;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Service Online</h1>
        <p>This server is operational. All systems are running normally.</p>
        <div class="status">Status: Active</div>
    </div>
</body>
</html>
HTMLEOF

    echo -e "${GREEN}✓ Сайт-заглушка создан: ${STUB_DIR}/index.html${NC}"
}

setup_certbot_renewal() {
    echo -e "${CYAN}➜ Настройка автообновления сертификата...${NC}"

    local renew_hook="systemctl reload nginx"
    local cron_line="0 3 * * * certbot renew --quiet --deploy-hook \"${renew_hook}\""

    if ! crontab -l 2>/dev/null | grep -q "certbot renew"; then
        (crontab -l 2>/dev/null; echo "$cron_line") | crontab -
        echo -e "${GREEN}✓ Автообновление сертификата настроено (cron, 3:00)${NC}"
    else
        echo -e "${GREEN}✓ Автообновление сертификата уже настроено${NC}"
    fi
}

remove_nginx_real_tls() {
    rm -f "$NGINX_CONF" "$NGINX_CONF_ENABLED" 2>/dev/null || true

    local stream_dir="/etc/nginx/modules-enabled"
    [[ ! -d "$stream_dir" ]] && stream_dir="/etc/nginx/conf.d"
    rm -f "${stream_dir}/mtproto-stream.conf" 2>/dev/null || true

    nginx -t &>/dev/null && systemctl reload nginx 2>/dev/null || true
}

# ─── Файрвол ─────────────────────────────────────────────────

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

# ─── Вывод результата ────────────────────────────────────────

print_qr_code() {
    local link="$1"

    if install_qrencode; then
        echo -e "  ${BOLD}QR-код (наведите камеру телефона):${NC}"
        echo ""
        qrencode -t ANSIUTF8 "$link"
        echo ""
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
    echo -e "  ${BOLD}Режим:${NC}       ${TLS_MODE^^}"
    echo -e "  ${BOLD}Сервер:${NC}      ${SERVER_IP}"
    echo -e "  ${BOLD}Порт:${NC}        ${EXT_PORT}"
    echo -e "  ${BOLD}Секрет:${NC}      ${SECRET}"
    if [[ "$TLS_MODE" == "real" ]]; then
        echo -e "  ${BOLD}Домен:${NC}       ${REAL_DOMAIN}"
        echo -e "  ${BOLD}Сайт:${NC}        https://${REAL_DOMAIN}"
    else
        echo -e "  ${BOLD}Домен:${NC}       ${FAKE_DOMAIN} (fake-tls)"
    fi
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
    echo -e "  Статус:       $0 --status"
    echo -e "  Диагностика:  $0 --doctor"
    echo -e "  Ссылки:       $0 --show"
    echo -e "  Обновить:     $0 --update"
    echo -e "  Удалить:      $0 --uninstall"
    echo ""
}

# ─── Doctor ──────────────────────────────────────────────────

run_doctor() {
    local name="$1"

    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qw "$name"; then
        echo -e "${YELLOW}⚠ Контейнер '${name}' не запущен — doctor недоступен${NC}"
        return 1
    fi

    echo ""
    echo -e "${BOLD}Диагностика mtg (doctor):${NC}"
    echo -e "${CYAN}──────────────────────────────────────────────────${NC}"
    docker exec "$name" /mtg doctor --simple-run \
        -n "$DNS_SERVER" \
        -i "$IP_PREFER" \
        "0.0.0.0:${INTERNAL_PORT}" \
        "$SECRET" 2>&1 || true
    echo -e "${CYAN}──────────────────────────────────────────────────${NC}"

    if [[ "$TLS_MODE" == "real" ]]; then
        echo ""
        echo -e "${BOLD}Диагностика Real-TLS:${NC}"
        echo -e "${CYAN}──────────────────────────────────────────────────${NC}"

        if systemctl is-active --quiet nginx 2>/dev/null; then
            echo -e "  ${GREEN}✓ Nginx: работает${NC}"
        else
            echo -e "  ${RED}✗ Nginx: не запущен${NC}"
        fi

        if [[ -n "$REAL_DOMAIN" ]] && [[ -f "/etc/letsencrypt/live/${REAL_DOMAIN}/fullchain.pem" ]]; then
            local expiry
            expiry=$(openssl x509 -enddate -noout -in "/etc/letsencrypt/live/${REAL_DOMAIN}/fullchain.pem" 2>/dev/null | cut -d= -f2)
            if [[ -n "$expiry" ]]; then
                local exp_epoch now_epoch days_left
                exp_epoch=$(date -d "$expiry" +%s 2>/dev/null)
                now_epoch=$(date +%s)
                if [[ -n "$exp_epoch" ]]; then
                    days_left=$(( (exp_epoch - now_epoch) / 86400 ))
                    if (( days_left > 7 )); then
                        echo -e "  ${GREEN}✓ Сертификат: действителен ещё ${days_left} дн. (до ${expiry})${NC}"
                    elif (( days_left > 0 )); then
                        echo -e "  ${YELLOW}⚠ Сертификат: истекает через ${days_left} дн. (до ${expiry})${NC}"
                    else
                        echo -e "  ${RED}✗ Сертификат: истёк! (${expiry})${NC}"
                    fi
                fi
            fi
        else
            echo -e "  ${RED}✗ Сертификат: не найден${NC}"
        fi

        if [[ -n "$REAL_DOMAIN" ]]; then
            local resolved_ip
            resolved_ip=$(dig +short "$REAL_DOMAIN" A 2>/dev/null | head -1)
            if [[ "$resolved_ip" == "$SERVER_IP" ]]; then
                echo -e "  ${GREEN}✓ DNS: ${REAL_DOMAIN} → ${resolved_ip}${NC}"
            elif [[ -n "$resolved_ip" ]]; then
                echo -e "  ${YELLOW}⚠ DNS: ${REAL_DOMAIN} → ${resolved_ip} (ожидался ${SERVER_IP})${NC}"
            else
                echo -e "  ${RED}✗ DNS: ${REAL_DOMAIN} не резолвится${NC}"
            fi
        fi

        echo -e "${CYAN}──────────────────────────────────────────────────${NC}"
    fi
}

# ─── Команда: --doctor ──────────────────────────────────────

do_doctor() {
    check_root

    if ! load_config; then
        echo -e "${RED}MTProto Proxy не установлен (конфигурация не найдена)${NC}"
        exit 1
    fi

    local name="${CONTAINER_NAME:-mtproto}"
    run_doctor "$name"
    exit 0
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

    echo -e "  ${BOLD}Режим:${NC}       ${TLS_MODE^^}"

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
    if [[ "$TLS_MODE" == "real" ]]; then
        echo -e "  ${BOLD}Домен:${NC}       ${REAL_DOMAIN}"
    else
        echo -e "  ${BOLD}Домен:${NC}       ${FAKE_DOMAIN} (fake-tls)"
    fi
    echo -e "  ${BOLD}DNS:${NC}         ${DNS_SERVER}"
    echo -e "  ${BOLD}Контейнер:${NC}   ${name}"

    echo ""
    echo -e "${CYAN}──────────────────────────────────────────────────${NC}"
    echo -e "  ${BOLD}Ссылки:${NC}"
    echo -e "  ${GREEN}https://t.me/proxy?server=${SERVER_IP}&port=${EXT_PORT}&secret=${SECRET}${NC}"
    echo -e "  ${GREEN}tg://proxy?server=${SERVER_IP}&port=${EXT_PORT}&secret=${SECRET}${NC}"

    if docker ps --format '{{.Names}}' 2>/dev/null | grep -qw "$name"; then
        run_doctor "$name"
    fi

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
    local mode="fake"

    if load_config; then
        name="${CONTAINER_NAME:-mtproto}"
        port="${EXT_PORT}"
        mode="${TLS_MODE:-fake}"
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

    if [[ "$mode" == "real" ]]; then
        echo ""
        echo -e "${BOLD}Компоненты Real-TLS:${NC}"

        if prompt_yes_no "  Удалить конфигурацию Nginx?" "y"; then
            remove_nginx_real_tls
            echo -e "${GREEN}✓ Конфигурация Nginx удалена${NC}"
        fi

        if [[ -n "${REAL_DOMAIN:-}" ]] && [[ -d "/etc/letsencrypt/live/${REAL_DOMAIN}" ]]; then
            if prompt_yes_no "  Удалить сертификат Let's Encrypt для ${REAL_DOMAIN}?" "n"; then
                certbot delete --cert-name "$REAL_DOMAIN" --non-interactive 2>/dev/null || true
                echo -e "${GREEN}✓ Сертификат удалён${NC}"
            fi
        fi

        if [[ -d "$STUB_DIR" ]]; then
            if prompt_yes_no "  Удалить сайт-заглушку (${STUB_DIR})?" "y"; then
                rm -rf "$STUB_DIR"
                echo -e "${GREEN}✓ Сайт-заглушка удалён${NC}"
            fi
        fi
    fi

    if prompt_yes_no "  Удалить Docker-образ ${MTG_IMAGE}?" "n"; then
        docker rmi "$MTG_IMAGE" &>/dev/null || true
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

    echo -e "${CYAN}➜ Обновление образа ${MTG_IMAGE}...${NC}"
    docker pull "$MTG_IMAGE"
    echo -e "${GREEN}✓ Образ обновлён${NC}"

    stop_existing_container "$name"

    echo -e "${CYAN}➜ Перезапуск контейнера с сохранёнными параметрами...${NC}"
    if [[ "$TLS_MODE" == "real" ]]; then
        start_mtg_container_real
    else
        start_mtg_container_fake
    fi

    if wait_for_container "$name"; then
        if [[ "$TLS_MODE" == "real" ]]; then
            systemctl reload nginx 2>/dev/null || true
            echo -e "${GREEN}✓ Nginx перезагружен${NC}"
        fi
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
    --doctor|-d)
        do_doctor
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
        echo "  --status, -s     Показать статус прокси + диагностика"
        echo "  --doctor, -d     Диагностика (проверка связи с Telegram DC)"
        echo "  --show           Показать ссылки для подключения и QR-код"
        echo "  --help, -h       Показать эту справку"
        echo ""
        echo "Переменные окружения (для --auto):"
        echo "  MT_TLS_MODE      Режим: fake или real (по умолчанию: fake)"
        echo "  MT_SERVER_IP     IP сервера (по умолчанию: автоопределение)"
        echo "  MT_PORT          Внешний порт (по умолчанию: 443)"
        echo "  MT_DOMAIN        Домен маскировки / реальный домен"
        echo "  MT_LE_EMAIL      Email для Let's Encrypt (Real-TLS)"
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
SAVED_TLS_MODE=""
if load_config; then
    SAVED_SECRET="$SECRET"
    SAVED_DOMAIN="$FAKE_DOMAIN"
    SAVED_TLS_MODE="$TLS_MODE"
    echo -e "${CYAN}Найдена предыдущая конфигурация (${CONFIG_FILE}), режим: ${TLS_MODE^^}${NC}"
fi

echo ""

# ─── Выбор режима TLS ────────────────────────────────────────

if [[ "$AUTO_MODE" == true ]]; then
    TLS_MODE="${MT_TLS_MODE:-${TLS_MODE:-fake}}"
else
    echo -e "${BOLD}Выберите режим работы:${NC}"
    echo -e "${CYAN}──────────────────────────────────────────────────${NC}"
    echo -e "  ${GREEN}1)${NC} Fake-TLS — стандартный, без реального домена"
    echo -e "  ${GREEN}2)${NC} Real-TLS — nginx + Let's Encrypt + реальный домен"
    echo ""

    local_default="1"
    if [[ "$SAVED_TLS_MODE" == "real" ]]; then
        local_default="2"
    fi

    echo -en "${YELLOW}  Режим [${local_default}]: ${NC}"
    read -r mode_choice
    mode_choice="${mode_choice:-$local_default}"

    if [[ "$mode_choice" == "2" ]]; then
        TLS_MODE="real"
    else
        TLS_MODE="fake"
    fi
fi

echo -e "${CYAN}Режим: ${GREEN}${TLS_MODE^^}${NC}"
echo ""

# ─── Общие параметры ─────────────────────────────────────────

if [[ "$AUTO_MODE" == false ]]; then
    echo -e "${BOLD}Настройка параметров прокси (Enter — значение по умолчанию):${NC}"
    echo -e "${CYAN}──────────────────────────────────────────────────${NC}"
fi

prompt_value SERVER_IP      "  IP сервера"                      "${MT_SERVER_IP:-$SERVER_IP}"
prompt_value EXT_PORT       "  Внешний порт"                    "${MT_PORT:-${EXT_PORT:-443}}"
prompt_value INTERNAL_PORT  "  Внутренний порт контейнера"      "${INTERNAL_PORT:-3128}"
prompt_value DNS_SERVER     "  DNS сервер"                      "${MT_DNS:-${DNS_SERVER:-1.1.1.1}}"
prompt_value IP_PREFER      "  Режим IP (prefer-ipv4/prefer-ipv6/only-ipv4/only-ipv6)" "${MT_IP_MODE:-${IP_PREFER:-prefer-ipv4}}"
prompt_value CONTAINER_NAME "  Имя контейнера"                  "${MT_CONTAINER:-${CONTAINER_NAME:-mtproto}}"

# ─── Параметры режима ────────────────────────────────────────

if [[ "$TLS_MODE" == "real" ]]; then
    prompt_value REAL_DOMAIN "  Домен (должен указывать на этот сервер)" "${MT_DOMAIN:-${REAL_DOMAIN:-}}"
    prompt_value LE_EMAIL    "  Email для Let's Encrypt"                 "${MT_LE_EMAIL:-${LE_EMAIL:-}}"
    FAKE_DOMAIN="${REAL_DOMAIN}"

    if [[ -z "$REAL_DOMAIN" ]]; then
        echo -e "${RED}Ошибка: домен обязателен для Real-TLS${NC}"
        exit 1
    fi
    if [[ -z "$LE_EMAIL" ]]; then
        echo -e "${RED}Ошибка: email обязателен для Let's Encrypt${NC}"
        exit 1
    fi
else
    REAL_DOMAIN=""
    LE_EMAIL=""
    prompt_value FAKE_DOMAIN "  Домен маскировки (fake-tls)" "${MT_DOMAIN:-${FAKE_DOMAIN:-apple.com}}"
fi

echo ""
echo -e "${CYAN}──────────────────────────────────────────────────${NC}"

# ─── Проверки ────────────────────────────────────────────────

if [[ "$TLS_MODE" == "fake" ]]; then
    check_port_available "$EXT_PORT"
    validate_domain "$FAKE_DOMAIN"
else
    validate_domain_points_to_server "$REAL_DOMAIN" "$SERVER_IP"
    check_port_available 80
fi

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

# ─── Установка зависимостей ──────────────────────────────────

install_docker

if [[ "$TLS_MODE" == "real" ]]; then
    install_nginx
    install_certbot
fi

echo -e "${CYAN}➜ Загрузка образа ${MTG_IMAGE}...${NC}"
docker pull "$MTG_IMAGE"
echo -e "${GREEN}✓ Образ загружен${NC}"

# ─── Let's Encrypt (Real-TLS) ────────────────────────────────

if [[ "$TLS_MODE" == "real" ]]; then
    if [[ -f "/etc/letsencrypt/live/${REAL_DOMAIN}/fullchain.pem" ]]; then
        echo -e "${GREEN}✓ Сертификат для ${REAL_DOMAIN} уже существует${NC}"
    else
        open_firewall_port 80
        obtain_certificate "$REAL_DOMAIN" "$LE_EMAIL"
    fi
fi

# ─── Секрет ──────────────────────────────────────────────────

REUSE_SECRET=false
if [[ -n "$SAVED_SECRET" && "$SAVED_TLS_MODE" == "$TLS_MODE" ]]; then
    if [[ "$TLS_MODE" == "fake" && "$FAKE_DOMAIN" == "$SAVED_DOMAIN" ]] || [[ "$TLS_MODE" == "real" ]]; then
        echo ""
        echo -e "${CYAN}Найден сохранённый секрет от предыдущей установки.${NC}"
        if prompt_yes_no "  Использовать существующий секрет? (клиентские ссылки не изменятся)" "y"; then
            SECRET="$SAVED_SECRET"
            REUSE_SECRET=true
        fi
    fi
fi

if [[ "$REUSE_SECRET" == false ]]; then
    local_domain="$FAKE_DOMAIN"
    if [[ "$TLS_MODE" == "real" ]]; then
        local_domain="$REAL_DOMAIN"
    fi
    echo -e "${CYAN}➜ Генерация секрета для домена '${local_domain}'...${NC}"
    SECRET=$(generate_secret "$local_domain")

    if [[ -z "$SECRET" ]]; then
        echo -e "${RED}Ошибка: не удалось сгенерировать секрет${NC}"
        exit 1
    fi
fi
echo -e "${GREEN}✓ Секрет: ${SECRET}${NC}"

# ─── Запуск контейнера ───────────────────────────────────────

stop_existing_container "$CONTAINER_NAME"

echo -e "${CYAN}➜ Запуск контейнера...${NC}"
if [[ "$TLS_MODE" == "real" ]]; then
    start_mtg_container_real
else
    start_mtg_container_fake
fi

if ! wait_for_container "$CONTAINER_NAME"; then
    exit 1
fi

# ─── Nginx (Real-TLS) ────────────────────────────────────────

if [[ "$TLS_MODE" == "real" ]]; then
    create_stub_website "$REAL_DOMAIN"
    configure_nginx_real_tls "$REAL_DOMAIN" "$INTERNAL_PORT"
    setup_certbot_renewal
fi

# ─── Проверка соединения ─────────────────────────────────────

verify_proxy_connection "$EXT_PORT"

# ─── Файрвол ─────────────────────────────────────────────────

open_firewall_port "$EXT_PORT"
if [[ "$TLS_MODE" == "real" ]]; then
    open_firewall_port 80
fi

# ─── Сохранение конфигурации ─────────────────────────────────

save_config
echo -e "${GREEN}✓ Конфигурация сохранена в ${CONFIG_FILE}${NC}"

print_result
