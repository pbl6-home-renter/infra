# Rentify Infrastructure Hub (`infra`)

Kho lưu trữ điều phối trung tâm và hạ tầng triển khai (Orchestration & Infrastructure) cho hệ thống **Rentify (PBL6)** trên **AWS EC2 `t3.micro`**.

---

## 🏛️ Kiến trúc triển khai

```text
               Internet (Client / Web / Mobile)
                              │
                    ┌─────────▼─────────┐
                    │ Port 80/443/5173  │
                    │   Caddy Gateway   │ ◄── Tự động cấp & gia hạn SSL
                    └─────────┬─────────┘
                              │ (Docker Internal Network: rentify-net)
                    ┌─────────┴─────────┐
                    ▼                   ▼
             ┌──────────────┐    ┌──────────────┐
             │      web     │    │   identity    │
             │  (Port 5173) │    │  (Port 3001)  │
             │  (Port 3001) │    │ (5672/15672) │
             └──────┬───────┘    └──────────────┘
                    │
                    ▼
          Supabase PostgreSQL (Cloud)
```

* **Caddy:** Điểm đón từ Internet (port 80, 443 và 5173), tự động xin chứng chỉ HTTPS Let's Encrypt khi dùng domain và điều phối traffic tới service nội bộ.
* **Frontend Web:** Image public `${DOCKERHUB_USERNAME}/pbl6-web:latest`, chạy static SPA nội bộ tại port 5173 và được Caddy proxy ra `http://<EC2_PUBLIC_IP>:5173`.
* **Identity Service:** Chạy độc lập trong container, giao tiếp an toàn qua mạng nội bộ Docker `rentify-net`.
* **RabbitMQ:** Broker nội bộ cho các service giao tiếp async/event-driven.
* **Supabase:** Managed PostgreSQL trên cloud.

---

## 📁 Cấu trúc thư mục

```text
infra/
├── caddy/
│   └── Caddyfile                # Cấu hình reverse proxy & tự động HTTPS
├── env/
│   ├── identity.env.example     # Mẫu biến môi trường cho Identity Service
│   └── rabbitmq.env.example     # Mẫu thông tin đăng nhập RabbitMQ
├── scripts/
│   ├── setup-swap.sh            # Tạo 2GB Swap Memory (chống OOM cho t3.micro)
│   ├── setup-server.sh          # Cài đặt Docker & Docker Compose trên Ubuntu EC2
│   └── deploy.sh                # Script kéo image mới và reload container
├── docker-compose.prod.yml      # File cấu hình chạy toàn bộ services trên EC2
├── .env.example                 # Mẫu cấu hình Docker Registry & Domain
├── .gitignore                   # Chặn commit các file secret (.env)
└── README.md
```

---

## 🚀 Hướng dẫn triển khai EC2 từ đầu (Runbook)

### Bước 1: Mở Port trên AWS Security Group
Đảm bảo Instance EC2 của bạn đã được gắn Security Group mở các Inbound rules:
* **SSH (Port 22):** IP của bạn (hoặc `0.0.0.0/0`)
* **HTTP (Port 80):** `0.0.0.0/0`
* **HTTPS (Port 443):** `0.0.0.0/0`
* **Frontend Web (Port 5173):** mở theo IP cần demo
* **RabbitMQ Dashboard (Port 15672):** IP của bạn (hoặc `0.0.0.0/0` nếu đang test)

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
Tạo các file `.env` thật từ các file mẫu:
```bash
# File cấu hình chung
cp .env.example .env

# File cấu hình từng service
cp env/rabbitmq.env.example env/rabbitmq.env
cp env/identity.env.example env/identity.env
```

Mở từng file bằng `nano` để điền thông tin thật:
* `.env`: Điền `DOCKERHUB_USERNAME` và `APP_DOMAIN`.
* `env/rabbitmq.env`: Điền user/pass cho RabbitMQ.
* `env/identity.env`: Điền `DATABASE_URL` Supabase và connection string RabbitMQ.
* `caddy/Caddyfile`: FE chạy tại `:5173`; domain/HTTPS có thể cấu hình sau.

### Bước 5: Khởi động hệ thống
```bash
./scripts/deploy.sh
```

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
* **Kiểm tra mức sử dụng RAM & CPU hiện tại:**
  ```bash
  docker stats
  free -h
  ```

