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
    description = "Kubernetes API access from admin CIDRs and runner private IP"
    protocol       = "TCP"
    port           = 6443
    v4_cidr_blocks = distinct(concat(
      var.kube_api_allowed_cidrs,
      var.runner_enabled ? ["${local.runner_spec.private_ip}/32"] : []
    ))
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

resource "yandex_vpc_security_group" "runner_sg" {
  count       = var.runner_enabled ? 1 : 0
  name        = "github-runner-sg"
  description = "Ingress/egress policy for the GitHub Actions self-hosted runner VM."
  network_id  = yandex_vpc_network.main.id

  ingress {
    description    = "SSH access to runner VM from admin CIDRs"
    protocol       = "TCP"
    port           = 22
    v4_cidr_blocks = var.firewall_admin_ssh_sources
  }

  egress {
    description    = "HTTP for Ubuntu apt mirrors and package metadata"
    protocol       = "TCP"
    port           = 80
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description    = "HTTPS to GitHub API, Actions runner and downloads"
    protocol       = "TCP"
    port           = 443
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description    = "DNS (UDP) for runner name resolution"
    protocol       = "UDP"
    port           = 53
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description    = "DNS (TCP) for runner name resolution"
    protocol       = "TCP"
    port           = 53
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description    = "Kubernetes API access to k3s server private IP"
    protocol       = "TCP"
    port           = 6443
    v4_cidr_blocks = ["${local.k3s_spec.private_ip}/32"]
  }
}
