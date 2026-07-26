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

    vm1 = { vm = "vm1", proxied = false }
    vm2 = { vm = "vm2", proxied = false }
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
