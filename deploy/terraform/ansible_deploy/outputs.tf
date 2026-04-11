output "private_ips" {
  description = "Private IPs for all VMs."
  value = {
    for name, vm in yandex_compute_instance.vm :
    name => vm.network_interface[0].ip_address
  }
}

output "public_ips" {
  description = "Public IPs for VMs with NAT enabled."
  value = {
    for name, vm in yandex_compute_instance.vm :
    name => try(vm.network_interface[0].nat_ip_address, null)
  }
}

output "ansible_inventory_yaml" {
  description = "Generated inventory (hosts.yml) for deploy/ansible."
  value = trimspace(<<-YAML
    ---
    all:
      children:
        db_hosts:
          hosts:
            db:
              ansible_host: ${yandex_compute_instance.vm["db"].network_interface[0].ip_address}
              private_ip: ${yandex_compute_instance.vm["db"].network_interface[0].ip_address}

        ollama_hosts:
          hosts:
            ollama:
              ansible_host: ${yandex_compute_instance.vm["ollama"].network_interface[0].ip_address}
              private_ip: ${yandex_compute_instance.vm["ollama"].network_interface[0].ip_address}

        n8n_hosts:
          hosts:
            n8n:
              ansible_host: ${yandex_compute_instance.vm["n8n"].network_interface[0].ip_address}
              private_ip: ${yandex_compute_instance.vm["n8n"].network_interface[0].ip_address}

        private_hosts:
          children:
            db_hosts: {}
            ollama_hosts: {}
            n8n_hosts: {}

        wiki_hosts:
          hosts:
            wiki:
              ansible_host: ${yandex_compute_instance.vm["wiki"].network_interface[0].nat_ip_address}
              private_ip: ${yandex_compute_instance.vm["wiki"].network_interface[0].ip_address}

        docker_hosts:
          children:
            db_hosts: {}
            ollama_hosts: {}
            n8n_hosts: {}
            wiki_hosts: {}
    YAML
  )
}

output "security_group_ids" {
  description = "Created security groups for bastion and private VMs."
  value = {
    bastion = yandex_vpc_security_group.bastion_sg.id
    private = yandex_vpc_security_group.private_sg.id
  }
}
