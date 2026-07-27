variable "zone_id" {
  description = "Excloud zone for the reserved IPs"
  type        = number
  default     = 1
}

variable "dns_zone_name" {
  description = "Cloudflare zone (domain) that DNS records live under"
  type        = string
  default     = "vrittiai.com"
}

# Provider credentials from Infisical (TF_VAR_*). Wired to the providers in providers.tf.
variable "EXCLOUD_API_KEY" {
  type      = string
  sensitive = true
}
variable "EXCLOUD_ORG_ID" {
  type      = string
  sensitive = true
}
variable "ANSI_CLOUDFLARE_API_TOKEN" {
  description = "Cloudflare API token — also consumed by ansible (TF_VAR_ANSI_CLOUDFLARE_API_TOKEN)"
  type        = string
  sensitive   = true
}
