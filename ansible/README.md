# Vritti Ansible

Provisions **vm1 — the cloud control plane** (host + cloud compose stack) and **vm2 — the prod-core
host** (base + docker + GHCR login). Three plays, run separately, in two Infisical contexts:

| Play | Dir | Infisical | Does |
|---|---|---|---|
| `vm1.yml` | `./` | infrastructure / prod | cloud control plane (host + compose stack) |
| `vm2.yml` | `./` | infrastructure / prod | prod-core **host** bootstrap: base + docker + GHCR login |
| `agent/agent.yml` | `agent/` | **vritti-core / apw1** (`/agent`) | deploy + enroll the `vritti-application-agent` |

`vm2.yml` does **not** deploy the agent — it only preps the host and logs into GHCR (that login
persists, so the agent pull needs no creds). The agent is a **separate play** because it reads its
deploy/enroll secrets from a different project (vritti-core `apw1`). The **core stack itself** (pg,
redis, nats, core-server, commerce, nginx) is then materialized by the agent from signed
desired-state. There is no shared `group_vars/all.yml`.

The one coupling: on vm1 the agent runs the dev core with **no nginx of its own**
(`AddOns.Nginx=false`), so this repo's cloud nginx is its **shared edge** — it attaches to the
external `vritti-core-net` and proxies `*.dev → core-server:3002`. (On vm2 the agent bundles its
own nginx, so vm2 needs no edge from us.)

| vm1 role | owner |
|---|---|
| base, docker, zfs, tls, geoip, cloud_stack, cloudflared | **Ansible** (this repo) |
| cloud compose stack (`/opt/vritti`): nginx + cloud-web SPA + cloud-server + pg/redis/nats + DbLab | **Ansible** |
| dev vritti-core (`*.dev`, fronted by our nginx) | agent |
| ZFS + DbLab (thin clones from the prod-core R2 backup) | **Ansible** deploys; agent's core consumes |

## Layout

```
# vm1 + vm2 (host plays) — run from this dir, infra Infisical / prod, tofu dynamic inventory
ansible.cfg              inventory/tofu-inventory.py   # vm1 + vm2 IPs from `tofu output`
                         inventory/hosts.yml.example   # optional static fallback
.infisical.json          # infrastructure project / prod
group_vars/vm1.yml       # vm1 vars (ssh user, ghcr, base pkgs, docker arch, cloud-stack toggles)
group_vars/vm2.yml       # vm2 HOST vars (ssh user, ghcr, base pkgs, docker arch)
vm1.yml                  # cloud control plane
vm2.yml                  # prod-core host bootstrap (roles: base, docker)
roles/  base  docker  zfs  tls  geoip  cloud_stack  cloudflared  agent   # shared by all plays

# agent — run from agent/, vritti-core Infisical / apw1 (path /agent)
agent/ansible.cfg        # roles_path = ../roles ; inventory = inventory.yml (static)
      inventory.yml      # vm2 RESERVED IP (no tofu/R2 creds needed)
      .infisical.json    # vritti-core project / apw1
      group_vars/vm2.yml # deployment_id / enroll_token + ssh connection
      agent.yml          # the play (roles: agent)
```

## Inventory

The vm1/vm2 hosts come from the **tofu compute outputs** — no IP is hand-copied.
`inventory/tofu-inventory.py` runs `tofu output -json` in `tofu/compute` and maps `vm1_public_ipv4`
/ `vm2_public_ipv4` onto the `vm1` / `vm2` groups. Because the tofu providers read creds via
`infisical run`, invoke Ansible the same way:

```bash
infisical run -- ansible-inventory --list          # sanity-check the resolved IPs
infisical run -- ansible-playbook vm1.yml
infisical run -- ansible-playbook vm2.yml
```

Overrides: `TOFU_DIR` (compute dir), `TOFU_BIN` (tofu/terraform). For a disconnected run, copy
`inventory/hosts.yml.example` → `hosts.yml`, fill the IP, and point `ansible.cfg` at it.

> The **agent play** (`agent/`) does NOT use this inventory — it has its own static `inventory.yml`
> (vm2's reserved IP) because it runs under the vritti-core env, which carries no tofu/R2 creds.

## Secrets — Infisical only (no ansible-vault)

Every secret comes from **Infisical** (`infrastructure` project, `prod` env), injected as env vars
by `infisical run`; the playbook reads them with `lookup('env', 'NAME')`. There is no vault file.
Naming: `ANSI_*` = ansible-only, `TF_VAR_ANSI_*` = shared with tofu.

| Env var | Used by | In Infisical? |
|---|---|---|
| `TF_VAR_ANSI_CLOUDFLARE_API_TOKEN` | tls (DNS-01) — also tofu | ✅ |
| `ANSI_MAXMIND_ACCOUNT_ID`, `ANSI_MAXMIND_LICENSE_KEY` | geoip | ✅ |
| `ANSI_GHCR_TOKEN` | docker + cloud-web bundle pull | ✅ |
| `ANSI_SSH_PRIVATE_KEY` | SSH to vm1 (CI) | ✅ |
| `ANSI_CORE_BACKREST_*` | DbLab (restore source; shared with the prod-core backup agent) | ✅ (inert until backups exist) |
| `ANSI_CLOUD_BACKREST_*` | cloud DB pgBackRest → R2 | ✅ |

**Note:** `cloud_stack` does *not* read cloud-server's app secrets from here — it exports them from
the **vritti-cloud** Infisical project's `production` env (via a machine identity) at deploy time.
This project is deploy machinery only. It also pulls the **cloud-web** SPA bundle from GHCR (oras)
and serves it via nginx; the API is proxied at `/api`.

## Run

`.infisical.json` in this dir pins the project (`infrastructure`) + env (`prod`), so `infisical run`
needs no flags. Always wrap in `infisical run` so both the inventory (`tofu output`) and every
`lookup('env', …)` resolve.

```bash
ansible-galaxy collection install -r requirements.yml

infisical run -- ansible-inventory --graph                       # sanity-check the resolved host
infisical run -- ansible-playbook vm1.yml --tags control-plane   # cloud control plane
infisical run -- ansible-playbook vm1.yml                        # full play (same thing; no core here)
```

### vm2 host bootstrap — run from this dir (infra Infisical)

Same context as vm1. Preps the prod-core host and logs into GHCR (the login persists on the host for
the agent play):

```bash
infisical run -- ansible-playbook vm2.yml
```

### agent deploy + enroll — run from `agent/` (vritti-core Infisical)

`agent/.infisical.json` pins the **vritti-core** project / **`apw1`**; the deploy/enroll secrets live
at its **`/agent`** path (so pass `--path=/agent`). Inventory is vm2's static reserved IP — no
tofu/R2 creds. **Prereq:** `vm2.yml` has already run (docker + GHCR login present). The enroll token
is **single-use** (consumed on first enrollment).

```bash
cd agent
infisical run --path=/agent -- ansible-playbook agent.yml
```

`apw1-local` mirrors `apw1` for local-agent testing.

## Notes

- **DbLab** (vm1) runs as part of the cloud stack (needs the ZFS pool from the `zfs` role). It
  physically restores the prod core DB from the R2 pgBackRest repo and serves thin clones; it's
  inert until those backups exist. Keep `dblab.` behind Zero-Trust.
- **Cloud DB backups** — postgres archives WAL + runs scheduled pgBackRest backups to R2 once
  `ANSI_CLOUD_BACKREST_R2_BUCKET` is set (otherwise it stays a plain, un-archived DB).
- **Customer/core deployments never route secrets through Ansible/Infisical** — the agent generates
  machine secrets on the VM and decrypts sealed human secrets locally. On vm2 Ansible provides only
  the host + the agent's `deployment_id`/`enroll_token`; the agent's own secret-store connection
  arrives in the signed desired-state, not from here.
- **Reserved IPs only** — vm1 + vm2 host plays resolve via the tofu dynamic inventory; the agent
  play uses its static `agent/inventory.yml` (vm2's reserved IP). None touch unmanaged VMs.
```
