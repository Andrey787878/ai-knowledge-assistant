data "yandex_compute_image" "os" {
  family = var.image_family
}

resource "yandex_compute_instance" "vm" {
  for_each = var.vm_specs

  name        = each.key
  zone        = var.zone
  platform_id = var.platform_id

  lifecycle {
    precondition {
      condition     = local.vm_keys_present
      error_message = "vm_specs must include all required keys: db, ollama, n8n, wiki."
    }

    precondition {
      condition     = contains(["private", "public"], each.value.subnet)
      error_message = "vm_specs.${each.key}.subnet must be 'private' or 'public'."
    }

    precondition {
      condition = (
        each.key == "wiki"
        ? (each.value.subnet == "public" && each.value.nat)
        : (each.value.subnet == "private" && !each.value.nat)
      )
      error_message = "wiki must be public+nat=true; db/ollama/n8n must be private+nat=false."
    }
  }

  resources {
    cores         = each.value.cores
    memory        = each.value.memory
    core_fraction = each.value.core_fraction
  }

  scheduling_policy {
    preemptible = var.preemptible
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.os.id
      size     = each.value.disk_size_gb
      type     = each.value.disk_type
    }
  }

  network_interface {
    subnet_id  = each.value.subnet == "public" ? yandex_vpc_subnet.public.id : yandex_vpc_subnet.private.id
    ip_address = each.value.private_ip
    nat        = each.value.nat
    security_group_ids = each.key == "wiki" ? [
      yandex_vpc_security_group.bastion_sg.id
      ] : [
      yandex_vpc_security_group.private_sg.id
    ]
  }

  metadata = {
    ssh-keys = "${var.ssh_username}:${file(pathexpand(var.ssh_public_key_path))}"
  }
}
