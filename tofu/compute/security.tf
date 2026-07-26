# Security group — the only inbound the VMs accept.
# Zero-Trust services (dblab/admin/git) need NO inbound: cloudflared dials OUT to Cloudflare.
# So we open just SSH (from the admin IP) + the public web ports for tenant traffic + ACME.
# Egress is left at the provider default (allow-all) so cloudflared/apt/docker/R2 work.

variable "ssh_allowed_cidr" {
  description = "CIDR allowed to SSH in (your current public IP; update when it changes)"
  type        = string
  default     = "49.238.34.78/32"
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

resource "excloud_security_group_rule" "http" {
  security_group_id = tonumber(excloud_security_group.vritti.id)
  description       = "HTTP — public web + ACME/Let's Encrypt"
  is_ingress        = true
  protocol          = "TCPv4"
  port_range        = "80"
  cidr              = "0.0.0.0/0"
}

resource "excloud_security_group_rule" "https" {
  security_group_id = tonumber(excloud_security_group.vritti.id)
  description       = "HTTPS — public web"
  is_ingress        = true
  protocol          = "TCPv4"
  port_range        = "443"
  cidr              = "0.0.0.0/0"
}
