# Reusable agent-managed deployment VM (apw1, apw2, …): one compute instance attached to the SHARED
# vritti-core security group (passed in as sg_id from the network layer). Parameterized so each
# deployment is a ~10-line thin root. No backend/provider here — those live in the calling root.

variable "name" {
  description = "Short deployment name, e.g. apw1 / apw2. Drives instance + SG names (vritti-<name>…)."
  type        = string
}

variable "ip_reservation_id" {
  description = "Reserved public-IPv4 reservation id (from the network layer) to attach to this VM."
  type        = number
}

variable "ssh_pubkey" {
  description = "SSH public key text for the VM."
  type        = string
}

variable "sg_id" {
  description = "Shared core security group id (vritti-core, from the network layer)."
  type        = number
}

variable "instance_type" {
  description = "Excloud instance size."
  type        = string
  default     = "t1a.small"
}

variable "root_gib" {
  description = "Root disk size (GiB); 25 is included with the instance type."
  type        = number
  default     = 25
}

variable "zone_id" {
  description = "Excloud zone to deploy into."
  type        = number
  default     = 1
}

variable "image_name" {
  description = "Compute image to boot (looked up by name → id)."
  type        = string
  default     = "ubuntu-24.04-latest"
}

variable "root_baseline_iops" {
  description = "Baseline IOPS for the root volume (Excloud minimum is 3000)."
  type        = number
  default     = 3000
}

variable "root_baseline_throughput_mbps" {
  description = "Baseline throughput MB/s for the root volume (Excloud minimum is 125)."
  type        = number
  default     = 125
}
