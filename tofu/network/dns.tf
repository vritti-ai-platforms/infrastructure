# Cloudflare DNS — permanent, lives with the reserved IPs it points at. Because the records
# are in this same module, they reference the IP resources directly (no remote state).

data "cloudflare_zones" "main" {
  filter {
    name = var.dns_zone_name
  }
}

locals {
  cf_zone_id = data.cloudflare_zones.main.zones[0].id

  vm_ip = {
    vm1 = excloud_public_ipv4.vm1.ip
    vm2 = excloud_public_ipv4.vm2.ip
  }

  # Wildcards — one A record per VM; nginx on each VM does host-based routing (api., dblab.,
  # cloud., admin., per-tenant, ...) and terminates TLS via Let's Encrypt.
  #   vm      = "vm1" | "vm2"   (which VM's reserved IP to point at)
  #   proxied = false everywhere — proxied WILDCARDS need a Cloudflare Business plan, and
  #             nginx handles TLS anyway. (A specific record could be proxied later.)
  #
  # DNS wildcards only match ONE label, so *.vrittiai.com and *.dev.vrittiai.com are distinct.
  # Explicit vm1/vm2 records win over the wildcard → stable names for SSH/Ansible.
  dns_records = {
    "*"      = { vm = "vm1", proxied = false } # *.vrittiai.com      → VM1
    "*.dev"  = { vm = "vm1", proxied = false } # *.dev.vrittiai.com  → VM1
    "*.apw1" = { vm = "vm2", proxied = false } # *.apw1.vrittiai.com → VM2 (AP-West-1: India + Gulf)

    # cloud. is PROXIED (orange cloud): DNS returns Cloudflare IPs (origin hidden), CF terminates
    # TLS + runs DDoS/WAF, then reaches nginx over the internet (Full-Strict, validated against the
    # Let's Encrypt cert). The security group then locks :80/:443 to Cloudflare ranges so the origin
    # can't be hit directly. A SPECIFIC record beats the "*" wildcard, so this wins for cloud.
    cloud = { vm = "vm1", proxied = true }

    # api. is the PUBLIC machine API (agent enroll/desired-state/status). Proxied like cloud. — CF
    # WAF/DDoS/rate-limiting at the edge, firewall stays CF-locked — but NOT Access-gated: the agent
    # authenticates with its own Ed25519 + enroll token, so no service token lives on any VM.
    api = { vm = "vm1", proxied = true }
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
