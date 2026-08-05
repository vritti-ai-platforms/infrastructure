# Reserved public IPs — permanent infrastructure. prevent_destroy guards them here, and the
# compute layer only READS their ids (via remote state), so destroying the VMs never releases
# them. To intentionally release an IP: remove its prevent_destroy here, then destroy this layer.

resource "excloud_public_ipv4" "cloud" {
  zone_id = var.zone_id
  name    = "vritti-cloud"

  lifecycle {
    prevent_destroy = true
  }
}

resource "excloud_public_ipv4" "apw1" {
  zone_id = var.zone_id
  name    = "vritti-apw1"

  lifecycle {
    prevent_destroy = true
  }
}
