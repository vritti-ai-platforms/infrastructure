# Provider credentials + SSH key from Infisical (TF_VAR_*). Sizing/SG defaults live in the module.
variable "EXCLOUD_API_KEY" {
  type      = string
  sensitive = true
}
variable "EXCLOUD_ORG_ID" {
  type      = string
  sensitive = true
}
variable "SSH_PUBLIC_KEY" {
  description = "SSH public key text for the VM (Infisical: TF_VAR_SSH_PUBLIC_KEY)"
  type        = string
}
