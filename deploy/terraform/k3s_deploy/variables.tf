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
  default     = "k3s-net"
}

variable "subnet_name" {
  description = "Subnet name"
  type        = string
  default     = "k3s-a"
}

variable "subnet_cidr" {
  description = "Subnet CIDR."
  type        = string
  default     = "10.20.0.0/24"

  validation {
    condition     = can(cidrhost(var.subnet_cidr, 0))
    error_message = "subnet_cidr must be a valid CIDR."
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
  default     = "~/.ssh/k3s_deploy.pub"
}

variable "image_family" {
  description = "Yandex Compute image family for VM."
  type        = string
  default     = "ubuntu-2204-lts"
}

variable "platform_id" {
  description = "Yandex Compute platform id."
  type        = string
  default     = "standard-v4a"
}

variable "preemptible" {
  description = "Whether VM should be preemptible."
  type        = bool
  default     = true
}

variable "vm_specs" {
  description = "Specs for VM in the kubernetes stage."
  type = map(object({
    private_ip    = string
    cores         = number
    memory        = number
    core_fraction = number
    disk_size_gb  = number
    disk_type     = string
    nat           = bool
  }))

  default = {
    k3s_vm = {
      private_ip    = "10.20.0.3"
      cores         = 8
      memory        = 16
      core_fraction = 100
      disk_size_gb  = 80
      disk_type     = "network-ssd"
      nat           = true
    }
  }
}

variable "edge_allowed_client_cidrs" {
  description = "Client CIDRs allowed to access edge HTTPS (wiki/n8n through ingress controller)."
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

variable "firewall_admin_ssh_sources" {
  description = "Admin CIDRs allowed to access SSH (22/tcp)."
  type        = list(string)
  sensitive   = true

  validation {
    condition     = length(var.firewall_admin_ssh_sources) > 0 && alltrue([for cidr in var.firewall_admin_ssh_sources : can(cidrhost(cidr, 0))])
    error_message = "firewall_admin_ssh_sources must contain at least one valid CIDR."
  }
}

variable "kube_api_allowed_cidrs" {
  description = "CIDRs allowed to access Kubernetes API (6443/tcp)."
  type        = list(string)
  sensitive   = true

  validation {
    condition     = length(var.kube_api_allowed_cidrs) > 0 && alltrue([for cidr in var.kube_api_allowed_cidrs : can(cidrhost(cidr, 0))])
    error_message = "kube_api_allowed_cidrs must contain at least one valid CIDR."
  }
}
