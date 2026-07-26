# Read-only lookups against the Excloud API. Data sources never create anything —
# they fetch info so we don't hardcode volatile IDs (image ids change as images update).

data "excloud_compute_images" "all" {}

data "excloud_subnets" "zone" {
  zone_id = var.zone_id
}

# Read the network layer's state (reserved IP ids) from R2. READ-ONLY — the compute layer
# never manages the IPs, so `tofu destroy` here leaves them untouched.
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "vritti-tfstate"
    key    = "network/terraform.tfstate"
    region = "auto"
    endpoints = {
      s3 = "https://45131bc1e1eb60fabc1b7991b762489f.r2.cloudflarestorage.com"
    }
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_s3_checksum            = true
    use_path_style              = true
  }
}
