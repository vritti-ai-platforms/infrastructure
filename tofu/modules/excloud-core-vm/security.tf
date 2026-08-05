# Each core VM owns its security groups outright (kept separate per VM):
#   admin  — SSH from the admin IP only.
#   public — HTTP/HTTPS + git-SSH + acme-dns :53 open to the WORLD. These VMs are served DIRECT
#            (grey-cloud DNS → the VM), not through Cloudflare: the agent's nginx terminates TLS with
#            Let's Encrypt (HTTP-01 + wildcard DNS-01 via the bundled acme-dns), so web ports are
#            world-open rather than Cloudflare-locked.

resource "excloud_security_group" "admin" {
  name        = "vritti-${var.name}-admin"
  description = "${var.name}: SSH from admin IP"
}

resource "excloud_security_group_rule" "ssh" {
  security_group_id = tonumber(excloud_security_group.admin.id)
  description       = "SSH from admin IP"
  is_ingress        = true
  protocol          = "TCPv4"
  port_range        = "22"
  cidr              = var.ssh_allowed_cidr
}

resource "excloud_security_group" "public" {
  name        = "vritti-${var.name}-public"
  description = "${var.name}: HTTP/HTTPS + git-SSH + acme-dns open to the world (direct-served, agent nginx + LE)"
}

resource "excloud_security_group_rule" "http_public" {
  security_group_id = tonumber(excloud_security_group.public.id)
  description       = "HTTP public (Let's Encrypt HTTP-01 + http->https redirect)"
  is_ingress        = true
  protocol          = "TCPv4"
  port_range        = "80"
  cidr              = "0.0.0.0/0"
}

resource "excloud_security_group_rule" "https_public" {
  security_group_id = tonumber(excloud_security_group.public.id)
  description       = "HTTPS public (core + per-tenant subdomains)"
  is_ingress        = true
  protocol          = "TCPv4"
  port_range        = "443"
  cidr              = "0.0.0.0/0"
}

resource "excloud_security_group_rule" "git_ssh_public" {
  security_group_id = tonumber(excloud_security_group.public.id)
  description       = "Git SSH (Gitea add-on) — clones over ssh://git@…:2222"
  is_ingress        = true
  protocol          = "TCPv4"
  port_range        = "2222"
  cidr              = "0.0.0.0/0"
}

resource "excloud_security_group_rule" "dns_udp_public" {
  security_group_id = tonumber(excloud_security_group.public.id)
  description       = "acme-dns DNS-01 (UDP) — Let's Encrypt resolves the wildcard challenge here"
  is_ingress        = true
  protocol          = "UDPv4"
  port_range        = "53"
  cidr              = "0.0.0.0/0"
}

resource "excloud_security_group_rule" "dns_tcp_public" {
  security_group_id = tonumber(excloud_security_group.public.id)
  description       = "acme-dns DNS-01 (TCP fallback)"
  is_ingress        = true
  protocol          = "TCPv4"
  port_range        = "53"
  cidr              = "0.0.0.0/0"
}
