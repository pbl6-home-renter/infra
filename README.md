# Rentify Infrastructure Hub (`infra`)

Kho lưu trữ điều phối trung tâm và hạ tầng triển khai (Orchestration & Infrastructure) cho hệ thống **Rentify (PBL6)** trên **AWS EC2 `t3.micro`**.

---

## 🏛️ Kiến trúc triển khai

```text
               Internet (Client / Web / Mobile)
                              │
                    ┌─────────▼─────────┐
                    │  Port 80 · 5173   │
                    │       Caddy       │
                    └────┬─────────┬────┘
                :80 (API)│         │:5173 (Web)
                         ▼         ▼   (Docker network: rentify-net)
              ┌──────────────┐  ┌──────────────┐
              │ api-gateway  │  │     web      │
              │ (Port 3000)  │  │ (Port 5173)  │
              └──────┬───────┘  └──────────────┘
                     ▼
              ┌──────────────┐     ┌──────────────┐
              │   identity   │ ──► │   rabbitmq   │
              │ (Port 3001)  │     │    (5672)    │
              └──────┬───────┘     └──────────────┘
                     ▼
          Supabase PostgreSQL (Cloud)
```

Hiện tại chỉ demo bằng IP (HTTP, chưa có domain/HTTPS):

| URL | Đích |
|-----|------|
| `http://<EC2_PUBLIC_IP>` | `api-gateway` (API) |
| `http://<EC2_PUBLIC_IP>:5173` | `web` (Frontend) |

* **Caddy:** Điểm đón duy nhất từ Internet. Port 80 → API gateway, port 5173 → web. Web và API tách rời: FE tự cấu hình URL gọi API (`VITE_API_BASE_URL` lúc build).
* **API Gateway:** Xác thực access token RS256 qua JWKS của Identity, rate limit, rồi route tới các backend service.
* **Frontend Web:** Image `${DOCKERHUB_USERNAME}/pbl6-web`, static SPA chạy nội bộ tại port 5173.
* **Identity Service:** Chỉ nằm trong mạng nội bộ `rentify-net`, không publish port ra ngoài.
* **RabbitMQ:** Broker nội bộ. AMQP (5672) chỉ trong Docker network; Management UI (15672) chỉ bind `127.0.0.1` của EC2, truy cập qua SSH tunnel (xem phần vận hành).
* **Supabase:** Managed PostgreSQL trên cloud.

---

## 📁 Cấu trúc thư mục

```text
infra/
├── caddy/
│   └── Caddyfile                # Reverse proxy: :80 → API, :5173 → web
├── env/
│   ├── api-gateway.env.example  # Mẫu biến môi trường cho API Gateway
│   ├── identity.env.example     # Mẫu biến môi trường cho Identity Service
│   ├── rabbitmq.env.example     # Mẫu tài khoản admin RabbitMQ
│   └── rabbitmq-users.env.example # Mẫu user RabbitMQ cho từng service
├── scripts/
│   ├── setup-swap.sh            # Tạo 2GB Swap Memory (chống OOM cho t3.micro)
│   ├── setup-server.sh          # Cài đặt Docker & Docker Compose trên Ubuntu EC2
│   ├── generate-jwt-keys.sh     # Sinh cặp key RS256 cho Identity Service
│   ├── sync-rabbitmq-users.sh   # Tạo/cập nhật user RabbitMQ cho từng service (deploy.sh tự gọi)
│   └── deploy.sh                # Script kéo image mới và reload container
├── docker-compose.prod.yml      # File cấu hình chạy toàn bộ services trên EC2
├── .gitignore                   # Chặn commit secret (env/*.env, .env, *.pem)
└── README.md
```

---

## 🚀 Hướng dẫn triển khai EC2 từ đầu (Runbook)

### Bước 1: Mở Port trên AWS Security Group
Đảm bảo Instance EC2 của bạn đã được gắn Security Group mở các Inbound rules:
* **SSH (Port 22):** IP của bạn (hoặc `0.0.0.0/0`)
* **API (Port 80):** `0.0.0.0/0`
* **Frontend Web (Port 5173):** `0.0.0.0/0` (hoặc chỉ IP cần demo)

Không mở `5672`, `15672`, `3000`, `3001` ra Internet.

### Bước 2: SSH vào máy EC2
Sử dụng file key `rentify-key.pem`:
```bash
chmod 400 rentify-key.pem
ssh -i rentify-key.pem ubuntu@<IP_PUBLIC_EC2>
```

### Bước 3: Cài đặt môi trường ban đầu
Trên terminal của EC2:
```bash
# 1. Clone repo infra về thư mục home
git clone https://github.com/pbl6-home-renter/infra.git
cd infra

# 2. Cấp quyền thực thi cho các script
chmod +x scripts/*.sh

# 3. Tạo 2GB Swap Memory (BẮT BUỘC để t3.micro không bị tràn RAM)
sudo ./scripts/setup-swap.sh

# 4. Cài đặt Docker và Docker Compose
./scripts/setup-server.sh

# 5. Đăng xuất và đăng nhập lại SSH để nhận nhóm docker
exit
ssh -i rentify-key.pem ubuntu@<IP_PUBLIC_EC2>
cd infra
```

### Bước 4: Cấu hình biến môi trường
Tạo các file env thật từ các file mẫu:
```bash
cp env/rabbitmq.env.example env/rabbitmq.env
cp env/rabbitmq-users.env.example env/rabbitmq-users.env
cp env/identity.env.example env/identity.env
cp env/api-gateway.env.example env/api-gateway.env
```

Sinh cặp key JWT (RS256) cho Identity Service:
```bash
cd /tmp && ~/infra/scripts/generate-jwt-keys.sh
```
Script in ra 2 dòng `JWT_PRIVATE_KEY=...` và `JWT_PUBLIC_KEY=...` (đã ở dạng một dòng với `\n`). Dán đè 2 dòng placeholder trong `env/identity.env`, sau đó xoá `/tmp/private.pem` và `/tmp/public.pem`.

Mở từng file bằng `nano` để điền thông tin thật:
* `env/rabbitmq.env`: Điền user/pass **admin** của RabbitMQ (dùng để vào Management UI). RabbitMQ chỉ đọc file này **một lần** khi tạo volume lần đầu.
* `env/rabbitmq-users.env`: Mỗi service một dòng `<username>=<password>`. `deploy.sh` tự tạo user, đặt lại password và cấp quyền theo file này. Nên dùng password chỉ gồm chữ và số (`openssl rand -hex 24`).
* `env/identity.env`: Điền `DATABASE_URL` Supabase, `RABBITMQ_URL=amqp://identity-service:<password>@rabbitmq:5672` (đúng password của dòng `identity-service` trong `rabbitmq-users.env`) và 2 JWT key ở trên. `JWT_ISSUER`/`JWT_AUDIENCE` phải khớp với `env/api-gateway.env`.
* `env/api-gateway.env`: Thường giữ nguyên mặc định; chỉnh rate limit nếu cần.

> Tuỳ chọn: tạo file `.env` ở thư mục gốc để ghi đè `DOCKERHUB_USERNAME` (mặc định `baocules`) hoặc `IMAGE_TAG` (mặc định `latest`). Không có file này hệ thống vẫn chạy.

### Bước 5: Khởi động hệ thống
```bash
./scripts/deploy.sh
```

Kiểm tra: `curl http://<EC2_PUBLIC_IP>/health` trả `{"status":"ok",...}` và mở `http://<EC2_PUBLIC_IP>:5173` thấy trang web.

Frontend được pull từ Docker Hub bằng image public `baocules/pbl6-web:latest`. Sau khi image mới được publish, chạy lại `./scripts/deploy.sh` để cập nhật service `web` và Caddy.

### Tự động deploy FE sau khi push

Workflow trong repo `fe` sẽ tự động build, push image `baocules/pbl6-web:latest` và SSH vào EC2 để chạy `bash scripts/deploy.sh web caddy`.

Cấu hình các GitHub Actions secrets trong repo FE:

* `DOCKERHUB_USERNAME`
* `DOCKERHUB_TOKEN`
* `EC2_HOST`
* `EC2_USER` (tuỳ chọn, mặc định `ubuntu`)
* `EC2_SSH_KEY`

Job deploy chỉ pull và restart `web`/`caddy`, không restart các service backend khác. Không truyền tham số cho `deploy.sh` nếu muốn triển khai toàn bộ hệ thống.

---

## 🛠️ Các lệnh vận hành thường dùng

* **Xem log thời gian thực của một service:**
  ```bash
  docker compose -f docker-compose.prod.yml logs -f identity
  docker compose -f docker-compose.prod.yml logs -f rabbitmq
  docker compose -f docker-compose.prod.yml logs -f caddy
  docker compose -f docker-compose.prod.yml logs -f web
  ```
* **Khởi động lại một service cụ thể:**
  ```bash
  docker compose -f docker-compose.prod.yml restart identity
  ```
* **Dừng toàn bộ hệ thống:**
  ```bash
  docker compose -f docker-compose.prod.yml down
  ```
* **Mở RabbitMQ Management UI (qua SSH tunnel, chạy trên máy cá nhân):**
  ```bash
  ssh -i rentify-key.pem -L 15672:127.0.0.1:15672 ubuntu@<IP_PUBLIC_EC2>
  # rồi mở http://localhost:15672
  ```
* **Thêm user RabbitMQ cho service mới / đổi password:** sửa `env/rabbitmq-users.env`, sửa `RABBITMQ_URL` trong env của service đó, rồi chạy:
  ```bash
  bash scripts/sync-rabbitmq-users.sh            # chỉ đồng bộ user
  bash scripts/deploy.sh <service>               # tạo lại container để nhận RABBITMQ_URL mới
  docker exec rabbitmq rabbitmqctl list_users    # kiểm tra
  ```
  Script không xoá user nào. Muốn xoá: `docker exec rabbitmq rabbitmqctl delete_user <username>`.
* **Kiểm tra mức sử dụng RAM & CPU hiện tại:**
  ```bash
  docker stats
  free -h
  ```

