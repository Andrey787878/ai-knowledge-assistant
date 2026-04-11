resource "yandex_vpc_security_group" "k3s_sg" {
  name        = "k3s-single-node-sg"
  description = "Ingress policy for single-node k3s VM."
  network_id  = yandex_vpc_network.main.id

  ingress {
    description    = "SSH access to k3s VM from admin CIDRs"
    protocol       = "TCP"
    port           = 22
    v4_cidr_blocks = var.firewall_admin_ssh_sources
  }

  ingress {
    description    = "Kubernetes API access from admin CIDRs"
    protocol       = "TCP"
    port           = 6443
    v4_cidr_blocks = var.kube_api_allowed_cidrs
  }

  ingress {
    description    = "HTTP for ACME HTTP-01 and redirect to HTTPS"
    protocol       = "TCP"
    port           = 80
    v4_cidr_blocks = var.edge_http_cidrs
  }

  ingress {
    description    = "HTTPS to edge ingress controller"
    protocol       = "TCP"
    port           = 443
    v4_cidr_blocks = var.edge_allowed_client_cidrs
  }

  egress {
    description    = "Allow all outbound traffic"
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}
