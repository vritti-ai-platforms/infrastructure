# Security group — the only inbound the VMs accept.
# Zero-Trust services (dblab/admin/git) need NO inbound: cloudflared dials OUT to Cloudflare.
# Web ports (80/443) are locked to CLOUDFLARE'S IP RANGES only — cloud. is proxied (orange cloud),
# so all legit web traffic arrives FROM Cloudflare's edge. This blocks direct-to-origin bypass:
# even if someone finds the VM IP, the firewall drops anything that isn't Cloudflare. SSH stays
# pinned to the admin IP. Egress is provider-default allow-all (cloudflared/apt/docker/R2).

variable "ssh_allowed_cidr" {
  description = "CIDR allowed to SSH in (your current public IP; update when it changes)"
  type        = string
  default     = "49.238.35.31/32"
}

# Cloudflare edge IPv4 ranges (https://www.cloudflare.com/ips-v4). All proxied web traffic to the
# origin comes from these. Refresh if Cloudflare publishes changes (rare).
variable "cloudflare_ipv4_cidrs" {
  description = "Cloudflare edge IPv4 CIDRs allowed to reach the origin on 80/443"
  type        = list(string)
  default = [
    "173.245.48.0/20", "103.21.244.0/22", "103.22.200.0/22", "103.31.4.0/22",
    "141.101.64.0/18", "108.162.192.0/18", "190.93.240.0/20", "188.114.96.0/20",
    "197.234.240.0/22", "198.41.128.0/17", "162.158.0.0/15", "104.16.0.0/13",
    "104.24.0.0/14", "172.64.0.0/13", "131.0.72.0/22",
  ]
}

resource "excloud_security_group" "vritti" {
  name        = "vritti"
  description = "SSH from admin IP; HTTP/HTTPS public; everything else denied"
}

resource "excloud_security_group_rule" "ssh" {
  security_group_id = tonumber(excloud_security_group.vritti.id)
  description       = "SSH from admin IP"
  is_ingress        = true
  protocol          = "TCPv4"
  port_range        = "22"
  cidr              = var.ssh_allowed_cidr
}

# HTTP/HTTPS from Cloudflare edge only (one rule per CF CIDR). cloud. is proxied, so all legit web
# traffic arrives from these ranges; direct-to-origin from any other IP is dropped.
resource "excloud_security_group_rule" "http_cf" {
  for_each          = toset(var.cloudflare_ipv4_cidrs)
  security_group_id = tonumber(excloud_security_group.vritti.id)
  description       = "HTTP from Cloudflare (${each.value})"
  is_ingress        = true
  protocol          = "TCPv4"
  port_range        = "80"
  cidr              = each.value
}

resource "excloud_security_group_rule" "https_cf" {
  for_each          = toset(var.cloudflare_ipv4_cidrs)
  security_group_id = tonumber(excloud_security_group.vritti.id)
  description       = "HTTPS from Cloudflare (${each.value})"
  is_ingress        = true
  protocol          = "TCPv4"
  port_range        = "443"
  cidr              = each.value
}

# vm2 (apw1 prod core) is served DIRECT (grey-cloud DNS → vm2), not through Cloudflare: the agent's
# own nginx terminates TLS with Let's Encrypt certs it obtains via HTTP-01. So vm2 needs :80/:443
# open to the WORLD (HTTP-01 + public HTTPS) plus git-SSH for the Gitea add-on — unlike vm1, whose
# web ports stay Cloudflare-locked. This is a SEPARATE group; vm2 carries both (vritti = admin SSH).
resource "excloud_security_group" "vm2_public" {
  name        = "vritti-vm2-public"
  description = "vm2 apw1: HTTP/HTTPS + git-SSH open to the world (direct-served, agent nginx + LE)"
}

resource "excloud_security_group_rule" "vm2_http_public" {
  security_group_id = tonumber(excloud_security_group.vm2_public.id)
  description       = "HTTP public (Let's Encrypt HTTP-01 + http->https redirect)"
  is_ingress        = true
  protocol          = "TCPv4"
  port_range        = "80"
  cidr              = "0.0.0.0/0"
}

resource "excloud_security_group_rule" "vm2_https_public" {
  security_group_id = tonumber(excloud_security_group.vm2_public.id)
  description       = "HTTPS public (apw1 core + per-tenant)"
  is_ingress        = true
  protocol          = "TCPv4"
  port_range        = "443"
  cidr              = "0.0.0.0/0"
}

resource "excloud_security_group_rule" "vm2_git_ssh_public" {
  security_group_id = tonumber(excloud_security_group.vm2_public.id)
  description       = "Git SSH (Gitea add-on) — clones over ssh://git@…:2222"
  is_ingress        = true
  protocol          = "TCPv4"
  port_range        = "2222"
  cidr              = "0.0.0.0/0"
}

# The bundled acme-dns is authoritative for acme.<base> and must be reachable by Let's Encrypt's
# resolvers (from anywhere) to answer the wildcard DNS-01 challenge TXT. DNS is UDP with a TCP
# fallback, so both. Without this the cloud firewall drops all :53 and the wildcard never issues.
resource "excloud_security_group_rule" "vm2_dns_udp_public" {
  security_group_id = tonumber(excloud_security_group.vm2_public.id)
  description       = "acme-dns DNS-01 (UDP) — Let's Encrypt resolves the wildcard challenge here"
  is_ingress        = true
  protocol          = "UDPv4"
  port_range        = "53"
  cidr              = "0.0.0.0/0"
}

resource "excloud_security_group_rule" "vm2_dns_tcp_public" {
  security_group_id = tonumber(excloud_security_group.vm2_public.id)
  description       = "acme-dns DNS-01 (TCP fallback)"
  is_ingress        = true
  protocol          = "TCPv4"
  port_range        = "53"
  cidr              = "0.0.0.0/0"
}
