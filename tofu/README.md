# Vritti Infrastructure — OpenTofu

Provisions Excloud VMs + Cloudflare (DNS/R2) as code. State lives in Cloudflare R2.

## Layout — two independent layers (separate state)
```
infrastructure/tofu/
├── network/    Reserved public IPs. Permanent. State key: network/terraform.tfstate
└── compute/    VMs. Disposable. State key: prod/terraform.tfstate
                Reads the IP ids from network's state (terraform_remote_state).
```
Why split: a `tofu destroy` in **compute/** removes the VMs but **cannot touch the IPs**
(they live in a different state). So VMs are cattle; the IPs — and the DNS pointing at
them — never move. The IPs also carry `prevent_destroy` in `network/`.

## Prerequisites (one-time, per machine)
```bash
brew install opentofu                                   # `tofu` CLI, >= 1.10
brew install infisical/get-cli/infisical                # secrets injector
infisical login --domain=https://infisical.vrittiai.com/api
```

## Secrets
All credentials live in the Infisical **`infrastructure`** project (`prod` env) and
are injected as env vars at run time — nothing sensitive is stored on disk or in `.tf`:

Naming: `TF_VAR_*` = tofu-only, `ANSI_*` = ansible-only, `TF_VAR_ANSI_*` = both (tofu reads it
natively via the `TF_VAR_` prefix; ansible reads the full name). Providers are wired to these
variables in `providers.tf` — no raw-env auto-detection.

| Env var | Purpose |
|---|---|
| `TF_VAR_EXCLOUD_API_KEY`, `TF_VAR_EXCLOUD_ORG_ID` | Excloud provider (`var.EXCLOUD_*`) |
| `TF_VAR_ANSI_CLOUDFLARE_API_TOKEN` | Cloudflare provider (`var.ANSI_CLOUDFLARE_API_TOKEN`) — also used by ansible |
| `TF_VAR_GITHUB_IDP_CLIENT_ID`, `TF_VAR_GITHUB_IDP_CLIENT_SECRET` | GitHub Access IdP |
| `TF_VAR_SSH_PUBLIC_KEY` | VM SSH public key |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | R2 state backend — **exact names required** (backends can't read variables), so no prefix |

Each layer has its own `.infisical.json`, so `infisical run` needs no `--projectId`.

## Usage — always wrap `tofu` with `infisical run`
First-time / after a full teardown, apply **network before compute** (compute reads
network's state):

```bash
# 1) Reserved IPs (rarely changes)
cd infrastructure/tofu/network
infisical run -- tofu init
infisical run -- tofu apply

# 2) VMs
cd ../compute
infisical run -- tofu init
infisical run -- tofu apply
```

Day-to-day VM rebuild (IPs stay put):
```bash
cd infrastructure/tofu/compute
infisical run -- tofu destroy      # VMs gone, IPs untouched
infisical run -- tofu apply        # VMs back on the same IPs
```
