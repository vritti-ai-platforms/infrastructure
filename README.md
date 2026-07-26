# Vritti Infrastructure

Infrastructure-as-code for the Vritti platform: OpenTofu for cloud resources, Ansible for VM
provisioning, the self-hosted Infisical stack, and shared container images.

Everything runs under **Infisical** for secrets — wrap tofu and ansible in `infisical run` so
credentials arrive as env vars (nothing is committed; there is no ansible-vault).

## Layout

```
tofu/          OpenTofu — reserved IPs, DNS, Zero-Trust tunnel/Access (network/), VMs (compute/)
ansible/       VM provisioning — vm1 (cloud control plane + dev core) and vm2 (prod core)
infisical/     Self-hosted Infisical stack (app + redis + postgres/pgBackRest + backups)
images/        Shared container images (postgres-pgbackrest)
.github/       CI workflows
```

## How it fits together

- **`tofu/network`** — reserved public IPs, Cloudflare DNS, and the Zero-Trust tunnel + Access
  (GitHub-org SSO) for the admin surfaces (`admin.`/`dblab.`/`git.dev`). Own state, so a compute
  destroy never touches the IPs.
- **`tofu/compute`** — the two VMs (`vritti-vm1`, `vritti-vm2`) on their reserved IPs.
- **`ansible/`** — provisions the VMs. **vm1** = cloud control plane (compose stack) + the dev
  `vritti-core` deployment; **vm2** = the prod `vritti-core` deployment. The core stack itself is
  owned by the **agent** (`vritti-application-agent`), not Ansible. See `ansible/README.md`.
- **`infisical/`** — the secrets manager, deployed by `infisical-deploy.yml` (SSH + compose).
  Backups (pgBackRest → local + R2) are baked into its single `docker-compose.yml`.
- **`images/postgres-pgbackrest`** — the shared Postgres 18.4 + pgBackRest image used by both the
  Infisical stack and the agent-managed core/cloud stacks.

## Workflows (`.github/workflows/`)

| Workflow | Purpose |
|---|---|
| `build-postgres-pgbackrest.yml` | Build + push `ghcr.io/vritti-ai-platforms/postgres-pgbackrest:18.4` |
| `infisical-deploy.yml` | Deploy the Infisical stack to its VM (SSH + compose, idempotent) |
| `reusable-build-backend-image.yml` | Reusable — build a NestJS service image to GHCR (called by app repos) |
| `reusable-build-web.yml` | Reusable — build a web bundle to GHCR (called by app repos) |

## Usage

```bash
# Provision (always via infisical run so state backend + providers get creds)
infisical run -- tofu -chdir=tofu/network apply
infisical run -- tofu -chdir=tofu/compute apply

# Configure the VMs (inventory IPs come from tofu output)
cd ansible
infisical run --projectId 8f447810-a5c7-4a83-a4f3-1a775999edd9 --env prod -- ansible-playbook vm1.yml --tags control-plane
infisical run --projectId 8f447810-a5c7-4a83-a4f3-1a775999edd9 --env prod -- ansible-playbook vm2.yml
```

## Notes

- **Secrets:** all in Infisical (`infrastructure` project, `prod`). Ansible reads them via
  `lookup('env', ...)`; there is no vault file. Customer deployments never route secrets through
  here — the agent generates machine secrets on their VM and decrypts sealed secrets locally.
- The previous single-VM stack (a `docker/` folder + `nginx/` + SSH-script deploys) has been
  **retired** in favor of tofu + ansible + the agent. It lives in git history if ever needed.
