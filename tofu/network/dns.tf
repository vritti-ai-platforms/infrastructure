# Cloudflare DNS — permanent, lives with the reserved IPs it points at. Because the records
# are in this same module, they reference the IP resources directly (no remote state).

data "cloudflare_zones" "main" {
  filter {
    name = var.dns_zone_name
  }
}

# Separate zone for the dev namespace. vrittiai.dev is its OWN registrable domain, so *.vrittiai.dev
# is a FIRST-level wildcard — free Universal SSL covers it AND it can be proxied on the Free plan
# (unlike *.dev.vrittiai.com, a second-level wildcard that would need Advanced Certificate Manager).
data "cloudflare_zones" "dev" {
  filter {
    name = var.dns_dev_zone_name
  }
}

locals {
  cf_zone_id     = data.cloudflare_zones.main.zones[0].id
  cf_dev_zone_id = data.cloudflare_zones.dev.zones[0].id

  vm_ip = {
    cloud = excloud_public_ipv4.cloud.ip
    apw1 = excloud_public_ipv4.apw1.ip
  }

  # Wildcards — one A record per VM; nginx on each VM does host-based routing (api., dblab.,
  # cloud., admin., per-tenant, ...) and terminates TLS via Let's Encrypt.
  #   vm      = "cloud" | "apw1"  (which VM's reserved IP to point at)
  #   proxied = false for wildcards — proxied WILDCARDS need a Cloudflare Business plan, and
  #             nginx handles TLS anyway. (A specific record could be proxied.)
  #
  # NO apex "*" catch-all — the cloud VM serves only explicit hostnames (cloud./api. here +
  # admin./dblab. via zero-trust tunnel CNAMEs); undefined subdomains must NOT land on it.
  # DNS wildcards only match ONE label, so *.dev.vrittiai.com and *.apw1.vrittiai.com are distinct.
  dns_records = {
    "*.dev"  = { vm = "cloud", proxied = false } # *.dev.vrittiai.com  → cloud VM
    "*.apw1" = { vm = "apw1", proxied = false }  # *.apw1.vrittiai.com → apw1 VM (AP-West-1: India + Gulf)

    # cloud. is PROXIED (orange cloud): DNS returns Cloudflare IPs (origin hidden), CF terminates
    # TLS + runs DDoS/WAF, then reaches nginx over the internet (Full-Strict, validated against the
    # Let's Encrypt cert). The security group then locks :80/:443 to Cloudflare ranges so the origin
    # can't be hit directly. A SPECIFIC record beats the "*" wildcard, so this wins for cloud.
    cloud = { vm = "cloud", proxied = true }

    # api. is the PUBLIC machine API (agent enroll/desired-state/status). Proxied like cloud. — CF
    # WAF/DDoS/rate-limiting at the edge, firewall stays CF-locked — but NOT Access-gated: the agent
    # authenticates with its own Ed25519 + enroll token, so no service token lives on any VM.
    api = { vm = "cloud", proxied = true }
  }
}

# Zone SSL mode — managed in code so it can't drift. Full (Strict) is REQUIRED for the proxied
# cloud./api. records: Cloudflare reaches nginx over HTTPS and validates its Let's Encrypt cert (with
# Flexible the origin's http->https redirect would loop). Only `ssl` is managed here — every other
# zone setting (always_use_https, min_tls_version, etc.) stays at its current live value (computed,
# not touched), so re-adding this resource preserves the zone exactly instead of resetting it.
resource "cloudflare_zone_settings_override" "main" {
  zone_id = local.cf_zone_id

  settings {
    ssl = "strict"
  }

  # `initial_settings` is a computed "before" snapshot the provider re-derives every plan, causing a
  # perpetual phantom in-place diff even though no live setting changes. Ignore it so plans stay clean
  # and real drift stands out.
  lifecycle {
    ignore_changes = [initial_settings]
  }
}

resource "cloudflare_record" "app" {
  for_each = local.dns_records

  zone_id = local.cf_zone_id
  name    = each.key
  type    = "A"
  content = local.vm_ip[each.value.vm]
  proxied = each.value.proxied
  ttl     = each.value.proxied ? 1 : 300 # TTL must be 1 (auto) when proxied

  # Take over an existing record of the same name instead of erroring (clean cutover).
  allow_overwrite = true
  comment         = "managed by tofu (network layer)"
}

# --- vrittiai.dev zone -----------------------------------------------------------------------
# *.vrittiai.dev → cloud VM, PROXIED (orange). First-level wildcard, so free Universal SSL issues
# the edge cert and the Free plan permits proxying it. CF terminates TLS at the edge; nginx on the
# cloud VM is the origin (must carry a *.vrittiai.dev LE cert once SSL mode is flipped to Strict).
resource "cloudflare_record" "dev_wildcard" {
  zone_id         = local.cf_dev_zone_id
  name            = "*"
  type            = "A"
  content         = excloud_public_ipv4.cloud.ip
  proxied         = true
  ttl             = 1 # must be auto when proxied
  allow_overwrite = true
  comment         = "managed by tofu (network layer)"
}

# Dev zone SSL mode — Full (Strict), same posture as the main zone. Safe to enforce now because
# nothing serves *.vrittiai.dev yet; when the cloud VM's nginx comes up it MUST present a valid
# *.vrittiai.dev Let's Encrypt cert (DNS-01) or CF returns 526. No later flip needed.
resource "cloudflare_zone_settings_override" "dev" {
  zone_id = local.cf_dev_zone_id

  settings {
    ssl = "strict"
  }

  lifecycle {
    ignore_changes = [initial_settings]
  }
}
