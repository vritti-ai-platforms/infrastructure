# Vritti Ansible

Two independent sub-projects, each self-contained (own `ansible.cfg`, `.infisical.json`, static
inventory) and pinned to its own Infisical project. Shared `roles/` at the top.

| Sub-project | Dir | Infisical project | Target | Does |
|---|---|---|---|---|
| **cloud** | `cloud/` | **infrastructure** / `prod` | the ONE fixed cloud control-plane VM | host + cloud compose stack (nginx, cloud-web SPA, cloud-server, pg/redis/nats, DbLab, TLS, cloudflared) |
| **core** | `core/` | **vritti-core** / `<env>` (`/agent`) | ANY agent-hosted core VM (apw1, apw2, cloud dev core…) | bootstrap (base + docker + GHCR login) **and** deploy/enroll the `vritti-application-agent`, in one pass |

The **core stack itself** (pg, redis, nats, core-server, commerce, nginx) is materialized by the
**agent** from cloud's signed desired-state — not by Ansible. `core/site.yml` only preps the host and
starts the agent.

## Layout

```
roles/   base docker zfs tls geoip cloud_stack cloudflared agent      # shared by both sub-projects
requirements.yml

cloud/                       # FIXED cloud VM · infrastructure/prod
  .infisical.json  ansible.cfg
  inventory.yml              # one fixed host; IP from the CLOUD_TARGET_IP secret (no hardcode)
  group_vars/cloud.yml
  site.yml                   # base+docker+zfs+tls+geoip+cloud_stack+cloudflared
  nginx.yml                  # re-render cloud nginx + hot reload (no full redeploy)
  update-cloud-images.yml    # refresh cloud-server image + cloud-web bundle in place

core/                        # REUSABLE core VM · vritti-core/<env> (/agent)
  .infisical.json  ansible.cfg
  inventory.yml              # ONE placeholder host; all per-VM data comes from --env's /agent secrets
  group_vars/core.yml
  site.yml                   # base+docker(GHCR login)+agent
```

There is **no tofu dynamic inventory** and no `group_vars/all.yml` — both sides are static, and every
per-host value comes from Infisical, so Ansible needs no tofu/R2 creds.

## cloud — the fixed control-plane VM

`cloud/.infisical.json` pins **infrastructure / prod**. The single host's IP comes from the
`CLOUD_TARGET_IP` secret, so nothing is hardcoded. Run from `cloud/`:

```bash
ansible-galaxy collection install -r ../requirements.yml    # once
cd cloud
infisical run -- ansible-playbook site.yml                  # full provision / converge
infisical run -- ansible-playbook nginx.yml                 # just re-render + reload nginx
infisical run -- ansible-playbook update-cloud-images.yml   # bump cloud-server image + cloud-web bundle
```

`cloud_stack` does **not** read cloud-server's app secrets from `infrastructure` — it exports them from
the **vritti-cloud** project's `production` env (via a machine identity) at deploy time. This project is
deploy machinery only.

## core — any agent-hosted VM, selected by `--env`

`core/.infisical.json` pins **vritti-core**. **Everything per-VM lives in that env's `/agent` folder**
(so pass `--path=/agent`), which means the inventory and files never change per VM — you select the VM
purely by `--env`:

```bash
cd core
infisical run --env=apw1 --path=/agent -- ansible-playbook site.yml   # prod core (apw1, edge:managed)
infisical run --env=dev  --path=/agent -- ansible-playbook site.yml   # cloud dev core (edge:external)
```

**Per-env `/agent` secrets:**

| Secret | Purpose |
|---|---|
| `TARGET_IP` | the VM's reserved public IP → `ansible_host` |
| `GHCR_USERNAME`, `GHCR_TOKEN` | GHCR login (docker role) so the agent image can be pulled |
| `DEPLOYMENT_ID`, `ENROLL_TOKEN` | agent enrollment (enroll token is single-use) |
| `ALLOW_ACME_DNS` | `true` only where the deployment manages its own edge (opens `:53` for acme-dns); omit for `edge:external` VMs like the cloud dev core |

**Adding a new core VM (e.g. apw2):** create its Infisical env with the six secrets above and run
`infisical run --env=apw2 --path=/agent -- ansible-playbook site.yml`. No file edits — that's the whole
point of the shared play + placeholder inventory.

### The cloud VM runs a core agent too (the dev core)

The cloud VM is provisioned by `cloud/` **and** hosts one `core` deployment — the dev core on
`*.vrittiai.dev`. That deployment is **`edge: external`**: the agent runs only `core-server:3002` on the
shared `vritti-core-net`, and the cloud stack's nginx is its edge (serves `*.vrittiai.dev` with the
`*.vrittiai.dev` LE cert). So `env=dev` has **no `ALLOW_ACME_DNS`** — the cloud VM opens no `:53`.

## Secrets — Infisical only (no ansible-vault)

Every secret comes from Infisical, injected as env vars by `infisical run`; plays read them with
`lookup('env', 'NAME')`. `cloud/` reads `ANSI_*` / `TF_VAR_ANSI_*` from **infrastructure/prod**; `core/`
reads the unprefixed `/agent` secrets above from **vritti-core**.

## Notes

- **DbLab** (cloud VM) restores the prod core DB from the R2 pgBackRest repo and serves thin clones;
  inert until backups exist. Keep `dblab.` behind Zero-Trust.
- **Cloud DB backups** — postgres archives WAL + runs pgBackRest → R2 once `ANSI_CLOUD_BACKREST_R2_BUCKET`
  is set.
- **Customer/core deployments never route secrets through Ansible** — the agent generates machine secrets
  on the VM and decrypts sealed human secrets locally. `core/` provides only the host + the agent's
  `deployment_id`/`enroll_token`; the secret-store connection arrives in the signed desired-state.
- **Reserved IPs only** — every host IP is a reserved public IP supplied via a secret (`CLOUD_TARGET_IP`
  / per-env `TARGET_IP`). Nothing touches unmanaged VMs.
```
