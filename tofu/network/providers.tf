# Reads EXCLOUD_API_KEY / EXCLOUD_ORG_ID from the environment (injected by `infisical run`).
provider "excloud" {}

# Reads CLOUDFLARE_API_TOKEN from the environment (needs Zone:DNS:Edit on vrittiai.com).
provider "cloudflare" {}
