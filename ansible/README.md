# Vritti Ansible

Provisions the two control-plane VMs. **VM1 and VM2 are asymmetric by design** because the
Go deployment agent (`vritti-application-agent`) owns the core stack — Ansible only owns the
host + (on vm1) the cloud compose stack.

| | VM1 (`vritti-vm1`) | VM2 (`vritti-vm2`) |
|---|---|---|
| Roles | base, docker, zfs, tls, cloud_stack, agent | base, docker, agent |
| Cloud stack | Ansible compose (`/opt/vritti`) | — |
| Core stack | agent (dev deployment) | agent (prod deployment) |
| ZFS + DbLab | yes | no |
| Edge nginx | cloud nginx (cloud./admin./dblab./*.dev) | agent's own nginx add-on |

## Layout

```
ansible.cfg              inventory/tofu-inventory.py   # VM IPs from `tofu output` (default)
                         inventory/hosts.yml.example   # optional static fallback
group_vars/all.yml       shared vars                   group_vars/vm1.yml, vm2.yml   per-VM vars
site.yml                 vm1.yml   vm2.yml             # the two plays
roles/  base  docker  zfs  tls  geoip  cloud_stack  agent  cloudflared
```

## Inventory

Hosts come from the **tofu compute outputs** — no IPs are hand-copied. `inventory/tofu-inventory.py`
runs `tofu output -json` in `tofu/compute` and maps `vm1_public_ipv4` / `vm2_public_ipv4` onto the
`vm1` / `vm2` groups. Because the tofu providers read creds via `infisical run`, invoke Ansible the
same way:

```bash
infisical run -- ansible-inventory --list          # sanity-check the resolved IPs
infisical run -- ansible-playbook vm1.yml
```

Overrides: `TOFU_DIR` (compute dir), `TOFU_BIN` (tofu/terraform). For a disconnected run, copy
`inventory/hosts.yml.example` → `hosts.yml`, fill IPs, and point `ansible.cfg` at it.

## Secrets — Infisical only (no ansible-vault)

Every secret comes from **Infisical** (`infrastructure` project, `prod` env), injected as env vars
by `infisical run`; the playbooks read them with `lookup('env', 'NAME')`. There is no vault file.

Secrets the playbooks expect in Infisical:

| Env var | Used by | In Infisical? |
|---|---|---|
| `CLOUDFLARE_API_TOKEN` | tls (DNS-01), tofu | ✅ |
| `MAXMIND_ACCOUNT_ID`, `MAXMIND_LICENSE_KEY` | geoip | ✅ |
| `GHCR_USERNAME`, `GHCR_TOKEN` | docker (private image pulls) | ➕ add |
| `CLOUD_DB_PASSWORD`, `CLOUD_REDIS_PASSWORD`, `CLOUD_JWT_SECRET`, `CLOUD_HMAC_KEY`, `CLOUD_COOKIE_SECRET` | cloud_stack | ➕ add |
| `VM1_DEPLOYMENT_ID`, `VM1_ENROLL_TOKEN`, `VM2_DEPLOYMENT_ID`, `VM2_ENROLL_TOKEN` | agent | ➕ add (from vritti-admin, Wave 2) |

## Run

```bash
ansible-galaxy collection install -r requirements.yml

# Always wrap in `infisical run` (same as tofu) so both the inventory (tofu output) and every
# lookup('env', ...) resolve:
infisical run --projectId 8f447810-a5c7-4a83-a4f3-1a775999edd9 --env prod -- ansible-inventory --list
infisical run --projectId 8f447810-a5c7-4a83-a4f3-1a775999edd9 --env prod -- ansible-playbook vm1.yml --tags control-plane
infisical run --projectId 8f447810-a5c7-4a83-a4f3-1a775999edd9 --env prod -- ansible-playbook vm2.yml
```

## Notes

- **Enroll token** is consumed on the agent's first boot only; afterwards the agent uses its
  cached credential + local keys. Rotating a deployment = new token in Infisical + re-run `agent`.
- **DbLab** (vm1) is a compose profile (`--profile dblab`), started on demand — it needs the
  ZFS pool from the `zfs` role and is dev-only. Keep `dblab.` behind Zero-Trust.
- **Customer deployments never route secrets through Ansible/Infisical** — the agent generates
  machine secrets on their VM and decrypts sealed human secrets locally. Infisical here holds
  only OUR control-plane infra secrets.
- **Do not touch existing VMs** — inventory targets only the new reserved IPs.
