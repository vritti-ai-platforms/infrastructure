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
