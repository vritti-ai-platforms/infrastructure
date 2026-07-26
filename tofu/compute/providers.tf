# Provider configuration. Both blocks are intentionally empty — each provider
# reads its credentials from environment variables that `infisical run` injects:
#   excloud    → EXCLOUD_API_KEY, EXCLOUD_ORG_ID
#   cloudflare → CLOUDFLARE_API_TOKEN

provider "excloud" {}

provider "cloudflare" {}
