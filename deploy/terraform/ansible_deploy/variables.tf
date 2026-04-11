variable "yc_token" {
  description = "Yandex Cloud IAM token."
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "cloud_id" {
  description = "Yandex Cloud cloud_id."
  type        = string
}

variable "folder_id" {
  description = "Yandex Cloud folder_id."
  type        = string
}

variable "zone" {
  description = "Default availability zone for the stack."
  type        = string
  default     = "ru-central1-b"
}

variable "network_name" {
  description = "VPC network name."
  type        = string
  default     = "vm-net"
}

variable "public_subnet_name" {
  description = "Public subnet name (edge/bastion hosts)."
  type        = string
  default     = "vm-public-a"
}

variable "public_subnet_cidr" {
  description = "Public subnet CIDR."
  type        = string
  default     = "10.10.0.16/28"

  validation {
    condition     = can(cidrhost(var.public_subnet_cidr, 0))
    error_message = "public_subnet_cidr must be a valid CIDR."
  }
}

variable "private_subnet_name" {
  description = "Private subnet name (db/ollama/n8n hosts)."
  type        = string
  default     = "vm-private-a"
}

variable "private_subnet_cidr" {
  description = "Private subnet CIDR."
  type        = string
  default     = "10.10.0.0/28"

  validation {
    condition     = can(cidrhost(var.private_subnet_cidr, 0))
    error_message = "private_subnet_cidr must be a valid CIDR."
  }
}

variable "ssh_username" {
  description = "Linux username injected into VM metadata ssh-keys."
  type        = string
  default     = "ubuntu"
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key used for VM access."
  type        = string
  default     = "~/.ssh/ansible_deploy.pub"
}

variable "image_family" {
  description = "Yandex Compute image family for all VMs."
  type        = string
  default     = "ubuntu-2204-lts"
}

variable "platform_id" {
  description = "Yandex Compute platform id."
  type        = string
  default     = "standard-v4a"
}

variable "preemptible" {
  description = "Whether VMs should be preemptible."
  type        = bool
  default     = true
}

variable "vm_specs" {
  description = "Specs for each VM in the 4-node Ansible stage."
  type = map(object({
    private_ip    = string
    subnet        = string
    cores         = number
    memory        = number
    core_fraction = number
    disk_size_gb  = number
    disk_type     = string
    nat           = bool
  }))

  default = {
    db = {
      private_ip    = "10.10.0.3"
      subnet        = "private"
      cores         = 2
      memory        = 2
      core_fraction = 50
      disk_size_gb  = 20
      disk_type     = "network-hdd"
      nat           = false
    }
    ollama = {
      private_ip    = "10.10.0.4"
      subnet        = "private"
      cores         = 2
      memory        = 4
      core_fraction = 100
      disk_size_gb  = 20
      disk_type     = "network-ssd"
      nat           = false
    }
    n8n = {
      private_ip    = "10.10.0.5"
      subnet        = "private"
      cores         = 2
      memory        = 4
      core_fraction = 50
      disk_size_gb  = 20
      disk_type     = "network-hdd"
      nat           = false
    }
    wiki = {
      private_ip    = "10.10.0.19"
      subnet        = "public"
      cores         = 2
      memory        = 2
      core_fraction = 50
      disk_size_gb  = 15
      disk_type     = "network-hdd"
      nat           = true
    }
  }

  validation {
    condition = alltrue([
      for vm_name, vm in var.vm_specs : contains(["private", "public"], vm.subnet)
    ])
    error_message = "Each vm_specs[*].subnet must be either private or public."
  }
}

variable "firewall_admin_ssh_sources" {
  description = "Admin CIDRs allowed to SSH into bastion/wiki VM."
  type        = list(string)
  sensitive   = true

  validation {
    condition     = length(var.firewall_admin_ssh_sources) > 0 && alltrue([for cidr in var.firewall_admin_ssh_sources : can(cidrhost(cidr, 0))])
    error_message = "firewall_admin_ssh_sources must contain at least one valid CIDR."
  }
}

variable "edge_allowed_client_cidrs" {
  description = "Client CIDRs allowed to access edge HTTPS (wiki/n8n through reverse proxy)."
  type        = list(string)
  sensitive   = true

  validation {
    condition     = length(var.edge_allowed_client_cidrs) > 0 && alltrue([for cidr in var.edge_allowed_client_cidrs : can(cidrhost(cidr, 0))])
    error_message = "edge_allowed_client_cidrs must contain at least one valid CIDR."
  }
}

variable "edge_http_cidrs" {
  description = "CIDRs allowed to access edge HTTP 80 (redirect + ACME HTTP-01)."
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = length(var.edge_http_cidrs) > 0 && alltrue([for cidr in var.edge_http_cidrs : can(cidrhost(cidr, 0))])
    error_message = "edge_http_cidrs must contain at least one valid CIDR."
  }
}
