# Credentials come from Infisical as TF_VAR_* (mapped to the variables below); no raw env reads.
#   TF_VAR_EXCLOUD_API_KEY, TF_VAR_EXCLOUD_ORG_ID   -> excloud
#   TF_VAR_ANSI_CLOUDFLARE_API_TOKEN                -> cloudflare (also used by ansible)
provider "excloud" {
  api_key = var.EXCLOUD_API_KEY
  org_id  = var.EXCLOUD_ORG_ID
}

provider "cloudflare" {
  api_token = var.ANSI_CLOUDFLARE_API_TOKEN
}
