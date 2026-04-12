data "yandex_compute_image" "os" {
  family = var.image_family
}

resource "yandex_compute_instance" "k3s" {
  name        = "k3s"
  zone        = var.zone
  platform_id = var.platform_id

  resources {
    cores         = local.k3s_spec.cores
    memory        = local.k3s_spec.memory
    core_fraction = local.k3s_spec.core_fraction
  }

  scheduling_policy {
    preemptible = var.preemptible
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.os.id
      size     = local.k3s_spec.disk_size_gb
      type     = local.k3s_spec.disk_type
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.main.id
    ip_address         = local.k3s_spec.private_ip
    nat                = local.k3s_spec.nat
    security_group_ids = [yandex_vpc_security_group.k3s_sg.id]
  }

  metadata = {
    ssh-keys = "${var.ssh_username}:${file(pathexpand(var.ssh_public_key_path))}"
  }
}