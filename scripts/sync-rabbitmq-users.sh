#!/bin/bash
# Đồng bộ user RabbitMQ cho từng service từ env/rabbitmq-users.env.
# Mỗi dòng trong file: <username>=<password>
#   - user chưa có  -> tạo mới
#   - user đã có    -> đặt lại password theo file
#   - luôn cấp quyền configure/write/read trên vhost "/"
# Chạy lại nhiều lần vẫn an toàn. Không xoá user nào (kể cả admin).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

USERS_FILE="env/rabbitmq-users.env"
CONTAINER="rabbitmq"
VHOST="/"

if [ ! -f "$USERS_FILE" ]; then
    echo "[!] Không có $USERS_FILE, bỏ qua đồng bộ user RabbitMQ."
    exit 0
fi

rmq() {
    docker exec "$CONTAINER" rabbitmqctl "$@"
}

echo "[+] Chờ RabbitMQ sẵn sàng..."
for _ in $(seq 1 30); do
    if docker exec "$CONTAINER" rabbitmq-diagnostics -q check_running >/dev/null 2>&1; then
        break
    fi
    sleep 2
done
if ! docker exec "$CONTAINER" rabbitmq-diagnostics -q check_running >/dev/null 2>&1; then
    echo "[-] RabbitMQ chưa sẵn sàng sau 60 giây." >&2
    exit 1
fi

existing_users="$(rmq -s list_users | awk '{print $1}')"

echo "[+] Đồng bộ user RabbitMQ từ $USERS_FILE..."
line_no=0
# Đọc qua fd 3 để `docker exec` không vô tình nuốt stdin của vòng lặp.
while IFS= read -r line <&3 || [ -n "$line" ]; do
    line_no=$((line_no + 1))
    line="${line%$'\r'}"
    [[ -z "${line//[[:space:]]/}" || "$line" == \#* ]] && continue

    if [[ "$line" != *=* ]]; then
        echo "[-] $USERS_FILE dòng $line_no không hợp lệ (cần <username>=<password>)." >&2
        exit 1
    fi
    user="${line%%=*}"
    pass="${line#*=}"
    if [ -z "$user" ] || [ -z "$pass" ]; then
        echo "[-] $USERS_FILE dòng $line_no thiếu username hoặc password." >&2
        exit 1
    fi

    if grep -qxF -- "$user" <<<"$existing_users"; then
        rmq -q change_password "$user" "$pass" >/dev/null
        echo "    ~ $user: đã cập nhật password"
    else
        rmq -q add_user "$user" "$pass" >/dev/null
        echo "    + $user: đã tạo mới"
    fi
    rmq -q set_permissions -p "$VHOST" "$user" '.*' '.*' '.*' >/dev/null
done 3< "$USERS_FILE"

echo "[✓] Đồng bộ user RabbitMQ xong."
