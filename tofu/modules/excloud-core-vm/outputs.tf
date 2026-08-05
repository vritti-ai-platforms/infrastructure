output "instance_id" {
  description = "Excloud compute instance id"
  value       = excloud_compute_instance.this.id
}

output "admin_sg_id" {
  value = excloud_security_group.admin.id
}

output "public_sg_id" {
  value = excloud_security_group.public.id
}
