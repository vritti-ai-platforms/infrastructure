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
resource "excloud_compute_instance" "cloud" {
  name          = "vritti-cloud"
  zone_id       = local.subnet.zone_id
  subnet_id     = local.subnet.id
  image_id      = local.image.id
  instance_type = var.cloud_instance_type
  ssh_pubkey    = var.SSH_PUBLIC_KEY

  security_group_ids = [tonumber(excloud_security_group.vritti.id)]

  # Reserved IP comes from the network layer's state — this VM never manages it,
  # so destroying the VM leaves the IP intact.
  allocate_public_ipv4       = true
  public_ipv4_reservation_id = data.terraform_remote_state.network.outputs.cloud_ip_id

  root_volume = {
    name                     = "vritti-vm1-root"
    size_gib                 = var.cloud_root_gib
    baseline_iops            = var.root_baseline_iops
    baseline_throughput_mbps = var.root_baseline_throughput_mbps
  }
}

# No separate volumes on VM1 — everything (Docker, apps, clouddb + dev-core Postgres,
# DBLab, pgbackrest) lives on the disposable root. DB durability is pgBackRest → Cloudflare R2
# (continuous WAL archiving); on a VM rebuild, Ansible restores from R2. This avoids the
# ~Rs376/mo-per-volume IOPS+throughput floor Excloud charges on every separate volume.

# VM2 (production / agent host) now lives in its own root: infrastructure/tofu/vm2/
# (own state key vm2/terraform.tfstate), so it can be created/destroyed independently of vm1.
