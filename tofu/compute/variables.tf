# Input variables. Non-secret configuration only — secrets come from Infisical.

variable "zone_id" {
  description = "Excloud zone to deploy into"
  type        = number
  default     = 1
}

variable "image_name" {
  description = "Compute image to boot (looked up by name → id)"
  type        = string
  default     = "ubuntu-24.04-latest"
}

variable "SSH_PUBLIC_KEY" {
  description = "SSH public key text for the VMs (Infisical: TF_VAR_SSH_PUBLIC_KEY)"
  type        = string
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

# --- VM1: control / build / dev ---
variable "vm1_instance_type" {
  description = "VM1 size (2 vCPU / 4 GB)"
  type        = string
  default     = "t1a.medium"
}

variable "vm1_root_gib" {
  description = "VM1 root disk (25 GiB is included with the instance type; not worth shrinking)"
  type        = number
  default     = 25
}

# --- VM2: production ---
variable "vm2_instance_type" {
  description = "VM2 size (2 vCPU / 2 GB)"
  type        = string
  default     = "t1a.small"
}

variable "vm2_root_gib" {
  description = "VM2 root disk (25 GiB is included with the instance type; not worth shrinking)"
  type        = number
  default     = 25
}

# No data-volume variables — VMs run with root only. DBs live on root; durability via
# pgBackRest → R2. Excloud charges a ~Rs376/mo floor per separate volume (min 3000 IOPS +
# 125 MB/s), so we deliberately keep zero of them.

# --- Root volume performance (kept minimal; these are provisioned-perf knobs) ---
variable "root_baseline_iops" {
  description = "Baseline IOPS for root volumes (Excloud minimum is 3000)"
  type        = number
  default     = 3000
}

variable "root_baseline_throughput_mbps" {
  description = "Baseline throughput MB/s for root volumes (Excloud minimum is 125)"
  type        = number
  default     = 125
}
