# Pins OpenTofu + provider versions, and points state at Cloudflare R2 (S3-compatible).
# Credentials are NEVER in this file — they arrive as env vars via `infisical run`.

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
  }

  # Remote state in R2. R2 speaks the S3 API, so we use the "s3" backend with
  # AWS-specific behaviors disabled. AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY
  # come from the environment (injected by `infisical run`).
  backend "s3" {
    bucket = "vritti-tfstate"
    key    = "prod/terraform.tfstate"
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

    # Native state locking via a lockfile in the bucket (no DynamoDB). Requires OpenTofu >= 1.10.
    use_lockfile = true
  }
}
