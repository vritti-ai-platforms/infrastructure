output "apw1_public_ipv4" {
  description = "apw1 public IP"
  value       = data.terraform_remote_state.network.outputs.apw1_ip
}

output "apw1_instance_id" {
  value = module.vm.instance_id
}
