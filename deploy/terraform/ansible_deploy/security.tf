resource "yandex_vpc_security_group" "bastion_sg" {
  name        = "ansible-bastion-sg"
  description = "Ingress policy for wiki edge+bastion VM."
  network_id  = yandex_vpc_network.main.id

  ingress {
    description    = "SSH access to bastion/wiki from admin CIDRs"
    protocol       = "TCP"
    port           = 22
    v4_cidr_blocks = var.firewall_admin_ssh_sources
  }

  ingress {
    description    = "HTTP for ACME HTTP-01 and redirect to HTTPS"
    protocol       = "TCP"
    port           = 80
    v4_cidr_blocks = var.edge_http_cidrs
  }

  ingress {
    description    = "HTTPS to edge reverse proxy"
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

resource "yandex_vpc_security_group" "private_sg" {
  name        = "ansible-private-sg"
  description = "Ingress policy for db/ollama/n8n private VMs."
  network_id  = yandex_vpc_network.main.id

  ingress {
    description    = "SSH from bastion/wiki private IP"
    protocol       = "TCP"
    port           = 22
    v4_cidr_blocks = [local.vm_private_cidrs["wiki"]]
  }

  ingress {
    description    = "PostgreSQL from n8n and wiki"
    protocol       = "TCP"
    port           = 5432
    v4_cidr_blocks = [local.vm_private_cidrs["n8n"], local.vm_private_cidrs["wiki"]]
  }

  ingress {
    description    = "n8n editor/API from edge proxy on wiki"
    protocol       = "TCP"
    port           = 5678
    v4_cidr_blocks = [local.vm_private_cidrs["wiki"]]
  }

  ingress {
    description    = "Ollama API from n8n host"
    protocol       = "TCP"
    port           = 11434
    v4_cidr_blocks = [local.vm_private_cidrs["n8n"]]
  }

  egress {
    description    = "Allow all outbound traffic"
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}
