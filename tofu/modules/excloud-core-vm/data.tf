# Read-only lookups against the Excloud API (uses the calling root's excloud provider).
data "excloud_compute_images" "all" {}

data "excloud_subnets" "zone" {
  zone_id = var.zone_id
}
