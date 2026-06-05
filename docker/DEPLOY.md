# Vritti — single-VM deployment (cloud + core)

Both products run on **one VM** behind **one nginx**, with **Postgres native on the
host** and **Redis + NATS** as containers.

```
                        Cloudflare DNS
   cloud./admin.vrittiai.com          *.dev.vrittiai.com
                  │                           │
                  ▼                           ▼
          ┌───────────────── nginx (:80/:443) ─────────────────┐
          │  cloud./admin.* → www/cloud   |  /api → cloud-server:3000
          │  *.dev.*        → www/core    |  /api → core-server:3002
          └─────────────────────────┬──────────────────────────┘
                cloud-server   core-server   commerce-service(NATS worker)
                      │              │              │
                      └──────┬───────┴──────┬───────┘
                             ▼              ▼
                  Postgres (host, native)   Redis + NATS (containers)
```

## Pipelines

| Trigger | Workflow | Does |
|---|---|---|
| Push to `main` (each app repo) | `build.yml` | `nx affected` → push **server images** + **web `.tar.gz`** to GHCR (no VM contact) |
| Manual (infra repo → Actions → **Deploy**) | `deploy.yml` | pick product + target + tag → SSH → pull image(s) + `up -d`, and `oras pull` the web bundle into `www/` |

Nothing reaches the VM on merge — both backend images and web bundles land in GHCR and are shipped only via the manual Deploy. `target` lets you ship `all`, `backend`, or `frontend`.

---

## One-time VM setup

### 1. Directory layout (`/opt/vritti`)
```bash
sudo mkdir -p /opt/vritti/{cloud,core,www/cloud,www/core,ssl,nginx/conf.d,logs/{nginx,cloud,core},letsencrypt,geoip}
sudo chown -R "$USER":"$USER" /opt/vritti
# copy docker-compose.yml to /opt/vritti/docker-compose.yml
# GeoIP DB (cloud-server) is committed in infra docker/geoip/ and scp'd here by the Deploy
#   workflow on cloud backend deploys — no manual upload. Lands at /opt/vritti/geoip/GeoLite2-City.mmdb.
# copy nginx config (mounted into the stock nginx:alpine container):
#   infrastructure/nginx/nginx.conf          -> /opt/vritti/nginx/nginx.conf
#   infrastructure/nginx/conf.d/default.conf -> /opt/vritti/nginx/conf.d/default.conf
```

### 1b. Install oras (pulls web bundles from GHCR)
```bash
VER=1.2.0
curl -sLO "https://github.com/oras-project/oras/releases/download/v${VER}/oras_${VER}_linux_amd64.tar.gz"
mkdir -p oras-install && tar -xzf "oras_${VER}_linux_amd64.tar.gz" -C oras-install
sudo mv oras-install/oras /usr/local/bin/ && rm -rf oras-install "oras_${VER}_linux_amd64.tar.gz"
oras version
```

### 2. Swap — REQUIRED on a 2 GB box
Full core + native Postgres sits ~1.8 GB; swap prevents OOM kills.
```bash
sudo fallocate -l 4G /swapfile && sudo chmod 600 /swapfile
sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
sudo sysctl -w vm.swappiness=10
```

### 3. Native Postgres — accept connections from containers
Containers reach the host as `host.docker.internal` (→ the Docker bridge gateway).
```bash
# postgresql.conf
listen_addresses = '*'           # or 'localhost,172.17.0.1'

# pg_hba.conf — allow the Docker bridge subnet (scram or md5)
host  all  all  172.16.0.0/12  scram-sha-256
```
```bash
sudo systemctl restart postgresql
# create roles, db, schemas
sudo -u postgres psql <<'SQL'
CREATE DATABASE vritti_db;
CREATE USER cloud_user WITH PASSWORD 'CHANGE_ME';
CREATE USER core_user  WITH PASSWORD 'CHANGE_ME';
\c vritti_db
CREATE SCHEMA IF NOT EXISTS cloud       AUTHORIZATION cloud_user;
CREATE SCHEMA IF NOT EXISTS vritti_core AUTHORIZATION core_user;
GRANT ALL ON DATABASE vritti_db TO cloud_user, core_user;
SQL
```

### 4. TLS — one cert covering both wildcards
`*.vrittiai.com` does **not** cover `*.dev.vrittiai.com`, so issue a combined cert
(DNS-01 via Cloudflare — extends the existing `vm-setup.yml` flow):
```bash
sudo certbot certonly --dns-cloudflare \
  --dns-cloudflare-credentials /root/.secrets/cloudflare.ini \
  --dns-cloudflare-propagation-seconds 60 \
  -d vrittiai.com -d '*.vrittiai.com' -d '*.dev.vrittiai.com' \
  --email you@vrittiai.com --agree-tos --non-interactive
sudo cp /etc/letsencrypt/live/vrittiai.com/fullchain.pem /opt/vritti/ssl/vrittiai.com.crt
sudo cp /etc/letsencrypt/live/vrittiai.com/privkey.pem   /opt/vritti/ssl/vrittiai.com.key

# auto-renewal hook — refresh certs into /opt/vritti/ssl and reload nginx on renew
sudo mkdir -p /etc/letsencrypt/renewal-hooks/deploy
sudo tee /etc/letsencrypt/renewal-hooks/deploy/vritti.sh >/dev/null <<'EOF'
#!/bin/bash
cp /etc/letsencrypt/live/vrittiai.com/fullchain.pem /opt/vritti/ssl/vrittiai.com.crt
cp /etc/letsencrypt/live/vrittiai.com/privkey.pem   /opt/vritti/ssl/vrittiai.com.key
docker exec nginx nginx -s reload 2>/dev/null || true
EOF
sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/vritti.sh
```
DNS (Cloudflare): A records `cloud`, `admin`, and `*.dev` → the VM IP.

### 5. Env files on the VM
```bash
# compose interpolation (image tags + redis password)
cat > /opt/vritti/.env <<'EOF'
CLOUD_IMAGE_TAG=latest-main
CORE_IMAGE_TAG=latest-main
REDIS_PASSWORD=CHANGE_ME_REDIS_PASSWORD
EOF
chmod 600 /opt/vritti/.env

# per-stack runtime env (fill in every CHANGE_ME)
cp cloud/.env.example /opt/vritti/cloud/.env   # from infrastructure/docker/cloud/.env.example
cp core/.env.example  /opt/vritti/core/.env
chmod 600 /opt/vritti/cloud/.env /opt/vritti/core/.env
# REDIS_URL passwords in both files must match REDIS_PASSWORD above
# NOTE: only cloud + core get a deploy .env. commerce-service shares core/.env
#       (see service/.env.example for the subset it validates); commerce-mf is a
#       static remote with no env (see mf/.env.example). Nothing to copy for those.
```

### 6. First boot
```bash
cd /opt/vritti
echo "$GHCR_TOKEN" | docker login ghcr.io -u <github-user> --password-stdin
docker compose pull
docker compose up -d
docker compose ps
```

---

## GitHub configuration

**Each app repo** (`vritti-cloud`, `vritti-core`) → Settings → Secrets and variables → Actions:

| Secret | Purpose |
|---|---|
| `SERVER_VM_HOST` | VM public IP/hostname |
| `SERVER_VM_USER` | SSH user (e.g. `ubuntu`) |
| `SERVER_VM_SSH_KEY` | SSH private key (ed25519) |

**infrastructure repo** (for `deploy.yml`): the three above **plus** `GHCR_TOKEN` (PAT with `read:packages`).

Image builds push to `ghcr.io/vritti-ai-platforms/{cloud-server,core-server,commerce-service}`
using the built-in `GITHUB_TOKEN` (no PAT needed for push).

---

## Day-2

- **Ship a backend change:** merge to `main` → image builds automatically → Actions →
  **Deploy** → pick product + tag (`latest-main` or a pinned `X.Y.Z-main`).
- **Ship a frontend change:** merge to `main` → web `.tar.gz` pushed to GHCR → run **Deploy** with `target: frontend` (or `all`) to pull + extract it.
- **Roll back:** run **Deploy** with a previous image tag.
- **Change nginx routing/config:** edit `/opt/vritti/nginx/conf.d/default.conf` on the VM
  (or scp it from `infrastructure/nginx/`), then
  `docker exec nginx nginx -t && docker exec nginx nginx -s reload`. No image rebuild —
  the config is a mounted volume.

## ⚠️ Before you ship — checklist
- **Set `APP_HOST` + `CORS_ORIGINS`** in each VM `.env` — host/CORS are now env-driven and fall
  back to local-dev values when unset. cloud → `APP_HOST=cloud.vrittiai.com`,
  `CORS_ORIGINS=https://cloud.vrittiai.com,https://admin.vrittiai.com`; core → `APP_HOST=dev.vrittiai.com`.
- **Distinct secrets per server** — `JWT_SECRET`, `HMAC_KEY`, `COOKIE_SECRET` must each be a
  *different* ≥32-char random value in cloud vs core (boot now rejects shorter/missing ones).
- After removing the `link:` overrides, **regenerate + commit `pnpm-lock.yaml`** in both repos,
  or the Docker `pnpm install --frozen-lockfile` will fail.

> commerce-service uses the shared `vritti_core` schema (confirmed) — no override needed.
