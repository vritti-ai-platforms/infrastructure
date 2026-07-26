# The compute layer consumes these via terraform_remote_state.

output "vm1_ip_id" {
  description = "VM1 reserved IP reservation id"
  value       = tonumber(excloud_public_ipv4.vm1.id)
}

output "vm2_ip_id" {
  description = "VM2 reserved IP reservation id"
  value       = tonumber(excloud_public_ipv4.vm2.id)
}

output "vm1_ip" {
  description = "VM1 reserved IP address"
  value       = excloud_public_ipv4.vm1.ip
}

output "vm2_ip" {
  description = "VM2 reserved IP address"
  value       = excloud_public_ipv4.vm2.ip
}

# Only vm1 runs a tunnel (admin/dblab/dev-git). vm2 (prod core) has none — it's public + SSH.
output "vm1_tunnel_token" {
  description = "Token cloudflared uses to run the VM1 tunnel (Ansible injects this on the VM)"
  value       = cloudflare_zero_trust_tunnel_cloudflared.vm["vm1"].tunnel_token
  sensitive   = true
}

# Access service token for headless clients hitting admin.vrittiai.com (scripts, Postman, CI).
# Fetch after apply:  tofu output -raw admin_service_token_client_id / _secret
output "admin_service_token_client_id" {
  description = "CF-Access-Client-Id header value for admin. programmatic access"
  value       = cloudflare_zero_trust_access_service_token.admin.client_id
  sensitive   = true
}

output "admin_service_token_client_secret" {
  description = "CF-Access-Client-Secret header value (only retrievable at/near creation)"
  value       = cloudflare_zero_trust_access_service_token.admin.client_secret
  sensitive   = true
}
