locals {
  # Look the image id up by name (ids change as "latest" images are rebuilt).
  image = one([for i in data.excloud_compute_images.all.images : i if i.name == var.image_name])
  # The single DEFAULT subnet in the chosen zone.
  subnet = one([for s in data.excloud_subnets.zone.subnets : s if s.name == "DEFAULT"])
}

# One agent-managed core deployment VM (apw1, apw2, …): prod core-server/web + commerce + Gitea add-on
# + tenant static sites + prod Postgres, plus the Vritti agent. Attaches the shared vritti-core SG; the
# reserved public IP is passed in from the network layer, so destroying the VM never touches the IP.
resource "excloud_compute_instance" "this" {
  name          = "vritti-${var.name}"
  zone_id       = local.subnet.zone_id
  subnet_id     = local.subnet.id
  image_id      = local.image.id
  instance_type = var.instance_type
  ssh_pubkey    = var.ssh_pubkey

  # Shared `vritti-core` SG (from the network layer) — SSH from admin IP + world-open 80/443 + git-SSH
  # + acme-dns :53 (direct-served, agent's own nginx + Let's Encrypt). Every core VM uses the same one.
  security_group_ids = [var.sg_id]

  allocate_public_ipv4       = true
  public_ipv4_reservation_id = var.ip_reservation_id

  root_volume = {
    name                     = "vritti-${var.name}-root"
    size_gib                 = var.root_gib
    baseline_iops            = var.root_baseline_iops
    baseline_throughput_mbps = var.root_baseline_throughput_mbps
  }
}

# No separate volume — everything (Docker, vritti-core, static sites, prod Postgres, pgbackrest) lives
# on the disposable root. DB durability is pgBackRest → R2; on a rebuild Ansible restores from R2.
