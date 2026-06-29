output "k3s_private_ip" {
  description = "Private IP of k3s VM."
  value       = yandex_compute_instance.k3s.network_interface[0].ip_address
}

output "k3s_public_ip" {
  description = "Public IP of k3s VM (when NAT is enabled)."
  value       = try(yandex_compute_instance.k3s.network_interface[0].nat_ip_address, null)
}

output "k3s_vm_id" {
  description = "Yandex Cloud VM ID for k3s node."
  value       = yandex_compute_instance.k3s.id
}

output "k3s_security_group_id" {
  description = "Security group ID attached to k3s VM."
  value       = yandex_vpc_security_group.k3s_sg.id
}

output "kube_api_endpoint" {
  description = "Kubernetes API endpoint (external)."
  value       = "https://${try(yandex_compute_instance.k3s.network_interface[0].nat_ip_address, yandex_compute_instance.k3s.network_interface[0].ip_address)}:6443"
}

output "runner_private_ip" {
  description = "Private IP of runner VM (when runner_enabled)."
  value       = local.runner_private_ip
}

output "runner_vm_id" {
  description = "Yandex Cloud VM ID for runner node (when runner_enabled)."
  value       = local.runner_vm_id
}

output "runner_security_group_id" {
  description = "Security group ID attached to runner VM (when runner_enabled)."
  value       = local.runner_sg_id
}

output "ansible_inventory_yaml" {
  description = "Generated inventory for k3s and runner bootstrap (runner rendered under private_hosts/github_runners when enabled)."
  value       = local.ansible_inventory_yaml
}
