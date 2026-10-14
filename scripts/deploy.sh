#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$ROOT_DIR"

if [ ! -f "env/rabbitmq.env" ]; then
    echo "[!] Đang khởi tạo env/rabbitmq.env từ example..."
    cp env/rabbitmq.env.example env/rabbitmq.env
fi

if [ ! -f "env/identity.env" ]; then
    echo "[!] Đang khởi tạo env/identity.env từ example..."
    cp env/identity.env.example env/identity.env
fi

echo "[1/4] Kéo (Pull) Docker images mới nhất..."
docker compose -f docker-compose.prod.yml pull

echo "[2/4] Khởi động lại các container..."
docker compose -f docker-compose.prod.yml up -d --remove-orphans

echo "[3/4] Dọn dẹp các image cũ (tránh đầy ổ cứng EC2)..."
docker image prune -f

echo "[4/4] Trạng thái các container đang chạy:"
docker compose -f docker-compose.prod.yml ps

echo "=========================================="
echo " [✓] Triển khai thành công!"
echo "=========================================="
