# Two brand-new VMs + their own reserved IPs. This does NOT touch your existing
# Infisical VM or the current all-in-one VM — those aren't in Tofu state, so they're
# invisible to it. Everything here is `+ create` only.

locals {
  # Look the image id up by name (ids change as "latest" images are rebuilt).
  image = one([for i in data.excloud_compute_images.all.images : i if i.name == var.image_name])
  # The single DEFAULT subnet in the chosen zone.
  subnet = one([for s in data.excloud_subnets.zone.subnets : s if s.name == "DEFAULT"])
}

# The public key is already registered in Excloud (as "macbook-m3pro"). We pass it
# straight to each instance's ssh_pubkey — no separate excloud_ssh_key resource needed.

# =========================================================
# VM1 — control / build / dev
# (cloud-server/web, dev core, commerce, Gitea+runner, DBLab, clouddb+dev-core PG)
# =========================================================
resource "excloud_compute_instance" "vm1" {
  name          = "vritti-vm1"
  zone_id       = local.subnet.zone_id
  subnet_id     = local.subnet.id
  image_id      = local.image.id
  instance_type = var.vm1_instance_type
  ssh_pubkey    = var.ssh_public_key

  security_group_ids = [tonumber(excloud_security_group.vritti.id)]

  # Reserved IP comes from the network layer's state — this VM never manages it,
  # so destroying the VM leaves the IP intact.
  allocate_public_ipv4       = true
  public_ipv4_reservation_id = data.terraform_remote_state.network.outputs.vm1_ip_id

  root_volume = {
    name                     = "vritti-vm1-root"
    size_gib                 = var.vm1_root_gib
    baseline_iops            = var.root_baseline_iops
    baseline_throughput_mbps = var.root_baseline_throughput_mbps
  }
}

# No separate volumes on VM1 — everything (Docker, apps, clouddb + dev-core Postgres,
# DBLab, pgbackrest) lives on the disposable root. DB durability is pgBackRest → Cloudflare R2
# (continuous WAL archiving); on a VM rebuild, Ansible restores from R2. This avoids the
# ~Rs376/mo-per-volume IOPS+throughput floor Excloud charges on every separate volume.

# =========================================================
# VM2 — production serving
# (prod core-server/web, commerce, prod Gitea+runner, client static sites, proddb)
# =========================================================
resource "excloud_compute_instance" "vm2" {
  name          = "vritti-vm2"
  zone_id       = local.subnet.zone_id
  subnet_id     = local.subnet.id
  image_id      = local.image.id
  instance_type = var.vm2_instance_type
  ssh_pubkey    = var.ssh_public_key

  security_group_ids = [tonumber(excloud_security_group.vritti.id)]

  # Reserved IP comes from the network layer's state (see VM1 note).
  allocate_public_ipv4       = true
  public_ipv4_reservation_id = data.terraform_remote_state.network.outputs.vm2_ip_id

  root_volume = {
    name                     = "vritti-vm2-root"
    size_gib                 = var.vm2_root_gib
    baseline_iops            = var.root_baseline_iops
    baseline_throughput_mbps = var.root_baseline_throughput_mbps
  }
}

# No separate volume on VM2 — everything (Docker, vritti-core, static sites, prod Postgres,
# pgbackrest) lives on the disposable root. DB durability is pgBackRest → Cloudflare R2
# (continuous WAL archiving); on a VM rebuild, Ansible restores from R2.
