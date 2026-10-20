#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$ROOT_DIR"

COMPOSE_FILE="docker-compose.prod.yml"

# Services that never talk to RabbitMQ; deploying only these skips the user sync.
SERVICES_WITHOUT_RABBITMQ=(web caddy api-gateway)

needs_rabbitmq_sync() {
    local service skip skip_service
    for service in "$@"; do
        skip=false
        for skip_service in "${SERVICES_WITHOUT_RABBITMQ[@]}"; do
            [ "$service" = "$skip_service" ] && skip=true
        done
        [ "$skip" = false ] && return 0
    done
    return 1
}

if [ "$#" -eq 0 ]; then
    required_files=("env/rabbitmq.env" "env/identity.env" "env/api-gateway.env")
    for required_file in "${required_files[@]}"; do
        if [ ! -f "$required_file" ]; then
            echo "[-] Missing required deployment file: $required_file" >&2
            echo "    Copy its .example file, fill real values, then rerun deploy.sh." >&2
            exit 1
        fi
    done

    echo "[1/5] Kéo (Pull) Docker images mới nhất..."
    docker compose -f "$COMPOSE_FILE" pull

    echo "[2/5] Khởi động lại các container..."
    docker compose -f "$COMPOSE_FILE" up -d --remove-orphans

    echo "[3/5] Đồng bộ user RabbitMQ cho các service..."
    bash "$SCRIPT_DIR/sync-rabbitmq-users.sh"

    echo "[4/5] Dọn dẹp các image cũ (tránh đầy ổ cứng EC2)..."
    docker image prune -f

    echo "[5/5] Trạng thái các container đang chạy:"
    docker compose -f "$COMPOSE_FILE" ps
else
    echo "[1/3] Kéo image cho services: $*"
    docker compose -f "$COMPOSE_FILE" pull "$@"

    echo "[2/3] Khởi động lại services: $*"
    docker compose -f "$COMPOSE_FILE" up -d --no-deps "$@"

    if needs_rabbitmq_sync "$@"; then
        echo "[+] Đồng bộ user RabbitMQ cho các service..."
        bash "$SCRIPT_DIR/sync-rabbitmq-users.sh"
    fi

    echo "[3/3] Dọn dẹp các image cũ..."
    docker image prune -f
    docker compose -f "$COMPOSE_FILE" ps "$@"
fi

echo "=========================================="
echo " [✓] Triển khai thành công!"
echo "=========================================="
