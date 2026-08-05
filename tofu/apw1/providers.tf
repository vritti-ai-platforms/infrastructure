# Credentials come from Infisical as TF_VAR_* (no raw env reads).
#   TF_VAR_EXCLOUD_API_KEY, TF_VAR_EXCLOUD_ORG_ID -> excloud
# vm2 provisions only compute + security groups, so it needs the excloud provider alone (no cloudflare).
provider "excloud" {
  api_key = var.EXCLOUD_API_KEY
  org_id  = var.EXCLOUD_ORG_ID
}
