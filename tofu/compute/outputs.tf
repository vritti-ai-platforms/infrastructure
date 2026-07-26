# Outputs surface values other tools consume — the VM IPs feed Ansible's inventory.

output "vm1_public_ipv4" {
  description = "VM1 (control/dev) public IP"
  value       = data.terraform_remote_state.network.outputs.vm1_ip
}

output "vm2_public_ipv4" {
  description = "VM2 (prod) public IP"
  value       = data.terraform_remote_state.network.outputs.vm2_ip
}

output "vm1_instance_id" {
  value = excloud_compute_instance.vm1.id
}

output "vm2_instance_id" {
  value = excloud_compute_instance.vm2.id
}
