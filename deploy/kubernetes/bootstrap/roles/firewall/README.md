# firewall

Роль для настройки host firewall (UFW) на VM этапа B в bootstrap.
Роль host-agnostic: набор inbound TCP-правил задаётся через переменную
`firewall_tcp_rules`, поэтому одна и та же роль применяется и к `k3s` хосту,
и к `runner` хосту с разными правилами.

## Структура роли

```text
.
├── README.md
├── defaults/main.yml
└── tasks/
    ├── main.yml
    ├── validate.yml
    ├── ufw.yml
    └── verify.yml
```

## Что делает

- Проверяет поддерживаемую ОС (`Debian` family).
- Валидирует базовые firewall-параметры и структуру `firewall_tcp_rules`.
- Устанавливает `ufw`.
- Применяет default policies:
  - incoming: `deny`
  - outgoing: `allow`
- Разрешает inbound TCP-порты по source CIDR согласно `firewall_tcp_rules`.
- Включает UFW.
- Проверяет:
  - `Status: active`
  - default policies
  - наличие каждого порта и каждого source CIDR в ufw rules.

## Модель правил

`firewall_tcp_rules` — список объектов:

```yaml
firewall_tcp_rules:
  - port: 22
    sources: "{{ firewall_admin_ssh_sources }}"
    description: "SSH access to public k3s host"
```

Каждое правило:
- `port` — TCP-порт (число или строка),
- `sources` — непустой список source CIDR,
- `description` — описание.

Правила задаются per host group в `group_vars`, а не хардкодятся в роли.

### k3s host

`inventories/cloud/group_vars/k3s_hosts/main.yml`:

- `22` от `firewall_admin_ssh_sources`
- `6443` от `kube_api_allowed_cidrs` и автоматически добавленных private `/32`
  адресов из inventory group `github_runners`
- `80` от `edge_http_cidrs`
- `443` от `edge_allowed_client_cidrs`

### runner host

`inventories/cloud/group_vars/github_runners/main.yml`:

- `22` только от private `/32` адресов из inventory group `k3s_hosts`

Egress на host firewall: default outgoing `allow`. Внешний perimeter
ограничивается cloud Security Group (см. Terraform README).

## Граница ответственности

Роль управляет только host firewall на VM.

Роль не управляет cloud security groups и не настраивает k3s / runner.

## Переменные

Основные переменные из `defaults/main.yml`:

- `firewall_package` - пакет firewall (по умолчанию `ufw`).
- `firewall_default_incoming_policy` - default incoming policy.
- `firewall_default_outgoing_policy` - default outgoing policy.
- `firewall_tcp_rules` - список inbound TCP-правил (port/sources/description).
- `firewall_admin_ssh_sources` - CIDR-лист для `22/tcp` на публичном `k3s`.
- `kube_api_allowed_cidrs` - CIDR-ы для `6443/tcp` (k3s).
- `edge_http_cidrs` - CIDR-ы для `80/tcp` (k3s).
- `edge_allowed_client_cidrs` - CIDR-ы для `443/tcp` (k3s).
- `firewall_apt_*` - apt таймауты/ретраи.

Значения CIDR задаются в `group_vars/<group>/zz-local.yml` (gitignored)
или через vault overrides.

## Использование

```yaml
- hosts: k3s_hosts
  become: true
  roles:
    - firewall

- hosts: github_runners
  become: true
  roles:
    - firewall
```

## Быстрая проверка

```bash
cd deploy/kubernetes/bootstrap
ansible -i inventories/cloud/hosts.yml k3s_hosts -b -m command -a "ufw status verbose"
ansible -i inventories/cloud/hosts.yml github_runners -b -m command -a "ufw status verbose"
```
