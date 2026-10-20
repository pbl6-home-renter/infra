#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$ROOT_DIR"

COMPOSE_FILE="docker-compose.prod.yml"

if [ "$#" -eq 0 ]; then
    required_files=("env/rabbitmq.env" "env/identity.env" "env/api-gateway.env")
    for required_file in "${required_files[@]}"; do
        if [ ! -f "$required_file" ]; then
            echo "[-] Missing required deployment file: $required_file" >&2
            echo "    Copy its .example file, fill real values, then rerun deploy.sh." >&2
            exit 1
        fi
    done

    echo "[1/4] Kéo (Pull) Docker images mới nhất..."
    docker compose -f "$COMPOSE_FILE" pull

    echo "[2/4] Khởi động lại các container..."
    docker compose -f "$COMPOSE_FILE" up -d --remove-orphans

    echo "[3/4] Dọn dẹp các image cũ (tránh đầy ổ cứng EC2)..."
    docker image prune -f

    echo "[4/4] Trạng thái các container đang chạy:"
    docker compose -f "$COMPOSE_FILE" ps
else
    echo "[1/3] Kéo image cho services: $*"
    docker compose -f "$COMPOSE_FILE" pull "$@"

    echo "[2/3] Khởi động lại services: $*"
    docker compose -f "$COMPOSE_FILE" up -d --no-deps "$@"

    echo "[3/3] Dọn dẹp các image cũ..."
    docker image prune -f
    docker compose -f "$COMPOSE_FILE" ps "$@"
fi

echo "=========================================="
echo " [✓] Triển khai thành công!"
echo "=========================================="
