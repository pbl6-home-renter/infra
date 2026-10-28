# Hướng dẫn triển khai Rentify trên hai EC2

## 1. Kiến trúc triển khai

```text
Internet
   |
Server edge/public
  Caddy · Web · API Gateway · RabbitMQ
   |
   | Private IP + Security Group
   v
Server internal/backend
  Identity · Tenancy · Payment · Community · AI
```

Hai server không dùng chung Docker network. Các container giao tiếp khác máy thông qua private IP. IP thật chỉ được cấu hình trong file env trên server, không commit vào repository.

## 2. Các file Compose

| File | Chạy trên | Service |
|---|---|---|
| `docker-compose.edge.yml` | Server edge | `caddy`, `web`, `api-gateway`, `rabbitmq` |
| `docker-compose.internal.yml` | Server backend | `identity`, `tenancy`, `payment`, `community` |

RabbitMQ chỉ chạy trên server edge. Server backend kết nối đến RabbitMQ qua private IP của server edge.

## 3. Cài đặt ban đầu trên mỗi server

```bash
git clone <INFRA_REPOSITORY_URL> infra
cd infra
chmod +x scripts/*.sh
sudo ./scripts/setup-swap.sh
./scripts/setup-server.sh
cp .deploy.env.example .deploy.env
```

Trong `.deploy.env`, đặt đúng stack:

```env
# Server edge
DEPLOY_STACK=edge

# Server backend
DEPLOY_STACK=internal
```

## 4. Cấu hình server edge

Tạo các file môi trường:

```bash
cp env/rabbitmq.env.example env/rabbitmq.env
cp env/rabbitmq-users.env.example env/rabbitmq-users.env
cp env/api-gateway.env.example env/api-gateway.env
```

Trong `env/api-gateway.env`, thay các placeholder bằng private IP của server backend:

```env
IDENTITY_SERVICE_URL=http://<INTERNAL_PRIVATE_HOST>:3001
TENANCY_SERVICE_URL=http://<INTERNAL_PRIVATE_HOST>:3002
PAYMENT_SERVICE_URL=http://<INTERNAL_PRIVATE_HOST>:3003
COMMUNITY_SERVICE_URL=http://<INTERNAL_PRIVATE_HOST>:3004
JWKS_URL=http://<INTERNAL_PRIVATE_HOST>:3001/api/v1/.well-known/jwks.json
```

Deploy toàn bộ edge stack:

```bash
./scripts/deploy.sh
```

RabbitMQ user được đồng bộ trên server edge bằng:

```bash
bash scripts/sync-rabbitmq-users.sh
```

## 5. Cấu hình server backend

Tạo các file môi trường:

```bash
cp env/identity.env.example env/identity.env
cp env/tenancy.env.example env/tenancy.env
```

Trong env của từng service, cấu hình RabbitMQ bằng private IP của server edge:

```env
RABBITMQ_URL=amqp://<service-user>:<password>@<EDGE_PRIVATE_HOST>:5672
```

Deploy Identity và Tenancy:

```bash
./scripts/deploy.sh
```

Các service có profile `optional` chỉ bật sau khi đã có Docker image và file env tương ứng:

```bash
COMPOSE_PROFILES=optional DEPLOY_STACK=internal ./scripts/deploy.sh
```

Server backend không chạy `sync-rabbitmq-users.sh`; RabbitMQ nằm ở server edge.

## 6. Cấu hình AWS Security Group

Hai EC2 đang dùng chung một Security Group. Vì vậy, với các kết nối nội bộ, chọn **Security Group của chính nhóm hiện tại** ở cột `Source`, không nhập public IP hoặc private IP.

Vào AWS Console → **EC2** → **Security Groups** → chọn Security Group đang gắn cho cả hai instance → **Edit inbound rules**.

### Các inbound rule cần có

| Type | Port | Source | Mục đích |
|---|---:|---|---|
| SSH | `22` | IP quản trị của nhóm `/32` | SSH vào server |
| Custom TCP | `80` | `0.0.0.0/0` | Caddy API |
| Custom TCP | `5173` | `0.0.0.0/0` hoặc IP demo | Web frontend |
| Custom TCP | `15672` | IP quản trị của nhóm `/32` | RabbitMQ Management UI |
| Custom TCP | `5672` | Security Group hiện tại | Backend server → RabbitMQ |
| Custom TCP | `3001-3004` | Security Group hiện tại | Edge server → backend services |

### Cách nhập Source là Security Group

Trong màn hình **Edit inbound rules**, với mỗi rule nội bộ:

1. Chọn `Custom TCP`.
2. Nhập port `5672` hoặc `3001-3004`.
3. Ở `Source type`, chọn `Custom`.
4. Ở ô `Source`, nhập và chọn **Security Group ID dạng `sg-...`** của nhóm đang gắn cho cả hai EC2.
5. Kiểm tra chip `sg-...` đã xuất hiện dưới ô Source rồi bấm **Save rules**.

Không dùng Security Group Rule ID dạng `sgr-...`; đó chỉ là ID của từng rule. Không dùng `0.0.0.0/0` cho hai port nội bộ này.

### Lưu ý bảo mật

- Không mở `3000`, `3001–3004`, `5672` hoặc `15672` cho `0.0.0.0/0`.
- Port `3000` chỉ là port nội bộ của API Gateway, Caddy proxy ra port `80`.
- Port `3001–3004` được mở bằng Security Group vì API Gateway ở máy khác cần gọi backend.
- Port `5672` được mở bằng Security Group vì Identity/backend ở server backend cần kết nối RabbitMQ ở server edge.
- Nếu chỉ muốn truy cập Web trong nhóm, thay `0.0.0.0/0` ở port `5173` bằng IP nhóm `/32`.
- Sau khi thêm rule, kiểm tra cả UFW trên Ubuntu nếu đang bật; Security Group cho phép kết nối nhưng UFW vẫn có thể chặn.

### Kiểm tra kết nối từ server backend

Thay `<EDGE_PRIVATE_HOST>` bằng private IP thật trên server:

```bash
nc -vz <EDGE_PRIVATE_HOST> 5672
```

### Kiểm tra kết nối từ server edge

```bash
nc -vz <INTERNAL_PRIVATE_HOST> 3001
nc -vz <INTERNAL_PRIVATE_HOST> 3002
```

Nếu kết nối thành công, kết quả sẽ chứa `succeeded` hoặc `open`. Nếu bị timeout, kiểm tra lại Security Group, private IP và UFW.

## 7. Deploy từng service

Trên server edge:

```bash
DEPLOY_STACK=edge ./scripts/deploy.sh api-gateway
```

Trên server backend:

```bash
DEPLOY_STACK=internal ./scripts/deploy.sh identity
DEPLOY_STACK=internal ./scripts/deploy.sh tenancy
```

## 8. CI/CD

- Workflow của Web và API Gateway deploy vào server edge.
- Workflow của Identity và backend service deploy vào server backend.
- Các workflow backend phải sử dụng `DEPLOY_STACK=internal`.
- Docker image được build trên GitHub Actions rồi pull về EC2; không build image trực tiếp trên server 1 GB RAM.

## 9. Kiểm tra vận hành

```bash
docker stats
free -h
docker compose -f docker-compose.edge.yml logs -f rabbitmq
docker compose -f docker-compose.internal.yml logs -f identity
```

Không commit `.deploy.env`, `env/*.env`, mật khẩu database, mật khẩu RabbitMQ, JWT key hoặc SSH key.
