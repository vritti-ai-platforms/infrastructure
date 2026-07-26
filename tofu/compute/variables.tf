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

variable "ssh_public_key" {
  description = "SSH public key text for the VMs (injected from Infisical as TF_VAR_ssh_public_key)"
  type        = string
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
