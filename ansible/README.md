# Vritti Ansible

Provisions **vm1 — the cloud control plane**. Ansible owns the host + the cloud compose stack.
The **core deployments** (dev vritti-core on vm1, prod vritti-core on vm2) are owned by the Go
deployment agent (`vritti-application-agent`) and are **not** provisioned here.

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
ansible.cfg              inventory/tofu-inventory.py   # vm1 IP from `tofu output` (default)
                         inventory/hosts.yml.example   # optional static fallback
group_vars/all.yml       shared vars                   group_vars/vm1.yml   per-VM vars
vm1.yml                                                # the play
roles/  base  docker  zfs  tls  geoip  cloud_stack  cloudflared
```

## Inventory

The vm1 host comes from the **tofu compute outputs** — no IP is hand-copied.
`inventory/tofu-inventory.py` runs `tofu output -json` in `tofu/compute` and maps `vm1_public_ipv4`
onto the `vm1` group. Because the tofu providers read creds via `infisical run`, invoke Ansible the
same way:

```bash
infisical run -- ansible-inventory --list          # sanity-check the resolved IP
infisical run -- ansible-playbook vm1.yml
```

Overrides: `TOFU_DIR` (compute dir), `TOFU_BIN` (tofu/terraform). For a disconnected run, copy
`inventory/hosts.yml.example` → `hosts.yml`, fill the IP, and point `ansible.cfg` at it.

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

## Notes

- **DbLab** (vm1) runs as part of the cloud stack (needs the ZFS pool from the `zfs` role). It
  physically restores the prod core DB from the R2 pgBackRest repo and serves thin clones; it's
  inert until those backups exist. Keep `dblab.` behind Zero-Trust.
- **Cloud DB backups** — postgres archives WAL + runs scheduled pgBackRest backups to R2 once
  `ANSI_CLOUD_BACKREST_R2_BUCKET` is set (otherwise it stays a plain, un-archived DB).
- **Customer/core deployments never route secrets through Ansible/Infisical** — the agent generates
  machine secrets on the VM and decrypts sealed human secrets locally. Infisical here holds only
  OUR control-plane infra secrets.
- **Do not touch existing VMs** — inventory targets only the new reserved IP.
```
