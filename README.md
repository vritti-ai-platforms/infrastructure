# Infrastructure

Centralized infrastructure configuration for Vritti platform deployment.

## Repository Structure

```
infrastructure/
├── .github/workflows/           # Reusable GitHub Actions workflows
│   ├── build-api.yml           # Build NestJS API services
│   ├── build-microfrontend.yml # Build MF remote apps
│   ├── build-web-container.yml # Build MF host app
│   ├── deploy-docker.yml       # Deploy Docker services
│   └── deploy-static.yml       # Deploy static files
├── docker/
│   ├── docker-compose.yml      # Production compose file
│   └── .env.example            # Environment template
├── dockerfiles/
│   └── Dockerfile.api          # NestJS API services
├── nginx/
│   └── sites-available/        # Nginx site configurations
└── server-vm/
    └── scripts/                # Server setup scripts
```

## Reusable Workflows

### build-api.yml
Builds and pushes NestJS API services to GHCR.

```yaml
jobs:
  build:
    uses: vritti-ai-platforms/infrastructure/.github/workflows/build-api.yml@main
    with:
      service_name: vritti-api-nexus
    secrets: inherit
```

**Inputs:**
| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `service_name` | Yes | - | Service name for the Docker image |
| `dockerfile_path` | No | `./Dockerfile` | Path to Dockerfile |
| `build_context` | No | `.` | Docker build context |
| `node_version` | No | `20` | Node.js version |

**Outputs:**
- `image_tag` - Full image tags that were pushed
- `image_digest` - Image digest
- `short_sha` - Short commit SHA

### build-microfrontend.yml
Builds microfrontend remote applications and uploads as artifacts.

```yaml
jobs:
  build:
    uses: vritti-ai-platforms/infrastructure/.github/workflows/build-microfrontend.yml@main
    with:
      app_name: vritti-auth
      production_domain: https://cloud.vrittiai.com
    secrets: inherit
```

**Inputs:**
| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `app_name` | Yes | - | Microfrontend app name |
| `build_command` | No | `pnpm build` | Build command |
| `output_dir` | No | `dist` | Build output directory |
| `production_domain` | No | `https://cloud.vrittiai.com` | Production URL |

### build-web-container.yml
Builds the Module Federation host application.

```yaml
jobs:
  build:
    uses: vritti-ai-platforms/infrastructure/.github/workflows/build-web-container.yml@main
    with:
      app_name: vritti-web-nexus
      microfrontend_artifacts: '["vritti-auth-abc123"]'
    secrets: inherit
```

### deploy-docker.yml
Deploys Docker services to the server VM.

```yaml
jobs:
  deploy:
    uses: vritti-ai-platforms/infrastructure/.github/workflows/deploy-docker.yml@main
    with:
      service_name: vritti-api
      image_tag: ghcr.io/org/vritti-api-nexus:abc123
      health_check_url: https://cloud.vrittiai.com/health
    secrets:
      SERVER_VM_HOST: ${{ secrets.SERVER_VM_HOST }}
      SERVER_VM_USER: ${{ secrets.SERVER_VM_USER }}
      SERVER_VM_SSH_KEY: ${{ secrets.SERVER_VM_SSH_KEY }}
      GHCR_TOKEN: ${{ secrets.GHCR_TOKEN }}
```

### deploy-static.yml
Deploys static files (frontend builds) to the server.

```yaml
jobs:
  deploy:
    uses: vritti-ai-platforms/infrastructure/.github/workflows/deploy-static.yml@main
    with:
      artifact_name: vritti-web-nexus-abc123
      deploy_path: /opt/vritti/www
    secrets:
      SERVER_VM_HOST: ${{ secrets.SERVER_VM_HOST }}
      SERVER_VM_USER: ${{ secrets.SERVER_VM_USER }}
      SERVER_VM_SSH_KEY: ${{ secrets.SERVER_VM_SSH_KEY }}
```

## Required GitHub Secrets

Configure these in each repository that uses the reusable workflows:

| Secret | Description |
|--------|-------------|
| `SERVER_VM_HOST` | Server VM public IP or hostname |
| `SERVER_VM_USER` | SSH username (e.g., `deploy`) |
| `SERVER_VM_SSH_KEY` | Private SSH key (ed25519) |
| `GHCR_TOKEN` | GitHub PAT with `read:packages` scope |
| `DB_DIRECT_URL` | PostgreSQL admin URL (for migrations) |

## GitHub Variables

| Variable | Description |
|----------|-------------|
| `APP_DOMAIN` | Application domain (e.g., `cloud.vrittiai.com`) |
| `RUN_MIGRATIONS` | Set to `true` to run DB migrations after deploy |

## Server Setup

### 1. Install Docker
```bash
scp server-vm/scripts/install-docker.sh root@<server-ip>:/tmp/
ssh root@<server-ip> 'bash /tmp/install-docker.sh'
```

### 2. Setup Deploy User
```bash
scp server-vm/scripts/setup-deploy-user.sh root@<server-ip>:/tmp/
ssh root@<server-ip> 'bash /tmp/setup-deploy-user.sh'
```

### 3. Generate SSH Key for CI/CD
```bash
ssh-keygen -t ed25519 -C "github-actions-deploy" -f ~/.ssh/vritti-deploy -N ""
cat ~/.ssh/vritti-deploy.pub | ssh root@<server-ip> 'cat >> /home/deploy/.ssh/authorized_keys'
# Add ~/.ssh/vritti-deploy contents to GitHub Secret: SERVER_VM_SSH_KEY
```

### 4. Setup Nginx
```bash
scp server-vm/scripts/setup-nginx.sh root@<server-ip>:/tmp/
scp nginx/sites-available/cloud.vrittiai.com.conf root@<server-ip>:/etc/nginx/sites-available/
ssh root@<server-ip> 'bash /tmp/setup-nginx.sh'
```

### 5. Deploy Docker Compose
```bash
scp docker/docker-compose.yml docker/.env deploy@<server-ip>:/opt/vritti/
ssh deploy@<server-ip> 'cd /opt/vritti && docker compose up -d'
```

## Architecture

```
Server VM (2 CPU, 4GB)              DB VM (2 CPU, 1GB)
┌──────────────────────────┐       ┌──────────────────────────┐
│ Docker Compose           │       │ PostgreSQL 17 (native)   │
│ └─ vritti-api-nexus     │───────│ - Tuned for 1GB RAM      │
│                          │ :5432 │                          │
│ Nginx                    │       │ Backup Service → R2      │
│ - /api/* → backend      │       │                          │
│ - /* → static files     │       └──────────────────────────┘
└──────────────────────────┘
         │
         ▼
┌──────────────────────────┐
│ Cloudflare (DNS/CDN)     │
└──────────────────────────┘
```
