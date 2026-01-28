# Infrastructure

Centralized infrastructure configuration for Vritti platform deployment with fully containerized architecture.

## Repository Structure

```
infrastructure/
├── .github/workflows/           # GitHub Actions workflows
│   ├── reusable-build-backend-image.yml # Reusable: Build NestJS API services
│   ├── reusable-build-web.yml           # Reusable: Build web apps (container & MF)
│   ├── reusable-deploy-backend-image.yml # Reusable: Deploy Docker services
│   ├── reusable-deploy-web-build.yml    # Reusable: Deploy static web builds
│   ├── nginx-build.yml                  # Nginx: Build nginx Docker image
│   ├── nginx-deploy.yml                 # Nginx: Deploy nginx container
│   ├── nginx-build-deploy.yml           # Nginx: Build and deploy nginx
│   ├── vm-setup.yml                     # VM: Automated VM setup
│   └── vm-verify.yml                    # VM: Configuration verification
├── docker/
│   ├── docker-compose.yml      # Production compose file
│   └── .env.example            # Environment template
├── dockerfiles/
│   └── Dockerfile.api          # NestJS API services (reference)
├── nginx/
│   ├── Dockerfile              # Nginx container image
│   ├── nginx.conf              # Main Nginx configuration
│   └── conf.d/                 # Server configurations
│       └── default.conf        # Default server config
└── server-vm/
    └── scripts/                # Server setup scripts (idempotent)
```

## Reusable Workflows

### reusable-build-backend-image.yml
Builds and pushes NestJS API services to GHCR.

```yaml
jobs:
  build:
    uses: vritti-ai-platforms/infrastructure/.github/workflows/reusable-build-backend-image.yml@main
    with:
      service_name: api-nexus
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

### reusable-build-web.yml
Unified workflow for building web applications - both Module Federation hosts (containers) and remotes (microfrontends).

#### Container App Example (vritti-web-nexus)
```yaml
jobs:
  build:
    uses: vritti-ai-platforms/infrastructure/.github/workflows/reusable-build-web.yml@main
    with:
      app_type: container
      app_name: vritti-web-nexus
      deploy_path: /
      node_version: '20'
      build_command: pnpm build
      output_dir: dist
    secrets: inherit
```

#### Microfrontend App Example (vritti-auth)
```yaml
jobs:
  build:
    uses: vritti-ai-platforms/infrastructure/.github/workflows/reusable-build-web.yml@main
    with:
      app_type: microfrontend
      app_name: vritti-auth
      deploy_path: /vritti-auth
      node_version: '20'
      build_command: pnpm build
      output_dir: dist
    secrets: inherit
```

**Inputs:**
| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `app_type` | Yes | - | `"container"` (MF host) or `"microfrontend"` (MF remote) |
| `app_name` | Yes | - | Application name (e.g., `vritti-web-nexus`, `vritti-auth`) |
| `deploy_path` | Yes | - | Deploy path relative to `/opt/vritti/www` (e.g., `/` or `/vritti-auth`) |
| `node_version` | No | `20` | Node.js version |
| `build_command` | No | `pnpm build` | Build command |
| `output_dir` | No | `dist` | Build output directory |
| `production_domain` | No | `https://cloud.vrittiai.com` | Production domain URL |
| `microfrontend_artifacts` | No | `[]` | JSON array of MF artifacts to merge (container only) |

**Outputs:**
- `artifact_name` - Name of the uploaded artifact
- `short_sha` - Short commit SHA

**How it works:**
- **Container apps**: Verifies `index.html` exists, can merge microfrontend artifacts
- **Microfrontend apps**: Checks for `mf-manifest.json` (informational), standalone build

### reusable-deploy-backend-image.yml
Deploys Docker services to the server VM.

```yaml
jobs:
  deploy:
    uses: vritti-ai-platforms/infrastructure/.github/workflows/reusable-deploy-backend-image.yml@main
    with:
      service_name: api-nexus
      image_tag: ghcr.io/org/api-nexus:abc123
      health_check_url: https://cloud.vrittiai.com/health
    secrets:
      SERVER_VM_HOST: ${{ secrets.SERVER_VM_HOST }}
      SERVER_VM_USER: ${{ secrets.SERVER_VM_USER }}
      SERVER_VM_SSH_KEY: ${{ secrets.SERVER_VM_SSH_KEY }}
      GHCR_TOKEN: ${{ secrets.GHCR_TOKEN }}
```

### reusable-deploy-web-build.yml
Deploys static web builds to the server.

```yaml
jobs:
  deploy:
    uses: vritti-ai-platforms/infrastructure/.github/workflows/reusable-deploy-web-build.yml@main
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

## Containerized Architecture

### Key Features
- **Fully Dockerized**: Nginx and all services run in Docker containers
- **Wildcard Subdomains**: Supports `*.vrittiai.com` (any subdomain)
- **Internal Networking**: API not exposed to host, only accessible via Nginx
- **Automated Deployment**: GitHub Actions workflows for complete automation
- **Idempotent Scripts**: Safe to run setup scripts multiple times

### Container Stack
```
nginx (ports 80, 443)
  ├── Serves static files from /opt/vritti/www
  ├── SSL termination (wildcard cert for *.vrittiai.com)
  └── Reverse proxy to api-nexus:3000 (internal network)

api-nexus (port 3000, internal only)
  └── NestJS backend service
```

## Automated Server Setup

### Option 1: Automated Setup (Recommended)

Use the GitHub Actions workflow for fully automated setup:

1. **Configure GitHub Secrets** (in infrastructure repository):
   ```
   SERVER_VM_HOST=<vm-ip-or-hostname>
   SERVER_VM_USER=ubuntu
   SERVER_VM_SSH_KEY=<private-ssh-key>
   PRIMARY_DB_HOST=<database-host>
   PRIMARY_DB_USERNAME=<database-user>
   PRIMARY_DB_PASSWORD=<database-password>
   JWT_SECRET=<jwt-secret>
   COOKIE_SECRET=<cookie-secret>
   ... (see Required GitHub Secrets section)
   ```

2. **Run Setup Workflow**:
   - Go to Actions → Setup Server VM
   - Click "Run workflow"
   - Enter VM host (IP or hostname)
   - Optionally skip Docker install if already present
   - Choose whether to deploy services after setup

3. **What Gets Automated**:
   - ✅ Docker Engine installation
   - ✅ Deploy user configuration
   - ✅ Directory structure creation
   - ✅ docker-compose.yml deployment
   - ✅ Environment variables (.env file)
   - ✅ Optionally: Nginx and API deployment

4. **Verify Setup**:
   ```bash
   # Manually run verification, or use workflow
   # Actions → Verify VM Setup → Run workflow
   ```

### Option 2: Manual Setup (Legacy)

For manual setup or troubleshooting:

#### 1. Install Docker
```bash
scp server-vm/scripts/install-docker.sh root@<server-ip>:/tmp/
ssh root@<server-ip> 'sudo bash /tmp/install-docker.sh'
```

#### 2. Setup Deploy User
```bash
scp server-vm/scripts/setup-deploy-user.sh root@<server-ip>:/tmp/
ssh root@<server-ip> 'sudo bash /tmp/setup-deploy-user.sh'
```

#### 3. Generate SSH Key for CI/CD
```bash
ssh-keygen -t ed25519 -C "github-actions-deploy" -f ~/.ssh/vritti-deploy -N ""
cat ~/.ssh/vritti-deploy.pub | ssh ubuntu@<server-ip> 'cat >> ~/.ssh/authorized_keys'
# Add ~/.ssh/vritti-deploy contents to GitHub Secret: SERVER_VM_SSH_KEY
```

#### 4. Upload SSL Certificates
```bash
# Upload wildcard certificate for *.vrittiai.com
scp vrittiai.com.crt ubuntu@<server-ip>:/opt/vritti/ssl/
scp vrittiai.com.key ubuntu@<server-ip>:/opt/vritti/ssl/
```

#### 5. Deploy Docker Compose
```bash
scp docker/docker-compose.yml ubuntu@<server-ip>:/opt/vritti/
# Create .env file manually or use vm-setup workflow
ssh ubuntu@<server-ip> 'cd /opt/vritti && docker compose up -d'
```

## Nginx Deployment

### Automated (Recommended)
Nginx configuration changes trigger automatic deployment:
- Edit files in `nginx/` directory
- Commit and push to main branch
- Workflow automatically builds, pushes, and deploys new image

### Manual
```bash
# Build image
cd infrastructure/nginx
docker build -t ghcr.io/org/nginx:latest .

# Push to registry
docker push ghcr.io/org/nginx:latest

# Deploy on server
ssh ubuntu@<server-ip> 'cd /opt/vritti && docker compose pull nginx && docker compose up -d nginx'
```

## Architecture

### System Overview

```
Server VM (2 CPU, 4GB)              DB VM (2 CPU, 1GB)
┌──────────────────────────┐       ┌──────────────────────────┐
│ Docker Compose Stack     │       │ PostgreSQL 17 (native)   │
│                          │       │ - Tuned for 1GB RAM      │
│ ┌────────────────────┐   │       │                          │
│ │ nginx              │   │       │ Backup Service → R2      │
│ │ - Ports: 80, 443   │   │       │                          │
│ │ - Static files     │   │       └──────────────────────────┘
│ │ - SSL termination  │   │                 ▲
│ └────────┬───────────┘   │                 │
│          │ internal      │                 │ :5432
│          │ network       │                 │
│          ▼               │                 │
│ ┌────────────────────┐   │                 │
│ │ api-nexus          │───┼─────────────────┘
│ │ - Port: 3000       │   │
│ │ - Internal only    │   │
│ └────────────────────┘   │
└──────────────────────────┘
         │
         ▼
┌──────────────────────────┐
│ Cloudflare (DNS/CDN)     │
│ *.vrittiai.com           │
└──────────────────────────┘
```

### Wildcard Subdomain Support

The infrastructure supports **any subdomain** under `*.vrittiai.com`:
- `cloud.vrittiai.com` - Main application
- `auth.vrittiai.com` - Authentication microfrontend
- `admin.vrittiai.com` - Admin panel
- Any other subdomain you create

**How it works:**
- Wildcard SSL certificate for `*.vrittiai.com`
- Nginx `server_name *.vrittiai.com vrittiai.com;`
- Dynamic CORS headers: `Access-Control-Allow-Origin: https://$host`
- Credentials enabled for cross-subdomain authentication

### Container Stack

```
┌─────────────────────────────────────────────────────────┐
│ nginx (ports 80, 443)                                   │
│ ├── Volume: /opt/vritti/www → /usr/share/nginx/html:ro │
│ ├── Volume: /opt/vritti/ssl → /etc/nginx/ssl:ro        │
│ ├── Volume: /opt/vritti/logs/nginx → /var/log/nginx    │
│ ├── Serves static files (Module Federation apps)        │
│ ├── SSL termination (wildcard cert *.vrittiai.com)     │
│ └── Reverse proxy to api-nexus:3000 (internal network) │
└─────────────────────────────────────────────────────────┘
                            │
                            ▼ (Docker internal network)
┌─────────────────────────────────────────────────────────┐
│ api-nexus (port 3000, internal only)                    │
│ ├── Volume: /opt/vritti/logs/api → /app/logs           │
│ ├── NOT exposed to host (no port mapping)              │
│ ├── Only accessible via nginx                           │
│ └── NestJS backend service                              │
└─────────────────────────────────────────────────────────┘
```

### Request Flow

```
User (any subdomain)
    │
    ▼
https://*.vrittiai.com
    │
    ▼
Cloudflare (DNS/CDN, DDoS protection)
    │
    ▼
Server VM (210.79.129.244)
    │
    ├─→ Port 80 (HTTP) ──→ nginx:80
    │                      └─→ 301 Redirect to HTTPS
    │
    └─→ Port 443 (HTTPS) ─→ nginx:443
            │
            ├─→ / ────────────────────→ Static files (/usr/share/nginx/html/)
            │                           Serves: vritti-web-nexus (container)
            │
            ├─→ /vritti-auth/* ───────→ Static files (/usr/share/nginx/html/vritti-auth/)
            │                           Serves: vritti-auth (microfrontend)
            │
            ├─→ /api/* ───────────────→ Reverse proxy to http://api-nexus:3000
            │                           (Docker internal network)
            │                           Path rewrite: /api/users → /users
            │
            ├─→ /static/* ────────────→ Static assets (cached 1 year, CORS enabled)
            │
            ├─→ /mf-manifest.json ────→ Module Federation manifest (cached 5 min)
            │
            ├─→ /health ──────────────→ Proxy to api-nexus:3000/health
            │
            └─→ /** ──────────────────→ SPA fallback (serves index.html)
                                        For client-side routing
```

### Key Features

- **Fully Dockerized**: All services run in containers, no native installations
- **Wildcard Subdomains**: Supports any subdomain under `*.vrittiai.com`
- **Internal Networking**: API not exposed to host, only accessible via Nginx
- **Automated Deployment**: Configuration changes trigger automatic rebuilds
- **Zero-Downtime Updates**: Rolling updates via Docker Compose
- **Health Checks**: Built-in health monitoring for all containers
- **Secure by Default**: SSL/TLS only, secure file permissions, credential-based CORS
