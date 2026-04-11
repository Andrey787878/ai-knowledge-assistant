locals {
  required_vm_keys = toset(["db", "ollama", "n8n", "wiki"])

  vm_keys_present = alltrue([
    for vm_name in local.required_vm_keys :
    contains(keys(var.vm_specs), vm_name)
  ])

  vm_private_cidrs = {
    for vm_name, vm in var.vm_specs :
    vm_name => "${vm.private_ip}/32"
  }
}
