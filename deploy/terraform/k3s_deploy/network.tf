resource "yandex_vpc_network" "main" {
  name = var.network_name
}

resource "yandex_vpc_gateway" "private_egress" {
  name = "k3s-private-egress-gw"

  shared_egress_gateway {}
}

resource "yandex_vpc_route_table" "main" {
  name       = "k3s-main-rt"
  network_id = yandex_vpc_network.main.id

  static_route {
    destination_prefix = "0.0.0.0/0"
    gateway_id         = yandex_vpc_gateway.private_egress.id
  }
}

resource "yandex_vpc_subnet" "main" {
  name           = var.subnet_name
  zone           = var.zone
  network_id     = yandex_vpc_network.main.id
  v4_cidr_blocks = [var.subnet_cidr]
  route_table_id = yandex_vpc_route_table.main.id
}
