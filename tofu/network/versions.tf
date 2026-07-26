# Network layer — the reserved public IPs live here, in their OWN state, so a
# `tofu destroy` in the compute layer can never touch them. Same R2 bucket, different key.
terraform {
  required_version = ">= 1.10"

  required_providers {
    excloud = {
      source  = "excloud-dev/excloud"
      version = "~> 0.2"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3"
    }
  }

  backend "s3" {
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

    use_lockfile = true
  }
}
