locals {
  k3s_spec         = var.vm_specs["k3s_vm"]
  k3s_private_cidr = "${local.k3s_spec.private_ip}/32"

  ingress_ports = [80, 443]
  admin_ports   = [22, 6443]
}
