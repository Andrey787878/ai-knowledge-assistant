resource "yandex_vpc_network" "main" {
  name = var.network_name
}

resource "yandex_vpc_gateway" "private_egress" {
  name = "ansible-private-egress-gw"
  shared_egress_gateway {}
}

resource "yandex_vpc_route_table" "private" {
  name       = "ansible-private-rt"
  network_id = yandex_vpc_network.main.id

  static_route {
    destination_prefix = "0.0.0.0/0"
    gateway_id         = yandex_vpc_gateway.private_egress.id
  }
}

resource "yandex_vpc_subnet" "public" {
  name           = var.public_subnet_name
  zone           = var.zone
  network_id     = yandex_vpc_network.main.id
  v4_cidr_blocks = [var.public_subnet_cidr]
}

resource "yandex_vpc_subnet" "private" {
  name           = var.private_subnet_name
  zone           = var.zone
  network_id     = yandex_vpc_network.main.id
  v4_cidr_blocks = [var.private_subnet_cidr]
  route_table_id = yandex_vpc_route_table.private.id
}
