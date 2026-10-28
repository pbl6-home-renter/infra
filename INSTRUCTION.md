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

## 6. Security Group

### Server edge

- Mở `80` và `5173` cho người dùng truy cập.
- Mở `15672` chỉ cho IP của thành viên nhóm.
- Cho phép `5672` từ Security Group của server backend.
- Không mở trực tiếp `3000` ra Internet.

### Server backend

- Cho phép các port backend `3001–3004` chỉ từ Security Group của server edge.
- Mở SSH chỉ cho IP quản trị của nhóm.
- Không mở port backend cho toàn bộ Internet.

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
