# Shared security group for EVERY agent-hosted core VM (apw1, apw2, …). They all run the same
# direct-served stack (agent nginx + Let's Encrypt), so ONE SG serves them all: SSH from the admin IP
# + HTTP/HTTPS + git-SSH + acme-dns :53 open to the world. Lives in the network layer (shared infra,
# like the reserved IPs) so every core root references the same SG id via remote state instead of
# each minting its own. The cloud VM is separate — it has its own Cloudflare-locked `vritti-cloud` SG
# in the cloud/ root (proxied origin), not this world-open one.
resource "excloud_security_group" "core" {
  name        = "vritti-core"
  description = "core VMs: SSH from admin IP; HTTP/HTTPS + git-SSH + acme-dns open to the world (direct-served, agent nginx + LE)"
}

resource "excloud_security_group_rule" "core_ssh" {
  security_group_id = tonumber(excloud_security_group.core.id)
  description       = "SSH from admin IP"
  is_ingress        = true
  protocol          = "TCPv4"
  port_range        = "22"
  cidr              = var.ssh_allowed_cidr
}

resource "excloud_security_group_rule" "core_http" {
  security_group_id = tonumber(excloud_security_group.core.id)
  description       = "HTTP public (Let's Encrypt HTTP-01 + http->https redirect)"
  is_ingress        = true
  protocol          = "TCPv4"
  port_range        = "80"
  cidr              = "0.0.0.0/0"
}

resource "excloud_security_group_rule" "core_https" {
  security_group_id = tonumber(excloud_security_group.core.id)
  description       = "HTTPS public (core + per-tenant subdomains)"
  is_ingress        = true
  protocol          = "TCPv4"
  port_range        = "443"
  cidr              = "0.0.0.0/0"
}

resource "excloud_security_group_rule" "core_git_ssh" {
  security_group_id = tonumber(excloud_security_group.core.id)
  description       = "Git SSH (Gitea add-on) — clones over ssh://git@…:2222"
  is_ingress        = true
  protocol          = "TCPv4"
  port_range        = "2222"
  cidr              = "0.0.0.0/0"
}

resource "excloud_security_group_rule" "core_dns_udp" {
  security_group_id = tonumber(excloud_security_group.core.id)
  description       = "acme-dns DNS-01 (UDP) — Let's Encrypt resolves the wildcard challenge here"
  is_ingress        = true
  protocol          = "UDPv4"
  port_range        = "53"
  cidr              = "0.0.0.0/0"
}

resource "excloud_security_group_rule" "core_dns_tcp" {
  security_group_id = tonumber(excloud_security_group.core.id)
  description       = "acme-dns DNS-01 (TCP fallback)"
  is_ingress        = true
  protocol          = "TCPv4"
  port_range        = "53"
  cidr              = "0.0.0.0/0"
}
