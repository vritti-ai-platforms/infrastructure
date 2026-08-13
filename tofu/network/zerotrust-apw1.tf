# =====================================================================
# apw1 (vm2) — Zero Trust tunnel and its Access-gated routes.
#
# Kept OUT of zerotrust.tf on purpose. That file's map drives the cloud VM's admin surfaces; apw1 is a
# production deployment with a different threat model, so it gets its own file and its own review
# surface. Same state and same zone/IdP though — HCL treats every .tf in this folder as one module, so
# local.cf_account_id, local.cf_zone_id, the GitHub IdP resource and var.github_org resolve across files.
#
# Everything NOT listed below stays public by design: agent nginx serves *.apw1 (unproxied wildcard, see
# dns.tf) and git-over-SSH goes straight to the VM. The services here have no host-published port and no
# security-group rule, so the tunnel is their only door and Access gates every connection through it.
# =====================================================================

locals {
  # The tunnel is named for the deployment, not the VM ordinal: the justfile, Ansible envs and Infisical
  # all key off apw1/apw2, so `vritti-apw2` stays unambiguous in a way `vritti-vm3` would not.
  apw1_tunnel_name = "vritti-apw1"

  # label -> { url cloudflared forwards to on the VM, title on the Access login page }.
  #
  # Each ingress rule needs its OWN hostname: one hostname cannot serve both a raw-TCP and an HTTP
  # origin, so "add a route" means "add an entry here" — the resources below fan out automatically.
  #
  # Labels are deliberately FIRST-level (apw1-git, not git.apw1): free Universal SSL covers
  # <label>.vrittiai.com, while a second-level name would need Advanced Certificate Manager (see the
  # zone notes in dns.tf).
  #
  # CAVEAT on the service names: apw1's stack is materialized by the AGENT from cloud's signed
  # desired-state, not by Ansible, so `postgres` and `gitea` must match what the containers actually
  # answer to on the docker network cloudflared joins. ansible/core/db-tunnel.yml asserts exactly that
  # before starting the connector, because a wrong name here still resolves and still passes Access,
  # then fails at the origin — indistinguishable from an outage unless you already suspect the config.
  apw1_services = {
    # Postgres — raw TCP. Reach it with `cloudflared access tcp --hostname apw1db.vrittiai.com
    # --url localhost:5432`, which in vritti-core is `pnpm db:tunnel:apw1` paired with the apw1-local
    # Infisical env (whose PRIMARY_DB_HOST=localhost only means "apw1" while that is running).
    # Keep this label as-is: vritti-core's db:tunnel:apw1 script hard-codes apw1db.vrittiai.com.
    "apw1db" = {
      url   = "tcp://postgres:5432"
      title = "Vritti APW1 DB"
    }

    # Gitea web UI — plain HTTP behind Access, so a browser at https://apw1-git.vrittiai.com gets the
    # GitHub SSO gate and then the UI. NOTE: `git clone` over HTTPS will NOT work through this, because
    # the git CLI cannot satisfy an Access challenge — use git-over-SSH direct to the VM for that, or an
    # Access service token. Core-server's own Gitea API calls are unaffected: they go over the docker
    # network and never touch this hostname.
    "apw1-git" = {
      url   = "http://gitea:3000"
      title = "Vritti APW1 Git"
    }
  }
}

# Secret shared with the tunnel record; cloudflared on the VM authenticates with the token output
# below, not with this value.
resource "random_id" "apw1_tunnel_secret" {
  byte_length = 35
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "apw1" {
  account_id = local.cf_account_id
  name       = local.apw1_tunnel_name
  secret     = random_id.apw1_tunnel_secret.b64_std
  config_src = "cloudflare"
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "apw1" {
  account_id = local.cf_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.apw1.id

  config {
    dynamic "ingress_rule" {
      for_each = local.apw1_services
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

# Proxied CNAME per route -> the apw1 tunnel. These are first-level labels, so they never collide with
# the unproxied "*.apw1" wildcard that points straight at the VM.
resource "cloudflare_record" "apw1" {
  for_each = local.apw1_services

  zone_id         = local.cf_zone_id
  name            = each.key
  type            = "CNAME"
  content         = "${cloudflare_zero_trust_tunnel_cloudflared.apw1.id}.cfargotunnel.com"
  proxied         = true
  allow_overwrite = true
  comment         = "managed by tofu (zero trust tunnel -> apw1)"
}

# Access application + GitHub-org policy per route, mirroring the vm1 services in zerotrust.tf. 24h
# sessions, so a laptop re-authenticates daily; `cloudflared access tcp` caches the token under
# ~/.cloudflared and a browser keeps a cookie.
resource "cloudflare_zero_trust_access_application" "apw1" {
  for_each = local.apw1_services

  account_id                = local.cf_account_id
  name                      = each.value.title
  domain                    = "${each.key}.vrittiai.com"
  type                      = "self_hosted"
  session_duration          = "24h"
  allowed_idps              = [cloudflare_zero_trust_access_identity_provider.github.id]
  auto_redirect_to_identity = true # skip the picker -> straight to GitHub login
}

resource "cloudflare_zero_trust_access_policy" "apw1" {
  for_each = local.apw1_services

  application_id = cloudflare_zero_trust_access_application.apw1[each.key].id
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

# Ansible's db-tunnel.yml play receives this via the justfile recipe, which reads it with
# `tofu output -raw apw1_tunnel_token` and passes it as CF_TUNNEL_TOKEN.
output "apw1_tunnel_token" {
  description = "Token cloudflared uses to run the apw1 tunnel (Ansible injects this on the VM)"
  value       = cloudflare_zero_trust_tunnel_cloudflared.apw1.tunnel_token
  sensitive   = true
}

# --- Preserve the already-applied apw1db resources across the single-resource -> map refactor -------
# Without these, adding the gitea route would destroy and recreate the DB record/app/policy even though
# the hostname never changed. Safe to delete once this has been applied everywhere.
moved {
  from = cloudflare_record.apw1db
  to   = cloudflare_record.apw1["apw1db"]
}
moved {
  from = cloudflare_zero_trust_access_application.apw1db
  to   = cloudflare_zero_trust_access_application.apw1["apw1db"]
}
moved {
  from = cloudflare_zero_trust_access_policy.apw1db
  to   = cloudflare_zero_trust_access_policy.apw1["apw1db"]
}
