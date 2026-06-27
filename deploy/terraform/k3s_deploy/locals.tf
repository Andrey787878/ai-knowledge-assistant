locals {
  k3s_spec    = var.vm_specs["k3s_vm"]
  runner_spec = var.vm_specs["runner_vm"]

  k3s_ansible_host = try(yandex_compute_instance.k3s.network_interface[0].nat_ip_address, yandex_compute_instance.k3s.network_interface[0].ip_address)
  k3s_private_ip   = yandex_compute_instance.k3s.network_interface[0].ip_address

  runner_present      = var.runner_enabled && length(yandex_compute_instance.runner) > 0
  runner_ansible_host = local.runner_present ? try(yandex_compute_instance.runner[0].network_interface[0].nat_ip_address, yandex_compute_instance.runner[0].network_interface[0].ip_address) : null
  runner_private_ip   = local.runner_present ? yandex_compute_instance.runner[0].network_interface[0].ip_address : null
  runner_public_ip    = local.runner_present ? try(yandex_compute_instance.runner[0].network_interface[0].nat_ip_address, null) : null
  runner_vm_id        = local.runner_present ? yandex_compute_instance.runner[0].id : null
  runner_sg_id        = local.runner_present ? yandex_vpc_security_group.runner_sg[0].id : null

  ansible_inventory_base = <<-YAML
    ---
    all:
      children:
        k3s_hosts:
          hosts:
            k3s:
              ansible_host: ${local.k3s_ansible_host}
              private_ip: ${local.k3s_private_ip}
    YAML

  # The runner block is only rendered when the runner VM exists. The format
  # call lives in the selected branch of the conditional so it is never
  # evaluated (and never references a missing resource) when the runner is
  # disabled. The block is indented to align with the k3s_hosts group.
  ansible_inventory_runner = local.runner_present ? format(
    "    github_runners:\n      hosts:\n        runner:\n          ansible_host: %s\n          private_ip: %s\n",
    local.runner_ansible_host,
    local.runner_private_ip,
  ) : ""

  ansible_inventory_yaml = trimspace("${local.ansible_inventory_base}${local.ansible_inventory_runner}")
}
