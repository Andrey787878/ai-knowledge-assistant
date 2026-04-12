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

output "ansible_inventory_yaml" {
  description = "Generated inventory for k3s bootstrap."
  value = trimspace(<<-YAML
    ---
    all:
      children:
        k3s_hosts:
          hosts:
            k3s:
              ansible_host: ${try(yandex_compute_instance.k3s.network_interface[0].nat_ip_address, yandex_compute_instance.k3s.network_interface[0].ip_address)}
              private_ip: ${yandex_compute_instance.k3s.network_interface[0].ip_address}
    YAML
  )
}
