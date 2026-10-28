# Rentify Infrastructure Hub

This directory contains the deployment configuration for Rentify. Production is split across two EC2 hosts, both in the same Security Group.

## Deployment topology

```text
Internet
   |
Edge host (public)
  Caddy · Web · API Gateway · RabbitMQ
   |
   | private network / Security Group
   v
Internal host
  Identity · Tenancy · Payment · Community · AI
```

Docker networks are local to each host. Cross-host communication uses private IPs configured only in the real, untracked env files on the servers.

## Compose stacks

| File | Host | Services |
|---|---|---|
| `docker-compose.edge.yml` | Edge host | `caddy`, `web`, `api-gateway`, `rabbitmq` |
| `docker-compose.internal.yml` | Internal host | `identity`, `tenancy`, optional `payment`, `community` |

Use `scripts/deploy.sh` with `DEPLOY_STACK=edge` or `DEPLOY_STACK=internal`.

## Network rules

The Security Group should allow:

- Edge host: `80` and `5173` from the Internet; `15672` only from team IPs; `5672` only from the internal host.
- Internal host: backend ports `3001–3004` only from the edge host; SSH only from team IPs.
- Never expose `3000`, `3001–3004`, or `5672` publicly.

## Initial server setup

Run on each host:

```bash
git clone <INFRA_REPOSITORY_URL> infra
cd infra
chmod +x scripts/*.sh
sudo ./scripts/setup-swap.sh
./scripts/setup-server.sh
```

Create `.deploy.env` from `.deploy.env.example`:

```bash
cp .deploy.env.example .deploy.env
```

Set the stack per host:

```env
# Edge host
DEPLOY_STACK=edge

# Internal host
DEPLOY_STACK=internal
```

## Edge host configuration

Create these files from their examples:

```bash
cp env/rabbitmq.env.example env/rabbitmq.env
cp env/rabbitmq-users.env.example env/rabbitmq-users.env
cp env/api-gateway.env.example env/api-gateway.env
```

In `env/api-gateway.env`, replace placeholders with the internal host private address:

```env
IDENTITY_SERVICE_URL=http://<INTERNAL_PRIVATE_HOST>:3001
TENANCY_SERVICE_URL=http://<INTERNAL_PRIVATE_HOST>:3002
PAYMENT_SERVICE_URL=http://<INTERNAL_PRIVATE_HOST>:3003
COMMUNITY_SERVICE_URL=http://<INTERNAL_PRIVATE_HOST>:3004
JWKS_URL=http://<INTERNAL_PRIVATE_HOST>:3001/api/v1/.well-known/jwks.json
```

Deploy the edge stack:

```bash
./scripts/deploy.sh
```

RabbitMQ users are synchronized only on this host because RabbitMQ runs here.

## Internal host configuration

Create the required env files:

```bash
cp env/identity.env.example env/identity.env
cp env/tenancy.env.example env/tenancy.env
```

In each service env, set RabbitMQ to the edge host private address:

```env
RABBITMQ_URL=amqp://<service-user>:<password>@<EDGE_PRIVATE_HOST>:5672
```

Deploy Identity and Tenancy:

```bash
./scripts/deploy.sh
```

Optional services are enabled only after their images and env files exist:

```bash
COMPOSE_PROFILES=optional DEPLOY_STACK=internal ./scripts/deploy.sh
```

## Common operations

```bash
# Edge logs
docker compose -f docker-compose.edge.yml logs -f api-gateway
docker compose -f docker-compose.edge.yml logs -f rabbitmq

# Internal logs
docker compose -f docker-compose.internal.yml logs -f identity
docker compose -f docker-compose.internal.yml logs -f tenancy

# Resource usage
docker stats
free -h
```

Deploy one service:

```bash
DEPLOY_STACK=edge ./scripts/deploy.sh api-gateway
DEPLOY_STACK=internal ./scripts/deploy.sh identity
```

## CI/CD targets

- Frontend and API Gateway workflows target the edge host.
- Identity and backend workflows target the internal host and must use `DEPLOY_STACK=internal`.
- Images are built in GitHub Actions and pulled from Docker Hub; do not build images on the 1 GB EC2 hosts.

## Secrets

Never commit `.deploy.env`, `env/*.env`, database URLs, RabbitMQ passwords, JWT keys, or SSH keys. Keep real host addresses in the server-local env files or GitHub Secrets only.
