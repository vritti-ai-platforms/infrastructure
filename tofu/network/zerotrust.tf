# =====================================================================
# Cloudflare Zero Trust — one cloudflared tunnel per VM + Access (GitHub-org SSO).
#
# cloudflared runs on each VM (installed by Ansible with the per-VM tunnel token output). NO
# inbound ports are opened for these services — the origin IP stays hidden and Access gates
# every request against the vritti-ai-platforms GitHub org. git itself goes over SSH (Access
# only guards the web UI).
# =====================================================================

variable "GITHUB_IDP_CLIENT_ID" {
  description = "GitHub OAuth App client id (Infisical: TF_VAR_GITHUB_IDP_CLIENT_ID)"
  type        = string
}

variable "GITHUB_IDP_CLIENT_SECRET" {
  description = "GitHub OAuth App client secret (Infisical: TF_VAR_GITHUB_IDP_CLIENT_SECRET)"
  type        = string
  sensitive   = true
}

variable "github_org" {
  description = "GitHub org whose members are allowed through Access"
  type        = string
  default     = "vritti-ai-platforms"
}

locals {
  cf_account_id = "45131bc1e1eb60fabc1b7991b762489f"

  # One tunnel per VM. Each host = record label under vrittiai.com -> { url cloudflared
  # forwards to on that VM, title shown on the Access login page }.
  #
  # cloudflared runs as a CONTAINER on the app docker networks (see ansible roles/cloudflared),
  # so these URLs are internal service names — NOT localhost. Deliberate: the admin surfaces
  # have no host-published port, so there is no public door to bypass Access at.
  #   admin  -> nginx:8080  (internal-only admin server block, proxies cloud-server)
  #   dblab  -> dblab:2345
  #   git    -> gitea:3000
  #   clouddb -> postgres:5432 (raw TCP; reach via `cloudflared access tcp`, Access-gated)
  tunnels = {
    vm1 = {
      name = "vritti-vm1"
      hosts = {
        "dblab"   = { url = "http://dblab:2345", title = "Vritti DbLab" }
        "admin"   = { url = "http://nginx:8080", title = "Vritti Admin" }
        "git.dev" = { url = "http://gitea:3000", title = "Vritti Git (dev)" }
        "clouddb" = { url = "tcp://postgres:5432", title = "Vritti Cloud DB" }
      }
    }
    # vm2 (prod core) has NO tunnel: it's public (agent nginx on *.apw1), git is SSH-only, and
    # Gitea is managed via API. Nothing internal to gate, so no cloudflared runs there.
  }

  # Flatten to hostname -> { vm, url, title } for the per-service resources.
  services = merge([
    for vmkey, t in local.tunnels : {
      for host, svc in t.hosts : host => merge(svc, { vm = vmkey })
    }
  ]...)
}

# GitHub identity provider — org members log in with GitHub SSO (membership lives in GitHub).
resource "cloudflare_zero_trust_access_identity_provider" "github" {
  account_id = local.cf_account_id
  name       = "GitHub"
  type       = "github"

  config {
    client_id     = var.GITHUB_IDP_CLIENT_ID
    client_secret = var.GITHUB_IDP_CLIENT_SECRET
  }
}

# 32-byte secret per tunnel, shared with cloudflared on that VM.
resource "random_id" "tunnel_secret" {
  for_each    = local.tunnels
  byte_length = 35
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "vm" {
  for_each   = local.tunnels
  account_id = local.cf_account_id
  name       = each.value.name
  secret     = random_id.tunnel_secret[each.key].b64_std
  config_src = "cloudflare"
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "vm" {
  for_each   = local.tunnels
  account_id = local.cf_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.vm[each.key].id

  config {
    dynamic "ingress_rule" {
      for_each = each.value.hosts
      content {
        hostname = "${ingress_rule.key}.vrittiai.com"
        service  = ingress_rule.value.url
      }
    }
    # Required catch-all: anything not matched gets a 404 (no accidental exposure).
    ingress_rule {
      service = "http_status:404"
    }
  }
}

# Proxied CNAME per service -> its VM's tunnel. Specific records beat the "*" wildcard.
resource "cloudflare_record" "tunnel" {
  for_each = local.services

  zone_id         = local.cf_zone_id
  name            = each.key
  type            = "CNAME"
  content         = "${cloudflare_zero_trust_tunnel_cloudflared.vm[each.value.vm].id}.cfargotunnel.com"
  proxied         = true
  allow_overwrite = true
  comment         = "managed by tofu (zero trust tunnel -> ${each.value.vm})"
}

# Access application + GitHub-org policy per service.
resource "cloudflare_zero_trust_access_application" "svc" {
  for_each = local.services

  account_id                = local.cf_account_id
  name                      = each.value.title
  domain                    = "${each.key}.vrittiai.com"
  type                      = "self_hosted"
  session_duration          = "24h"
  allowed_idps              = [cloudflare_zero_trust_access_identity_provider.github.id]
  auto_redirect_to_identity = true # skip the picker -> straight to GitHub login
}

resource "cloudflare_zero_trust_access_policy" "svc" {
  for_each = local.services

  application_id = cloudflare_zero_trust_access_application.svc[each.key].id
  account_id     = local.cf_account_id
  name           = "allow-github-org"
  precedence     = 1
  decision       = "allow"

  include {
    github {
      name                 = var.github_org
      identity_provider_id = cloudflare_zero_trust_access_identity_provider.github.id
    }
  }
}

# --- Service token for headless clients (scripts, Postman, CI) on the admin app ---------
# Browser users still get GitHub SSO (the policy above). Non-browser clients present the
# service token as CF-Access-Client-Id / CF-Access-Client-Secret headers instead; Cloudflare
# validates them at the edge and lets the request through the tunnel. This is the ONLY way to
# reach admin. programmatically — nothing bypasses Access.
resource "cloudflare_zero_trust_access_service_token" "admin" {
  account_id = local.cf_account_id
  name       = "vritti-admin-api"
  # Rotate before expiry; provider warns within min_days_for_renewal.
  duration = "8760h" # 1 year
}

resource "cloudflare_zero_trust_access_policy" "admin_service_token" {
  application_id = cloudflare_zero_trust_access_application.svc["admin"].id
  account_id     = local.cf_account_id
  name           = "allow-admin-service-token"
  precedence     = 2
  decision       = "non_identity" # service tokens are non-identity auth

  include {
    service_token = [cloudflare_zero_trust_access_service_token.admin.id]
  }
}

# --- Access for the docs site (docs.vrittiai.dev) — Mintlify-hosted, proxied through Cloudflare, gated
# by GitHub-org SSO. NOT a tunnel service (external origin); it's a standalone Access app on the proxied
# hostname, so Access enforces at the Cloudflare edge before the request ever reaches Mintlify. ---
resource "cloudflare_zero_trust_access_application" "docs" {
  account_id                = local.cf_account_id
  name                      = "Vritti Docs"
  domain                    = "docs.vrittiai.dev"
  type                      = "self_hosted"
  session_duration          = "24h"
  allowed_idps              = [cloudflare_zero_trust_access_identity_provider.github.id]
  auto_redirect_to_identity = true # skip the picker -> straight to GitHub login
}

resource "cloudflare_zero_trust_access_policy" "docs" {
  application_id = cloudflare_zero_trust_access_application.docs.id
  account_id     = local.cf_account_id
  name           = "allow-github-org"
  precedence     = 1
  decision       = "allow"

  include {
    github {
      name                 = var.github_org
      identity_provider_id = cloudflare_zero_trust_access_identity_provider.github.id
    }
  }
}

# --- Preserve already-applied resources across the vm1->per-VM refactor (no recreate) ---
moved {
  from = random_id.vm1_tunnel_secret
  to   = random_id.tunnel_secret["vm1"]
}
moved {
  from = cloudflare_zero_trust_tunnel_cloudflared.vm1
  to   = cloudflare_zero_trust_tunnel_cloudflared.vm["vm1"]
}
moved {
  from = cloudflare_zero_trust_tunnel_cloudflared_config.vm1
  to   = cloudflare_zero_trust_tunnel_cloudflared_config.vm["vm1"]
}
moved {
  from = cloudflare_zero_trust_access_application.vm1["dblab"]
  to   = cloudflare_zero_trust_access_application.svc["dblab"]
}
moved {
  from = cloudflare_zero_trust_access_policy.vm1["dblab"]
  to   = cloudflare_zero_trust_access_policy.svc["dblab"]
}
