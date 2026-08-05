# Outputs surface values other tools consume — the VM IPs feed Ansible's inventory.

output "cloud_public_ipv4" {
  description = "VM1 (control/dev) public IP"
  value       = data.terraform_remote_state.network.outputs.cloud_ip
}

output "cloud_instance_id" {
  value = excloud_compute_instance.cloud.id
}
