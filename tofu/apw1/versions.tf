# vm2 (apw1 prod core / agent host) — its OWN state, separate from vm1 and network, so vm2 can be
# created/destroyed without ever touching vm1 or the reserved IPs. Same R2 bucket, distinct key.
# Credentials arrive as env vars via `infisical run`; never in this file.

terraform {
  required_version = ">= 1.10"

  required_providers {
    excloud = {
      source  = "excloud-dev/excloud"
      version = "~> 0.2"
    }
  }

  backend "s3" {
    bucket = "vritti-tfstate"
    key    = "apw1/terraform.tfstate"
    region = "auto"

    endpoints = {
      s3 = "https://45131bc1e1eb60fabc1b7991b762489f.r2.cloudflarestorage.com"
    }

    # R2 is not AWS — skip the AWS-only preflight checks.
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_s3_checksum            = true
    use_path_style              = true

    use_lockfile = true
  }
}
